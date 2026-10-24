extends RefCounted
## Wraps a face photo onto a LabCharacter's head: bakes a front projection of the
## rest-pose head into UV2 (plus a blend weight in COLOR.r) so the photo follows
## skinning, and swaps the head/eye materials for a lit skin+photo shader.

const EYE_L_PX := Vector2(178.0, 296.0)
const EYE_R_PX := Vector2(345.0, 279.0)
const PHOTO_PX := Vector2(570.0, 720.0)
const CHEEK_PX: Array[Vector2] = [Vector2(205.0, 395.0), Vector2(330.0, 385.0), Vector2(250.0, 200.0)]
const FACE_X_PX := Vector2(150.0, 430.0)
const OVAL_HALF_W: float = 0.088
const OVAL_UP: float = 0.095
const OVAL_DOWN: float = 0.118

const SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform float normal_depth = 1.0;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float roughness = 0.62;
uniform float specular = 0.38;
uniform float rim = 0.5;
uniform vec3 skin_tint = vec3(1.0);
uniform sampler2D face_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float face_gain = 0.88;
uniform float face_glow = 0.06;
uniform float blur_lod = 5.0;
uniform float face_mix = 1.0;

void fragment() {
	vec3 skin = texture(base_tex, UV).rgb * base_color.rgb * skin_tint;
	vec4 f = texture(face_tex, UV2);
	f.rgb = clamp((f.rgb - 0.45) * 1.18 + 0.45, 0.0, 1.0);
	vec2 edge = smoothstep(vec2(0.0), vec2(0.02), UV2) * smoothstep(vec2(0.0), vec2(0.02), vec2(1.0) - UV2);
	float a = min(f.a, textureLod(face_tex, UV2, blur_lod).a);
	float m = clamp(COLOR.r, 0.0, 1.0) * smoothstep(0.7, 0.99, a) * face_mix * edge.x * edge.y;
	ALBEDO = mix(skin, f.rgb * face_gain, m);
	ROUGHNESS = mix(roughness * texture(rough_tex, UV).r, 0.62, m);
	SPECULAR = mix(specular, 0.2, m);
	EMISSION = f.rgb * m * face_glow;
	RIM = rim * (1.0 - 0.9 * m);
	RIM_TINT = 0.5;
	if (has_normal) {
		NORMAL_MAP = mix(texture(normal_tex, UV).rgb, vec3(0.5, 0.5, 1.0), m);
		NORMAL_MAP_DEPTH = normal_depth;
	}
}
"""

static func apply(body: LabCharacter, tex: Texture2D, img: Image) -> bool:
	var sk := body.skeleton
	if sk == null or tex == null:
		return false
	var head := sk.find_bone("Head")
	var eyes: MeshInstance3D = sk.find_child("Eyes", false, false)
	var skin_mi: MeshInstance3D = null
	var skin_surf: int = -1
	var best: int = 0
	for n in sk.get_children():
		if not n is MeshInstance3D or n == eyes:
			continue
		var mi: MeshInstance3D = n
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat and String(mat.resource_name).begins_with("MI_Hair"):
				continue
			var c := _head_count(mi.mesh, s, head)
			if c > best:
				best = c
				skin_mi = mi
				skin_surf = s
	if skin_mi == null or eyes == null or best < 50:
		return false
	var lr := _eye_centres(eyes.mesh)
	if lr.size() < 2 or lr[1].x - lr[0].x < 0.01:
		return false
	var map := _Map.new(lr[0], lr[1], img)
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var tint := _skin_tint(img, skin_mi.get_active_material(skin_surf))
	_rebuild(skin_mi, {skin_surf: true}, map, false, shader, tex, tint)
	var eye_surfs := {}
	for s in eyes.mesh.get_surface_count():
		eye_surfs[s] = true
	_rebuild(eyes, eye_surfs, map, true, shader, tex, Vector3.ONE)
	for n in sk.get_children():
		if n is MeshInstance3D and String(n.name).begins_with("Eyebrows"):
			n.visible = false
	return true

class _Map:
	var mid: Vector3
	var k: float
	var ang: float
	var mid_px: Vector2
	var size_px: Vector2
	func _init(l: Vector3, r: Vector3, img: Image) -> void:
		mid = (l + r) * 0.5
		size_px = Vector2(img.get_width(), img.get_height())
		var sc := size_px / PHOTO_PX
		var lp := EYE_L_PX * sc
		var rp := EYE_R_PX * sc
		mid_px = (lp + rp) * 0.5
		k = lp.distance_to(rp) / (r.x - l.x)
		ang = (rp - lp).angle()
	func uv(p: Vector3) -> Vector2:
		var v := Vector2(p.x - mid.x, mid.y - p.y) * k
		return (mid_px + v.rotated(ang)) / size_px
	func weight(p: Vector3, n: Vector3) -> float:
		var dy := p.y - mid.y
		var ex := (p.x - mid.x) / OVAL_HALF_W
		var ey := dy / (OVAL_UP if dy > 0.0 else OVAL_DOWN)
		var oval := 1.0 - smoothstep(0.8, 1.0, sqrt(ex * ex + ey * ey))
		var front := smoothstep(0.15, 0.5, n.z)
		var px := uv(p).x * PHOTO_PX.x
		var span := smoothstep(FACE_X_PX.x, FACE_X_PX.x + 40.0, px) * (1.0 - smoothstep(FACE_X_PX.y - 40.0, FACE_X_PX.y, px))
		return oval * front * span

static func _head_count(mesh: Mesh, s: int, head: int) -> int:
	var arr := mesh.surface_get_arrays(s)
	if arr[Mesh.ARRAY_BONES] == null:
		return 0
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var nb: int = 8 if mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
	var c := 0
	for i in bones.size() / nb:
		var hw := 0.0
		for j in nb:
			if bones[i * nb + j] == head:
				hw += w[i * nb + j]
		if hw > 0.5:
			c += 1
	return c

static func _eye_centres(mesh: Mesh) -> Array[Vector3]:
	var sum_l := Vector3.ZERO
	var sum_r := Vector3.ZERO
	var nl := 0
	var nr := 0
	for s in mesh.get_surface_count():
		var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for p in v:
			if p.x < 0.0:
				sum_l += p
				nl += 1
			else:
				sum_r += p
				nr += 1
	if nl == 0 or nr == 0:
		return []
	return [sum_l / nl, sum_r / nr]

static func _skin_tint(img: Image, skin: Material) -> Vector3:
	if not skin is StandardMaterial3D:
		return Vector3.ONE
	var sc := Vector2(img.get_width(), img.get_height()) / PHOTO_PX
	var photo := Color(0, 0, 0)
	var n := 0
	for c in CHEEK_PX:
		var p := Vector2i(c * sc)
		if p.x < img.get_width() and p.y < img.get_height() and img.get_pixelv(p).a > 0.9:
			photo += img.get_pixelv(p)
			n += 1
	var sm: StandardMaterial3D = skin
	var base := sm.albedo_color
	if sm.albedo_texture:
		var t := sm.albedo_texture.get_image()
		if t:
			if t.is_compressed():
				t.decompress()
			t.resize(8, 8, Image.INTERPOLATE_BILINEAR)
			var avg := Color(0, 0, 0)
			var cnt := 0
			for y in 8:
				for x in 8:
					var px := t.get_pixel(x, y)
					if px.a > 0.5 and px.r > px.b:
						avg += px
						cnt += 1
			if cnt > 0:
				base = base * (avg / cnt)
	if n == 0 or base.r <= 0.01:
		return Vector3.ONE
	photo = photo / n
	var pl := photo.srgb_to_linear()
	var bl := base.srgb_to_linear()
	var t3 := Vector3(pl.r / maxf(bl.r, 0.01), pl.g / maxf(bl.g, 0.01), pl.b / maxf(bl.b, 0.01))
	return Vector3.ONE.lerp(t3, 0.25).clamp(Vector3.ONE * 0.85, Vector3.ONE * 1.2)

static func _rebuild(mi: MeshInstance3D, targets: Dictionary, map: _Map, full: bool, shader: Shader, tex: Texture2D, tint: Vector3) -> void:
	var src: Mesh = mi.mesh
	var keep: Array[Material] = []
	for s in src.get_surface_count():
		keep.append(mi.get_surface_override_material(s))
	var dst := ArrayMesh.new()
	if src is ArrayMesh:
		dst.blend_shape_mode = (src as ArrayMesh).blend_shape_mode
		for b in (src as ArrayMesh).get_blend_shape_count():
			dst.add_blend_shape((src as ArrayMesh).get_blend_shape_name(b))
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		if targets.has(s):
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uv2 := PackedVector2Array()
			var col := PackedColorArray()
			uv2.resize(v.size())
			col.resize(v.size())
			for i in v.size():
				uv2[i] = map.uv(v[i])
				var w := 1.0 if full else map.weight(v[i], nrm[i] if i < nrm.size() else Vector3.BACK)
				col[i] = Color(w, 0.0, 0.0, 1.0)
			arr[Mesh.ARRAY_TEX_UV2] = uv2
			arr[Mesh.ARRAY_COLOR] = col
		var fmt: int = src.surface_get_format(s)
		dst.add_surface_from_arrays(src.surface_get_primitive_type(s), arr, src.surface_get_blend_shape_arrays(s), {}, fmt & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | (0xFFF << Mesh.ARRAY_FORMAT_CUSTOM_BASE)))
		dst.surface_set_material(s, src.surface_get_material(s))
		if src is ArrayMesh:
			dst.surface_set_name(s, (src as ArrayMesh).surface_get_name(s))
	var old: Array[Material] = []
	for s in src.get_surface_count():
		old.append(mi.get_active_material(s))
	mi.mesh = dst
	for s in dst.get_surface_count():
		if targets.has(s):
			mi.set_surface_override_material(s, _material(old[s], shader, tex, tint, full))
		else:
			mi.set_surface_override_material(s, keep[s])

static func _material(src: Material, shader: Shader, tex: Texture2D, tint: Vector3, eyes: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("face_tex", tex)
	m.set_shader_parameter("skin_tint", tint)
	if src is StandardMaterial3D:
		var sm: StandardMaterial3D = src
		m.set_shader_parameter("base_color", sm.albedo_color)
		m.set_shader_parameter("base_tex", sm.albedo_texture)
		if sm.normal_enabled and sm.normal_texture:
			m.set_shader_parameter("normal_tex", sm.normal_texture)
			m.set_shader_parameter("has_normal", true)
			m.set_shader_parameter("normal_depth", sm.normal_scale)
		if sm.roughness_texture:
			m.set_shader_parameter("rough_tex", sm.roughness_texture)
		m.set_shader_parameter("roughness", sm.roughness)
		m.set_shader_parameter("specular", sm.metallic_specular)
		m.set_shader_parameter("rim", sm.rim if sm.rim_enabled else 0.0)
	if eyes:
		m.set_shader_parameter("rim", 0.0)
	return m
