#!/bin/bash
# Installs the `harkio` command. Double-click this file, or run ./install.command
# Re-run it any time: after updating this folder (git pull), after moving it, or on another Mac.
#
# harkio is copied to ~/.local/share/harkio and run from there, not from this folder.
# Folders like Documents, Desktop and Downloads are protected by macOS, and AI agents
# and other apps often can't read them, so running harkio from here would fail for them.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/harkio"
BIN="$HOME/.local/bin"
FILES="harkio narrate.py narrate.sh rate_test.py tempo.swift harkio-record.swift pronunciations.txt LICENSE"

echo "== Installing harkio from $SRC =="
mkdir -p "$DEST" "$BIN"
for f in $FILES; do
  [ -f "$SRC/$f" ] && cp -f "$SRC/$f" "$DEST/$f"
done
chmod -R u+rwX,go+rX "$DEST"
chmod +x "$DEST/harkio" "$DEST/narrate.py" "$DEST/narrate.sh" "$DEST/rate_test.py"
# Files downloaded from the internet are flagged by macOS; clear that on the installed copy.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
ln -sf "$DEST/harkio" "$BIN/harkio"
echo "Installed to $DEST"
echo "Linked $BIN/harkio"

# Shared pronunciation list used by every script (unless a script has its own next to it).
CONF="$HOME/.config/harkio"
mkdir -p "$CONF"
if [ ! -f "$CONF/pronunciations.txt" ] && [ -f "$SRC/pronunciations.txt" ]; then
  cp "$SRC/pronunciations.txt" "$CONF/pronunciations.txt"
  echo "Created $CONF/pronunciations.txt"
fi

# Put ~/.local/bin on PATH for every shell, including the non-interactive shells that
# AI agents and other tools start (they don't read ~/.zshrc).
LINE='export PATH="$HOME/.local/bin:$PATH"'
add_path() {
  if ! grep -qs 'HOME/.local/bin' "$1"; then
    printf '\n# harkio\n%s\n' "$LINE" >> "$1"
    echo "Added ~/.local/bin to your PATH in $1"
  fi
}
add_path "$HOME/.zshrc"
add_path "$HOME/.zshenv"
if [ -f "$HOME/.bash_profile" ]; then add_path "$HOME/.bash_profile"; else add_path "$HOME/.profile"; fi

echo
"$DEST/harkio" setup || echo "(Helper tools didn't build - narration still works; speed changes will be weaker.)"
echo
echo "== Done. Open a NEW Terminal window and try:  harkio --help =="
read -p "Press Return to close." || true
