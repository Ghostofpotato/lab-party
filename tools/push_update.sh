#!/usr/bin/env bash
# Publish a Lab Party release over the air: a GitHub release with both exported
# builds plus latest.json, which the in-game Updater reads.
# Usage: tools/push_update.sh <build> <version> "<notes>"
# Expects build/linux/LabParty.x86_64 and build/windows/LabParty.exe (exported and,
# for Windows, signed with tools/sign_windows.sh) with Updater.BUILD == <build>.
set -euo pipefail
BUILD="$1"; VERSION="$2"; NOTES="$3"
REPO=Ghostofpotato/lab-party
OUT="${LP_BUILD_DIR:-$HOME/lab-party-build}"
TAG="v$VERSION"
STAGE="$OUT/release-$TAG"
cd "$(dirname "$0")/.."

grep -q "const BUILD: int = $BUILD\$" autoloads/updater.gd || { echo "Updater.BUILD is not $BUILD"; exit 1; }

mkdir -p "$STAGE"
ln -f "$OUT/linux/LabParty.x86_64" "$STAGE/LabParty-Linux.x86_64"
ln -f "$OUT/windows/LabParty.exe" "$STAGE/LabParty-Windows.exe"
python3 - "$BUILD" "$VERSION" "$NOTES" "$REPO" "$TAG" "$STAGE" > "$STAGE/latest.json" <<'PY'
import hashlib, json, os, sys
b, v, n, repo, tag, stage = sys.argv[1:]
def entry(name):
    p = os.path.join(stage, name)
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return {"url": f"https://github.com/{repo}/releases/download/{tag}/{name}",
            "sha256": h.hexdigest(), "size": os.path.getsize(p)}
print(json.dumps({"build": int(b), "version": v, "notes": n,
    "linux": entry("LabParty-Linux.x86_64"), "windows": entry("LabParty-Windows.exe")}))
PY
gh release create "$TAG" --repo "$REPO" --title "Lab Party $VERSION" --notes "$NOTES" \
  "$STAGE/LabParty-Windows.exe" "$STAGE/LabParty-Linux.x86_64" "$STAGE/latest.json"
curl -sL "https://github.com/$REPO/releases/latest/download/latest.json"; echo
rm -f "$STAGE"/*; rmdir "$STAGE"
echo "published build $BUILD ($VERSION)"
