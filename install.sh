#!/usr/bin/env bash
# Persian Voice Dictation for macOS — installer
# Run: ./install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$HOME/.whisper-models"
MODEL_FILE="ggml-large-v3-turbo.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_FILE"
HAMMERSPOON_DIR="$HOME/.hammerspoon"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="$LAUNCH_AGENT_DIR/com.persian-dictation.whisper-server.plist"

say() { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
ok()  { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m✗\033[0m %s\n" "$*" >&2; }

# ---------- Pre-flight ----------
if [[ "$(uname)" != "Darwin" ]]; then
    err "macOS only."
    exit 1
fi

if ! command -v brew &>/dev/null; then
    err "Homebrew is required. Install from https://brew.sh first."
    exit 1
fi

# ---------- Dependencies ----------
say "Installing dependencies via Homebrew…"
brew install whisper-cpp sox nowplaying-cli
brew install --cask hammerspoon

# ---------- Model ----------
say "Setting up Whisper model…"
mkdir -p "$MODEL_DIR"
if [[ -f "$MODEL_DIR/$MODEL_FILE" ]]; then
    ok "Model already present: $MODEL_DIR/$MODEL_FILE"
else
    say "Downloading $MODEL_FILE (~1.5 GB)…"
    curl -L --progress-bar -o "$MODEL_DIR/$MODEL_FILE" "$MODEL_URL"
    ok "Model downloaded."
fi

# ---------- Hammerspoon config ----------
say "Installing Hammerspoon configuration…"
mkdir -p "$HAMMERSPOON_DIR"
if [[ -f "$HAMMERSPOON_DIR/init.lua" ]]; then
    backup="$HAMMERSPOON_DIR/init.lua.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$HAMMERSPOON_DIR/init.lua" "$backup"
    warn "Existing init.lua backed up to: $backup"
fi
cp "$REPO_DIR/hammerspoon/init.lua" "$HAMMERSPOON_DIR/init.lua"
ok "Hammerspoon config installed."

# ---------- LaunchAgent ----------
say "Setting up whisper-server LaunchAgent (auto-start at login)…"
mkdir -p "$LAUNCH_AGENT_DIR"

# Unload existing agent if present (clean re-install)
if launchctl list 2>/dev/null | grep -q com.persian-dictation.whisper-server; then
    launchctl bootout "gui/$(id -u)/com.persian-dictation.whisper-server" 2>/dev/null || true
fi

sed -e "s|{{MODEL_PATH}}|$MODEL_DIR/$MODEL_FILE|g" \
    "$REPO_DIR/launchd/com.persian-dictation.whisper-server.plist.template" \
    > "$LAUNCH_AGENT_PLIST"

launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PLIST"
ok "LaunchAgent installed and started."

# ---------- Done ----------
cat <<EOF

$(tput bold)Installation complete.$(tput sgr0)

Next steps:
  1. Launch Hammerspoon (will be in /Applications).
  2. Grant Accessibility permission in System Settings.
  3. Grant Microphone permission on first dictation.
  4. Tap Right Command to start/stop dictation.

Notes:
  - whisper-server runs in background as a LaunchAgent (~1.6 GB RAM).
  - Edit $HAMMERSPOON_DIR/init.lua to customize hotkey, language, or vocabulary.
  - To uninstall: see README "Uninstall" section.

EOF
