#!/bin/bash
# Installs the `harkio` command. Double-click this file, or run ./install.command
# Re-run it any time (e.g. after moving this folder or on another Mac).
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"

echo "== Installing harkio from $DIR =="
chmod +x "$DIR/harkio" "$DIR/narrate.py" "$DIR/narrate.sh" 2>/dev/null || true
mkdir -p "$BIN"
ln -sf "$DIR/harkio" "$BIN/harkio"
echo "Linked $BIN/harkio"

# Shared pronunciation list used by every script (unless a script has its own next to it).
CONF="$HOME/.config/harkio"
mkdir -p "$CONF"
if [ ! -f "$CONF/pronunciations.txt" ] && [ -f "$DIR/pronunciations.txt" ]; then
  cp "$DIR/pronunciations.txt" "$CONF/pronunciations.txt"
  echo "Created $CONF/pronunciations.txt"
fi

# Make sure ~/.local/bin is on PATH for new Terminal windows (zsh is the macOS default).
if ! grep -qs 'HOME/.local/bin' "$HOME/.zshrc"; then
  printf '\n# harkio\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
  echo "Added ~/.local/bin to your PATH in ~/.zshrc"
fi

echo
"$DIR/harkio" setup || echo "(Helper tools didn't build - narration still works; speed changes will be weaker.)"
echo
echo "== Done. Open a NEW Terminal window and try:  harkio --help =="
read -p "Press Return to close."
