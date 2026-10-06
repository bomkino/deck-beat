#!/bin/bash
# Turns on automatic update signing for pitch.dog's Mac apps, once, from the
# Mac that holds the update key:
#
#   cd ~/deck-beat && git pull && bash scripts/auto-signing-setup.sh
#
# For each app repository it makes a `release` environment that only main may
# use, and puts the key in it as the SPARKLE_PRIVATE_KEY secret. From then on
# each repository's release workflow signs its own releases, and nobody signs
# by hand. The key goes from its file straight to gh, which encrypts it for
# GitHub; it is never printed. Running this again is harmless. To undo it, see
# docs/UPDATES.md.
set -euo pipefail
KEY="${SPARKLE_KEY:-$HOME/Library/Application Support/pitch.dog/Release Keys/sparkle-ed25519-private.key}"
REPOS=(bomkino/deck-beat bomkino/ooo bomkino/pitchdog-drift bomkino/galileo-gallery bomkino/backdrop)

[ -f "$KEY" ] || { echo "No update key at $KEY"; exit 1; }
command -v gh >/dev/null || { echo "Needs the GitHub CLI: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh isn't signed in: run gh auth login"; exit 1; }

for repo in "${REPOS[@]}"; do
  echo "== $repo"
  # The environment, open only to workflows running on main.
  echo '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' \
    | gh api -X PUT "repos/$repo/environments/release" --input - >/dev/null
  if ! gh api "repos/$repo/environments/release/deployment-branch-policies" --jq '.branch_policies[].name' | grep -qx main; then
    gh api -X POST "repos/$repo/environments/release/deployment-branch-policies" -f name=main -f type=branch >/dev/null
  fi
  gh secret set SPARKLE_PRIVATE_KEY --env release -R "$repo" < "$KEY"
done
echo
echo "Done. Deck Beat, OOO, Drift, Galileo and Backdrop now sign their own releases."
