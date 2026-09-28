#!/usr/bin/env bash
# Link this plugin's helper scripts into ~/.local/bin so the bar widget can find
# them. Safe to re-run.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$HOME/.local/bin"

# Only the entry points get symlinked. phone-vnc-start finds poscalc.py by
# resolving its own path with `readlink -f`, which lands back here in the repo,
# so poscalc.py does not need to be linked into ~/.local/bin itself.
mkdir -p "$target"
for s in phone-vnc-start.sh phone-vnc-stop.sh; do
  ln -sf "$here/$s" "$target/${s%.sh}"
  echo "linked $target/${s%.sh} -> $here/$s"
done

echo
echo "Done. Restart the shell for the bar widget to pick up changes:"
echo "  omarchy restart shell"
