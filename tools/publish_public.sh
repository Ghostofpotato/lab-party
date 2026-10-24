#!/usr/bin/env bash
# Mirror the committed tree (HEAD) into the public GitHub repo as one new commit,
# leaving out private dev notes. Usage: tools/publish_public.sh "<message>"
set -euo pipefail
MSG="${1:-Update}"
REPO=Ghostofpotato/lab-party
PUB="${LP_PUBLIC_DIR:-$HOME/lab-party-public}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
PRIVATE=(docs BUILD_PLAN.md minigames/duck_hunt_classic/RULES.md)

if [ ! -d "$PUB/.git" ]; then
  if gh repo view "$REPO" >/dev/null 2>&1; then
    git clone -q "https://github.com/$REPO.git" "$PUB"
  else
    mkdir -p "$PUB" && git -C "$PUB" init -q -b main
  fi
fi
ID=$(gh api user --jq .id)
git -C "$PUB" config user.name "Grim Intern"
git -C "$PUB" config user.email "$ID+Ghostofpotato@users.noreply.github.com"

find "$PUB" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git -C "$SRC" archive HEAD | tar -x -C "$PUB"
for p in "${PRIVATE[@]}"; do rm -rf "${PUB:?}/$p"; done
if grep -rIiE "reverse-engineer|decompil|machine.party|klubnika|ghostcloud|dronetjek|192\.168\." "$PUB" --exclude-dir=.git --exclude=publish_public.sh -l; then
  echo "private reference found in the files above, not publishing"; exit 1
fi

git -C "$PUB" add -A
git -C "$PUB" diff --cached --quiet && { echo "nothing to publish"; exit 0; }
git -C "$PUB" commit -q -m "$MSG"
if ! gh repo view "$REPO" >/dev/null 2>&1; then
  gh repo create "$REPO" --public --source "$PUB" --push \
    --description "A grim little party game: 21 lethal minigames, LAN multiplayer, bots. Godot 4.5."
else
  git -C "$PUB" push -q origin HEAD:main
fi
echo "published: https://github.com/$REPO"
