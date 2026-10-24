extends Node
## Local player profile: cosmetic catalog (COMMON / RARE / EPIC / LEGENDARY),
## challenges, lifetime stats, unlocked items and the equipped loadout, saved per
## machine in user://profile.cfg. RoundDirector feeds it round and match results;
## minigames may add mode stats with bump(). Bots never earn. Autoload singleton.

signal loadout_changed()
signal unlocked(item_ids)

enum { COMMON, RARE, EPIC, LEGENDARY }

const SAVE_PATH: String = "user://profile.cfg"
const SAVE_VERSION: int = 1
const RARITY_NAMES: Array[String] = ["COMMON", "RARE", "EPIC", "LEGENDARY"]
const RARITY_COLORS: Array[Color] = [Color("a9c2ae"), Color("4aa8ff"), Color("c27bff"), Color("ffc83d")]
const CATEGORIES: Array[String] = ["body", "suit", "pattern", "hair", "hat", "title", "death_fx"]
const CATEGORY_NAMES: Dictionary = {"body": "BODY", "suit": "SUIT", "pattern": "PATTERN", "hair": "HAIR", "hat": "HAT", "title": "TITLE", "death_fx": "DEATH FX"}
const DEFAULT_LOADOUT: Dictionary = {"body": "body_male", "suit": "suit_rust", "pattern": "pattern_none", "hair": "hair_auto", "hat": "hat_hardhat", "title": "title_subject", "death_fx": "death_blood"}

const ITEMS: Array[Dictionary] = [
	{"id": "body_male", "cat": "body", "name": "Male Subject", "r": COMMON, "v": "male", "free": true},
	{"id": "body_female", "cat": "body", "name": "Female Subject", "r": COMMON, "v": "female", "free": true},

	{"id": "suit_rust", "cat": "suit", "name": "Rust Red", "r": COMMON, "v": Color("a33a2c"), "free": true},
	{"id": "suit_navy", "cat": "suit", "name": "Navy", "r": COMMON, "v": Color("2f5684"), "free": true},
	{"id": "suit_olive", "cat": "suit", "name": "Olive Drab", "r": COMMON, "v": Color("5f7236"), "free": true},
	{"id": "suit_mustard", "cat": "suit", "name": "Mustard", "r": COMMON, "v": Color("b8902a"), "free": true},
	{"id": "suit_orange", "cat": "suit", "name": "Safety Orange", "r": COMMON, "v": Color("b8642a"), "free": true},
	{"id": "suit_teal", "cat": "suit", "name": "Teal", "r": COMMON, "v": Color("2c7470"), "free": true},
	{"id": "suit_maroon", "cat": "suit", "name": "Maroon", "r": COMMON, "v": Color("74304a"), "free": true},
	{"id": "suit_slate", "cat": "suit", "name": "Slate", "r": COMMON, "v": Color("6a6f7c"), "free": true},
	{"id": "suit_khaki", "cat": "suit", "name": "Khaki", "r": COMMON, "v": Color("9a8a5e")},
	{"id": "suit_mud", "cat": "suit", "name": "Mud Brown", "r": COMMON, "v": Color("5a4030")},
	{"id": "suit_scrubs", "cat": "suit", "name": "Scrub Green", "r": COMMON, "v": Color("4f8f78")},
	{"id": "suit_denim", "cat": "suit", "name": "Denim", "r": COMMON, "v": Color("3e5470")},
	{"id": "suit_hazmat", "cat": "suit", "name": "Hazmat Yellow", "r": RARE, "v": Color("d6b417")},
	{"id": "suit_bruise", "cat": "suit", "name": "Bruise Purple", "r": RARE, "v": Color("5a3477")},
	{"id": "suit_toxic", "cat": "suit", "name": "Toxic Lime", "r": RARE, "v": Color("7fbf1f")},
	{"id": "suit_coolant", "cat": "suit", "name": "Coolant Cyan", "r": RARE, "v": Color("2aa7c4")},
	{"id": "suit_flamingo", "cat": "suit", "name": "Flamingo Pink", "r": RARE, "v": Color("cf5e8e")},
	{"id": "suit_void", "cat": "suit", "name": "Void Black", "r": EPIC, "v": Color("1c1c1f")},
	{"id": "suit_bone", "cat": "suit", "name": "Bone White", "r": EPIC, "v": Color("c9c2ad")},
	{"id": "suit_arterial", "cat": "suit", "name": "Arterial Red", "r": EPIC, "v": Color("8e0a12")},

	{"id": "pattern_none", "cat": "pattern", "name": "Plain", "r": COMMON, "v": 0, "free": true},
	{"id": "pattern_filth", "cat": "pattern", "name": "Filthy", "r": COMMON, "v": 5},
	{"id": "pattern_rust", "cat": "pattern", "name": "Rusted", "r": COMMON, "v": 3},
	{"id": "pattern_hazard", "cat": "pattern", "name": "Hazard Stripes", "r": RARE, "v": 1},
	{"id": "pattern_camo", "cat": "pattern", "name": "Camo", "r": RARE, "v": 2},
	{"id": "pattern_inmate", "cat": "pattern", "name": "Inmate Bands", "r": RARE, "v": 9},
	{"id": "pattern_blood", "cat": "pattern", "name": "Blood-Soaked", "r": EPIC, "v": 4},
	{"id": "pattern_bio", "cat": "pattern", "name": "Biohazard Glow", "r": EPIC, "v": 6},
	{"id": "pattern_chrome", "cat": "pattern", "name": "Chrome", "r": LEGENDARY, "v": 7},
	{"id": "pattern_gold", "cat": "pattern", "name": "Solid Gold", "r": LEGENDARY, "v": 8},

	{"id": "hair_auto", "cat": "hair", "name": "Natural", "r": COMMON, "v": Color(0, 0, 0, 0), "free": true},
	{"id": "hair_black", "cat": "hair", "name": "Jet Black", "r": COMMON, "v": Color("120d0a"), "free": true},
	{"id": "hair_brown", "cat": "hair", "name": "Brown", "r": COMMON, "v": Color("5a3a22"), "free": true},
	{"id": "hair_blond", "cat": "hair", "name": "Bleach Blond", "r": COMMON, "v": Color("d8c27a")},
	{"id": "hair_ginger", "cat": "hair", "name": "Ginger", "r": COMMON, "v": Color("b0481c")},
	{"id": "hair_grey", "cat": "hair", "name": "Stress Grey", "r": RARE, "v": Color("9a9a96")},
	{"id": "hair_toxic", "cat": "hair", "name": "Toxic Green", "r": RARE, "v": Color("4fd13a")},
	{"id": "hair_blue", "cat": "hair", "name": "Electric Blue", "r": EPIC, "v": Color("2f6bff")},
	{"id": "hair_pink", "cat": "hair", "name": "Bubblegum", "r": EPIC, "v": Color("ff5fb4")},
	{"id": "hair_gold", "cat": "hair", "name": "Molten Gold", "r": LEGENDARY, "v": Color("ffbf2e")},

	{"id": "hat_none", "cat": "hat", "name": "Bare Head", "r": COMMON, "v": "", "free": true},
	{"id": "hat_hardhat", "cat": "hat", "name": "Hard Hat", "r": COMMON, "v": "hardhat", "free": true},
	{"id": "hat_beanie", "cat": "hat", "name": "Beanie", "r": COMMON, "v": "beanie", "free": true},
	{"id": "hat_bucket", "cat": "hat", "name": "Bucket Hat", "r": COMMON, "v": "bucket", "free": true},
	{"id": "hat_cone", "cat": "hat", "name": "Traffic Cone", "r": COMMON, "v": "cone", "free": true},
	{"id": "hat_fedora", "cat": "hat", "name": "Fedora", "r": COMMON, "v": "fedora"},
	{"id": "hat_shades", "cat": "hat", "name": "Shades", "r": COMMON, "v": "shades"},
	{"id": "hat_party", "cat": "hat", "name": "Party Hat", "r": RARE, "v": "party"},
	{"id": "hat_propeller", "cat": "hat", "name": "Propeller Cap", "r": RARE, "v": "propeller"},
	{"id": "hat_goggles", "cat": "hat", "name": "Lab Goggles", "r": RARE, "v": "goggles"},
	{"id": "hat_tophat", "cat": "hat", "name": "Top Hat", "r": EPIC, "v": "tophat"},
	{"id": "hat_hardhat_chrome", "cat": "hat", "name": "Chrome Hard Hat", "r": EPIC, "v": "hardhat", "tint": "chrome"},
	{"id": "hat_cone_blood", "cat": "hat", "name": "Bloody Cone", "r": EPIC, "v": "cone", "tint": "blood"},
	{"id": "hat_goggles_neon", "cat": "hat", "name": "Night Vision", "r": EPIC, "v": "goggles", "tint": "neon"},
	{"id": "hat_tophat_gold", "cat": "hat", "name": "Gold Top Hat", "r": LEGENDARY, "v": "tophat", "tint": "gold"},
	{"id": "hat_fedora_gold", "cat": "hat", "name": "Gold Fedora", "r": LEGENDARY, "v": "fedora", "tint": "gold"},

	{"id": "title_none", "cat": "title", "name": "No Title", "r": COMMON, "v": "", "free": true},
	{"id": "title_subject", "cat": "title", "name": "Test Subject", "r": COMMON, "v": "Test Subject", "free": true},
	{"id": "title_expendable", "cat": "title", "name": "Expendable", "r": COMMON, "v": "Expendable"},
	{"id": "title_labrat", "cat": "title", "name": "Lab Rat", "r": COMMON, "v": "Lab Rat"},
	{"id": "title_dummy", "cat": "title", "name": "Crash Test Dummy", "r": COMMON, "v": "Crash Test Dummy"},
	{"id": "title_disposable", "cat": "title", "name": "Disposable", "r": COMMON, "v": "Disposable"},
	{"id": "title_bait", "cat": "title", "name": "Sniper Bait", "r": COMMON, "v": "Sniper Bait"},
	{"id": "title_peabrain", "cat": "title", "name": "Pea Brain", "r": COMMON, "v": "Pea Brain"},
	{"id": "title_roadkill", "cat": "title", "name": "Roadkill", "r": COMMON, "v": "Roadkill"},
	{"id": "title_smoker", "cat": "title", "name": "Chain Smoker", "r": COMMON, "v": "Chain Smoker"},
	{"id": "title_mince", "cat": "title", "name": "Mince", "r": COMMON, "v": "Mince"},
	{"id": "title_dustbunny", "cat": "title", "name": "Dust Bunny", "r": COMMON, "v": "Dust Bunny"},
	{"id": "title_minesweeper", "cat": "title", "name": "Mine Sweeper", "r": RARE, "v": "Mine Sweeper"},
	{"id": "title_duck", "cat": "title", "name": "Lucky Duck", "r": RARE, "v": "Lucky Duck"},
	{"id": "title_gunsmith", "cat": "title", "name": "Gunsmith", "r": RARE, "v": "Gunsmith"},
	{"id": "title_commuter", "cat": "title", "name": "Commuter", "r": RARE, "v": "Commuter"},
	{"id": "title_clean", "cat": "title", "name": "Clean Hands", "r": RARE, "v": "Clean Hands"},
	{"id": "title_lungs", "cat": "title", "name": "Iron Lungs", "r": RARE, "v": "Iron Lungs"},
	{"id": "title_sculptor", "cat": "title", "name": "Sculptor", "r": RARE, "v": "Sculptor"},
	{"id": "title_qc", "cat": "title", "name": "Quality Control", "r": RARE, "v": "Quality Control"},
	{"id": "title_operator", "cat": "title", "name": "Certified Operator", "r": RARE, "v": "Certified Operator"},
	{"id": "title_surefooted", "cat": "title", "name": "Sure-Footed", "r": RARE, "v": "Sure-Footed"},
	{"id": "title_fasthand", "cat": "title", "name": "Fastest Hand", "r": RARE, "v": "Fastest Hand"},
	{"id": "title_chairhog", "cat": "title", "name": "Chair Hog", "r": RARE, "v": "Chair Hog"},
	{"id": "title_defused", "cat": "title", "name": "Defused", "r": RARE, "v": "Defused"},
	{"id": "title_marksman", "cat": "title", "name": "Marksman", "r": EPIC, "v": "Marksman"},
	{"id": "title_hardtarget", "cat": "title", "name": "Hard Target", "r": EPIC, "v": "Hard Target"},
	{"id": "title_zero", "cat": "title", "name": "Patient Zero", "r": EPIC, "v": "Patient Zero"},
	{"id": "title_apex", "cat": "title", "name": "Apex Subject", "r": EPIC, "v": "Apex Subject"},
	{"id": "title_untouchable", "cat": "title", "name": "Untouchable", "r": EPIC, "v": "Untouchable"},
	{"id": "title_eotm", "cat": "title", "name": "Employee of the Month", "r": LEGENDARY, "v": "Employee of the Month"},
	{"id": "title_head", "cat": "title", "name": "Head of Research", "r": LEGENDARY, "v": "Head of Research"},

	{"id": "death_blood", "cat": "death_fx", "name": "Standard Blood", "r": COMMON, "v": "blood", "free": true},
	{"id": "death_gore", "cat": "death_fx", "name": "Extra Gore", "r": RARE, "v": "gore"},
	{"id": "death_sparks", "cat": "death_fx", "name": "Short Circuit", "r": RARE, "v": "sparks"},
	{"id": "death_ash", "cat": "death_fx", "name": "Up In Smoke", "r": EPIC, "v": "ash"},
	{"id": "death_boom", "cat": "death_fx", "name": "Self-Destruct", "r": EPIC, "v": "boom"},
	{"id": "death_confetti", "cat": "death_fx", "name": "Confetti Burst", "r": LEGENDARY, "v": "confetti"},
	{"id": "death_gold", "cat": "death_fx", "name": "Golden Gore", "r": LEGENDARY, "v": "gold"},
]

const CHALLENGES: Array[Dictionary] = [
	{"id": "c_first", "text": "Complete your first test", "stat": "rounds_played", "goal": 1, "reward": "title_expendable"},
	{"id": "c_rounds10", "text": "Play 10 tests", "stat": "rounds_played", "goal": 10, "reward": "suit_khaki"},
	{"id": "c_rounds50", "text": "Play 50 tests", "stat": "rounds_played", "goal": 50, "reward": "pattern_filth"},
	{"id": "c_rounds150", "text": "Play 150 tests", "stat": "rounds_played", "goal": 150, "reward": "suit_void"},
	{"id": "c_rounds400", "text": "Play 400 tests", "stat": "rounds_played", "goal": 400, "reward": "title_head"},
	{"id": "c_win1", "text": "Win a test", "stat": "rounds_won", "goal": 1, "reward": "hat_fedora"},
	{"id": "c_win10", "text": "Win 10 tests", "stat": "rounds_won", "goal": 10, "reward": "hat_party"},
	{"id": "c_win50", "text": "Win 50 tests", "stat": "rounds_won", "goal": 50, "reward": "hat_tophat"},
	{"id": "c_win150", "text": "Win 150 tests", "stat": "rounds_won", "goal": 150, "reward": "hat_tophat_gold"},
	{"id": "c_match1", "text": "Finish a full session", "stat": "matches_played", "goal": 1, "reward": "title_labrat"},
	{"id": "c_match25", "text": "Finish 25 sessions", "stat": "matches_played", "goal": 25, "reward": "suit_toxic"},
	{"id": "c_mwin1", "text": "Win a session", "stat": "matches_won", "goal": 1, "reward": "suit_hazmat"},
	{"id": "c_mwin5", "text": "Win 5 sessions", "stat": "matches_won", "goal": 5, "reward": "pattern_blood"},
	{"id": "c_mwin10", "text": "Win 10 sessions", "stat": "matches_won", "goal": 10, "reward": "hair_gold"},
	{"id": "c_mwin25", "text": "Win 25 sessions", "stat": "matches_won", "goal": 25, "reward": "pattern_gold"},
	{"id": "c_podium10", "text": "Finish a session in the top 3 ten times", "stat": "match_podiums", "goal": 10, "reward": "hair_grey"},
	{"id": "c_top3_10", "text": "Finish a test in the top 3 ten times", "stat": "rounds_top3", "goal": 10, "reward": "suit_mud"},
	{"id": "c_top3_100", "text": "Finish a test in the top 3 a hundred times", "stat": "rounds_top3", "goal": 100, "reward": "title_apex"},
	{"id": "c_survive100", "text": "Survive 100 tests", "stat": "rounds_survived", "goal": 100, "reward": "pattern_chrome"},
	{"id": "c_flawless1", "text": "Win a test without dying", "stat": "flawless_wins", "goal": 1, "reward": "hat_shades"},
	{"id": "c_flawless5", "text": "Win 5 tests without dying", "stat": "flawless_wins", "goal": 5, "reward": "title_untouchable"},
	{"id": "c_flawless25", "text": "Win 25 tests without dying", "stat": "flawless_wins", "goal": 25, "reward": "title_eotm"},
	{"id": "c_die25", "text": "Die 25 times", "stat": "deaths", "goal": 25, "reward": "title_dummy"},
	{"id": "c_die100", "text": "Die 100 times", "stat": "deaths", "goal": 100, "reward": "death_gore"},
	{"id": "c_last10", "text": "Finish dead last 10 times", "stat": "last_places", "goal": 10, "reward": "title_disposable"},
	{"id": "c_streak3", "text": "Win 3 tests in a row", "stat": "win_streak_best", "goal": 3, "reward": "death_boom"},
	{"id": "c_streak5", "text": "Win 5 tests in a row", "stat": "win_streak_best", "goal": 5, "reward": "death_gold"},
	{"id": "c_allplay", "text": "Play every test at least once", "stat": "modes_played", "goal": 21, "reward": "hair_blond"},
	{"id": "c_won10modes", "text": "Win 10 different tests", "stat": "modes_won", "goal": 10, "reward": "death_ash"},
	{"id": "c_wonall", "text": "Win every test at least once", "stat": "modes_won", "goal": 21, "reward": "death_confetti"},

	{"id": "c_mine_surv", "text": "Survive 10 Minefield rounds", "stat": "m.minefield3d.survived", "goal": 10, "reward": "title_minesweeper"},
	{"id": "c_mine_win", "text": "Win Minefield 5 times", "stat": "m.minefield3d.won", "goal": 5, "reward": "pattern_hazard"},
	{"id": "c_dh_play", "text": "Play 5 Duck Hunt rounds", "stat": "m.duck_hunt.played", "goal": 5, "reward": "title_bait"},
	{"id": "c_dh_runner", "text": "Survive 10 Duck Hunt rounds as a runner", "stat": "m.duck_hunt.runner_survived", "goal": 10, "reward": "pattern_camo"},
	{"id": "c_dh_runner25", "text": "Survive 25 Duck Hunt rounds as a runner", "stat": "m.duck_hunt.runner_survived", "goal": 25, "reward": "title_hardtarget"},
	{"id": "c_dh_sniper", "text": "Win 3 Duck Hunt rounds as the sniper", "stat": "m.duck_hunt.sniper_won", "goal": 3, "reward": "hat_goggles_neon"},
	{"id": "c_dhc_escape", "text": "Reach the exit gate 10 times in Duck Hunt Classic", "stat": "m.duck_hunt_classic.escapes", "goal": 10, "reward": "title_duck"},
	{"id": "c_dhc_kills", "text": "Shoot 25 ducks as the Duck Hunt Classic sniper", "stat": "m.duck_hunt_classic.hunter_kills", "goal": 25, "reward": "hat_goggles"},
	{"id": "c_dhc_sweep", "text": "Win 3 Duck Hunt Classic hunts as the sniper (nobody escapes)", "stat": "m.duck_hunt_classic.sweeps", "goal": 3, "reward": "title_marksman"},
	{"id": "c_ff_kills", "text": "Shoot 10 subjects in Firearm Factory", "stat": "m.firearm_factory.kills", "goal": 10, "reward": "suit_arterial"},
	{"id": "c_ff_win", "text": "Win Firearm Factory 3 times", "stat": "m.firearm_factory.won", "goal": 3, "reward": "title_gunsmith"},
	{"id": "c_tm_clear", "text": "Clear your plate 5 times in Table Manners", "stat": "m.table_manners.cleared", "goal": 5, "reward": "hair_ginger"},
	{"id": "c_tm_choke", "text": "Choke 5 times in Table Manners", "stat": "m.table_manners.died", "goal": 5, "reward": "title_peabrain"},
	{"id": "c_th_exit", "text": "Reach the tunnel exit 10 times", "stat": "m.tunnel_hazard.escaped", "goal": 10, "reward": "title_commuter"},
	{"id": "c_th_die", "text": "Get flattened 10 times in Tunnel Hazard", "stat": "m.tunnel_hazard.died", "goal": 10, "reward": "title_roadkill"},
	{"id": "c_ij_clean", "text": "Finish Inside Job uninfected 5 times", "stat": "m.inside_job.clean_survived", "goal": 5, "reward": "title_clean"},
	{"id": "c_ij_zero", "text": "Finish top 3 in Inside Job as patient zero", "stat": "m.inside_job.zero_top3", "goal": 1, "reward": "title_zero"},
	{"id": "c_sb_smoke", "text": "Smoke 25 cigarettes in Smoke Break", "stat": "m.smoke_break.smoked", "goal": 25, "reward": "title_smoker"},
	{"id": "c_sb_win", "text": "Win Smoke Break 5 times", "stat": "m.smoke_break.won", "goal": 5, "reward": "title_lungs"},
	{"id": "c_cg_surv", "text": "Survive 10 Chisel Gauntlet rounds", "stat": "m.chisel_gauntlet.survived", "goal": 10, "reward": "title_sculptor"},
	{"id": "c_cg_win", "text": "Win Chisel Gauntlet 3 times", "stat": "m.chisel_gauntlet.won", "goal": 3, "reward": "suit_bone"},
	{"id": "c_tf_sort", "text": "Sort 50 items correctly in The Filter", "stat": "m.the_filter.sorted", "goal": 50, "reward": "suit_scrubs"},
	{"id": "c_tf_win", "text": "Win The Filter 3 times", "stat": "m.the_filter.won", "goal": 3, "reward": "title_qc"},
	{"id": "c_fc_deliver", "text": "Deliver 20 pallets in Forklift Certified", "stat": "m.forklift_certified.deliveries", "goal": 20, "reward": "title_operator"},
	{"id": "c_fc_win", "text": "Win Forklift Certified 5 times", "stat": "m.forklift_certified.won", "goal": 5, "reward": "hat_hardhat_chrome"},
	{"id": "c_sf_surv", "text": "Survive 10 Stable Footing rounds", "stat": "m.stable_footing.survived", "goal": 10, "reward": "title_surefooted"},
	{"id": "c_sf_win", "text": "Win Stable Footing 3 times", "stat": "m.stable_footing.won", "goal": 3, "reward": "suit_denim"},
	{"id": "c_qd_surv", "text": "Survive 10 Quick Draw rounds", "stat": "m.quick_draw.survived", "goal": 10, "reward": "title_fasthand"},
	{"id": "c_qd_win", "text": "Win Quick Draw 5 times", "stat": "m.quick_draw.won", "goal": 5, "reward": "hat_fedora_gold"},
	{"id": "c_lr_kills", "text": "Shove 10 rivals into the saws in Lethal Rebound", "stat": "m.lethal_rebound.kills", "goal": 10, "reward": "hat_cone_blood"},
	{"id": "c_lr_win", "text": "Win Lethal Rebound 3 times", "stat": "m.lethal_rebound.won", "goal": 3, "reward": "pattern_rust"},
	{"id": "c_ww_top", "text": "Reach the top landing 10 times in Wrong Way", "stat": "m.wrong_way.topped", "goal": 10, "reward": "hat_propeller"},
	{"id": "c_ww_die", "text": "Get shredded 10 times in Wrong Way", "stat": "m.wrong_way.died", "goal": 10, "reward": "title_mince"},
	{"id": "c_spb_surv", "text": "Survive 10 Spine Breaker rounds", "stat": "m.spine_breaker.survived", "goal": 10, "reward": "pattern_inmate"},
	{"id": "c_spb_win", "text": "Win Spine Breaker 3 times", "stat": "m.spine_breaker.won", "goal": 3, "reward": "hair_toxic"},
	{"id": "c_sa_surv", "text": "Survive 10 Seat Assignment rounds", "stat": "m.seat_assignment.survived", "goal": 10, "reward": "suit_flamingo"},
	{"id": "c_sa_win", "text": "Win Seat Assignment 5 times", "stat": "m.seat_assignment.won", "goal": 5, "reward": "title_chairhog"},
	{"id": "c_rr_surv", "text": "Survive 10 Roomba Rampage rounds", "stat": "m.roomba_rampage.survived", "goal": 10, "reward": "title_dustbunny"},
	{"id": "c_rr_win", "text": "Win Roomba Rampage 3 times", "stat": "m.roomba_rampage.won", "goal": 3, "reward": "suit_coolant"},
	{"id": "c_sfz_surv", "text": "Survive 10 Short Fuse rounds", "stat": "m.short_fuse.survived", "goal": 10, "reward": "title_defused"},
	{"id": "c_sfz_win", "text": "Win Short Fuse 3 times", "stat": "m.short_fuse.won", "goal": 3, "reward": "hair_pink"},
	{"id": "c_lw_surv", "text": "Survive 10 Live Wire rounds", "stat": "m.live_wire.survived", "goal": 10, "reward": "death_sparks"},
	{"id": "c_lw_win", "text": "Win Live Wire 5 times", "stat": "m.live_wire.won", "goal": 5, "reward": "pattern_bio"},
	{"id": "c_gc_surv", "text": "Survive 10 Gas Chamber rounds", "stat": "m.gas_chamber.survived", "goal": 10, "reward": "suit_bruise"},
	{"id": "c_gc_win", "text": "Win Gas Chamber 5 times", "stat": "m.gas_chamber.won", "goal": 5, "reward": "hair_blue"},
]

## Mode slug -> {stat suffix: [var name in the minigame, how]} read at round end.
## how: "count" = int(dict[me]), "has" = 1 if array has me.
const MODE_READS: Dictionary = {
	"firearm_factory": {"kills": ["kills", "count"]},
	"lethal_rebound": {"kills": ["kills", "count"]},
	"forklift_certified": {"deliveries": ["deliveries", "count"]},
	"smoke_break": {"smoked": ["smoked", "count"]},
	"the_filter": {"sorted": ["score", "count"]},
	"table_manners": {"cleared": ["finish_order", "has"]},
	"tunnel_hazard": {"escaped": ["finish_order", "has"]},
	"wrong_way": {"topped": ["finish_order", "has"]},
}
const DEATH_ARRAYS: Array[String] = ["dead_order", "elim_order", "dead"]

var save_path: String = SAVE_PATH
var persist: bool = true
var stats: Dictionary = {}
var unlocked_ids: Array[String] = []
var loadout: Dictionary = DEFAULT_LOADOUT.duplicate()
var session_unlocks: Array[String] = []

var _items: Dictionary = {}
var _reward_of: Dictionary = {}
var _round_active: bool = false
var _round_died: bool = false
var _round_slug: String = ""

func _ready() -> void:
	for it in ITEMS:
		_items[it.id] = it
	for c in CHALLENGES:
		_reward_of[c.reward] = c
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tools/"):
			persist = false
	load_profile()


func item(id: String) -> Dictionary:
	return _items.get(id, {})

func items_in(cat: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in ITEMS:
		if it.cat == cat:
			out.append(it)
	return out

func rarity_color(r: int) -> Color:
	return RARITY_COLORS[clampi(r, 0, RARITY_COLORS.size() - 1)]

func rarity_name(r: int) -> String:
	return RARITY_NAMES[clampi(r, 0, RARITY_NAMES.size() - 1)]

func challenge_for(item_id: String) -> Dictionary:
	return _reward_of.get(item_id, {})

func is_unlocked(id: String) -> bool:
	return bool(item(id).get("free", false)) or unlocked_ids.has(id)

func progress(c: Dictionary) -> int:
	return mini(stat(c.stat), int(c.goal))

func is_done(c: Dictionary) -> bool:
	return stat(c.stat) >= int(c.goal)

func requirement_text(item_id: String) -> String:
	var c := challenge_for(item_id)
	if c.is_empty():
		return ""
	return "%s · %d/%d" % [c.text, progress(c), c.goal]

func stat(key: String) -> int:
	match key:
		"modes_played":
			return _distinct_modes("played")
		"modes_won":
			return _distinct_modes("won")
	return int(stats.get(key, 0))

func _distinct_modes(suffix: String) -> int:
	var n := 0
	for m in Globals.MODES:
		if int(stats.get("m.%s.%s" % [m.slug, suffix], 0)) > 0:
			n += 1
	return n


func equip(id: String) -> bool:
	var it := item(id)
	if it.is_empty() or not is_unlocked(id):
		return false
	loadout[it.cat] = id
	save_profile()
	loadout_changed.emit()
	return true

func equipped(cat: String) -> String:
	var id: String = str(loadout.get(cat, DEFAULT_LOADOUT[cat]))
	if item(id).is_empty() or item(id).cat != cat or not is_unlocked(id):
		return DEFAULT_LOADOUT[cat]
	return id

func look(lo: Dictionary = {}) -> Dictionary:
	var src := lo if not lo.is_empty() else loadout
	var pick := func(cat: String) -> Dictionary:
		var id: String = str(src.get(cat, DEFAULT_LOADOUT[cat]))
		var it := item(id)
		if it.is_empty() or it.cat != cat:
			it = item(DEFAULT_LOADOUT[cat])
		return it
	var hat_it: Dictionary = pick.call("hat")
	var title_it: Dictionary = pick.call("title")
	return {
		"sex": pick.call("body").v,
		"suit": pick.call("suit").v,
		"pattern": pick.call("pattern").v,
		"hair": pick.call("hair").v,
		"hat": hat_it.v,
		"hat_tint": hat_it.get("tint", ""),
		"title": title_it.v,
		"title_rarity": title_it.r,
		"death_fx": pick.call("death_fx").v,
	}

func local_look() -> Dictionary:
	var lo := {}
	for cat in CATEGORIES:
		lo[cat] = equipped(cat)
	return look(lo)

static func sanitize_look(d: Dictionary) -> Dictionary:
	var out := {}
	if d.get("sex") in ["male", "female"]:
		out.sex = d.sex
	if d.get("suit") is Color:
		var c: Color = d.suit
		out.suit = Color(c.r, c.g, c.b, 1.0)
	if d.get("pattern") is int:
		out.pattern = clampi(d.pattern, 0, 9)
	if d.get("hair") is Color:
		out.hair = d.hair
	if d.get("hat") is String and (d.hat == "" or Globals.HATS.has(d.hat)):
		out.hat = d.hat
	if d.get("hat_tint") is String and d.hat_tint in ["", "gold", "chrome", "blood", "neon", "rust"]:
		out.hat_tint = d.hat_tint
	if d.get("title") is String:
		out.title = (d.title as String).left(28)
	if d.get("title_rarity") is int:
		out.title_rarity = clampi(d.title_rarity, 0, 3)
	if d.get("death_fx") is String and d.death_fx in ["blood", "gore", "sparks", "ash", "boom", "confetti", "gold"]:
		out.death_fx = d.death_fx
	return out


func session_begin() -> void:
	session_unlocks.clear()

func round_begin(slug: String) -> void:
	_round_active = true
	_round_died = false
	_round_slug = slug

func note_death(peer_id: int) -> void:
	if _round_active and multiplayer.multiplayer_peer != null and peer_id == multiplayer.get_unique_id():
		_round_died = true

func bump(key: String, n: int = 1) -> void:
	if not _local_is_human():
		return
	stats[key] = int(stats.get(key, 0)) + n

func _local_is_human() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	var me := multiplayer.get_unique_id()
	return NetworkManager.players.has(me) and not NetworkManager.players[me].get("is_bot", false)

func round_end(slug: String, mg: Node, placement: Array) -> Array[String]:
	_round_active = false
	if not _local_is_human():
		return []
	var me := multiplayer.get_unique_id()
	if not placement.has(me):
		return []
	return apply_round(slug, observe(slug, mg, me, placement))

func observe(slug: String, mg: Node, me: int, placement: Array) -> Dictionary:
	var f := {"place": placement.find(me) + 1, "count": placement.size(), "died": _round_died, "extra": {}}
	if mg and is_instance_valid(mg):
		for k in DEATH_ARRAYS:
			var a: Variant = mg.get(k)
			if a is Array and (a as Array).has(me):
				f.died = true
		var ps: Variant = mg.get("players")
		if ps is Dictionary and (ps as Dictionary).has(me):
			var p: Variant = ps[me]
			if p is LabPlayer3D and is_instance_valid(p) and not (p as LabPlayer3D).alive:
				f.died = true
		var reads: Dictionary = MODE_READS.get(slug, {})
		for suffix in reads:
			var spec: Array = reads[suffix]
			var v: Variant = mg.get(spec[0])
			if spec[1] == "count" and v is Dictionary:
				var n: Variant = (v as Dictionary).get(me, 0)
				if n is int or n is float:
					f.extra[suffix] = maxi(int(n), 0)
			elif spec[1] == "has" and v is Array:
				f.extra[suffix] = 1 if (v as Array).has(me) else 0
		match slug:
			"duck_hunt":
				var h: Variant = mg.get("hunter")
				f.role = "sniper" if h is int and h == me else "runner"
			"inside_job":
				var inf: Variant = mg.get("infected")
				var zero: Variant = mg.get("zero_id")
				f.role = "zero" if zero is int and zero == me else ("infected" if inf is Array and (inf as Array).has(me) else "clean")
	return f

func apply_round(slug: String, f: Dictionary) -> Array[String]:
	var before := _done_ids()
	var place: int = f.get("place", 0)
	var count: int = f.get("count", 1)
	var died: bool = f.get("died", false)
	var won := place == 1
	var role: String = f.get("role", "")
	var pre := "m.%s." % slug
	_add("rounds_played")
	_add(pre + "played")
	if won:
		_add("rounds_won")
		_add(pre + "won")
		_add("win_streak")
		stats.win_streak_best = maxi(int(stats.get("win_streak_best", 0)), int(stats.win_streak))
		if not died:
			_add("flawless_wins")
	else:
		stats.win_streak = 0
	if place >= 1 and place <= 3 and count > 1:
		_add("rounds_top3")
		_add(pre + "top3")
	if count > 1 and place == count:
		_add("last_places")
	if died:
		_add("deaths")
		_add(pre + "died")
	else:
		_add("rounds_survived")
		_add(pre + "survived")
	var extra: Dictionary = f.get("extra", {})
	for k in extra:
		if int(extra[k]) > 0:
			_add(pre + str(k), int(extra[k]))
	match role:
		"runner":
			if not died:
				_add(pre + "runner_survived")
		"sniper":
			if won:
				_add(pre + "sniper_won")
		"clean":
			_add(pre + "clean_survived")
		"zero":
			if place >= 1 and place <= 3:
				_add(pre + "zero_top3")
	return _commit(before)

func match_end(winner_id: int) -> Array[String]:
	if not _local_is_human():
		return []
	var me := multiplayer.get_unique_id()
	var ranks: Array = NetworkManager.players.keys()
	ranks.sort_custom(func(a, b): return int(NetworkManager.players[a].score) > int(NetworkManager.players[b].score))
	return apply_match(winner_id == me, ranks.find(me) + 1)

func apply_match(won: bool, rank: int) -> Array[String]:
	var before := _done_ids()
	_add("matches_played")
	if won:
		_add("matches_won")
	if rank >= 1 and rank <= 3:
		_add("match_podiums")
	return _commit(before)

func _add(key: String, n: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n

func _done_ids() -> Array[String]:
	var out: Array[String] = []
	for c in CHALLENGES:
		if is_done(c):
			out.append(c.id)
	return out

func _commit(_before: Array[String]) -> Array[String]:
	var fresh: Array[String] = []
	for c in CHALLENGES:
		if is_done(c) and not unlocked_ids.has(c.reward):
			unlocked_ids.append(c.reward)
			fresh.append(c.reward)
	session_unlocks.append_array(fresh)
	save_profile()
	if not fresh.is_empty():
		unlocked.emit(fresh)
	return fresh


func reset() -> void:
	stats = {}
	unlocked_ids.clear()
	loadout = DEFAULT_LOADOUT.duplicate()
	session_unlocks.clear()

func load_profile() -> void:
	reset()
	if not persist or not FileAccess.file_exists(save_path):
		return
	var cf := ConfigFile.new()
	if cf.load(save_path) != OK:
		push_warning("profile unreadable, starting fresh: " + save_path)
		return
	var st: Variant = cf.get_value("profile", "stats", {})
	if st is Dictionary:
		for k in st:
			if (st[k] is int or st[k] is float) and str(k).length() < 64:
				stats[str(k)] = int(st[k])
	var ul: Variant = cf.get_value("profile", "unlocked", [])
	if ul is Array:
		for id in ul:
			if id is String and _items.has(id) and not unlocked_ids.has(id):
				unlocked_ids.append(id)
	var lo: Variant = cf.get_value("profile", "loadout", {})
	if lo is Dictionary:
		for cat in CATEGORIES:
			var id: Variant = lo.get(cat, "")
			if id is String and _items.has(id) and item(id).cat == cat:
				loadout[cat] = id
	for c in CHALLENGES:
		if is_done(c) and not unlocked_ids.has(c.reward):
			unlocked_ids.append(c.reward)

func save_profile() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	cf.set_value("profile", "version", SAVE_VERSION)
	cf.set_value("profile", "stats", stats)
	cf.set_value("profile", "unlocked", unlocked_ids)
	cf.set_value("profile", "loadout", loadout)
	var tmp := save_path + ".tmp"
	if cf.save(tmp) != OK:
		push_warning("profile save failed: " + save_path)
		return
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_path))

func use_save_path(path: String) -> void:
	save_path = path
	persist = true
	load_profile()
