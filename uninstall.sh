#!/usr/bin/env bash
# Persian Voice Dictation for macOS — uninstaller

set -euo pipefail

say() { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
ok()  { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!\033[0m %s\n" "$*"; }

LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/com.persian-dictation.whisper-server.plist"
HAMMERSPOON_CFG="$HOME/.hammerspoon/init.lua"
MODEL_DIR="$HOME/.whisper-models"

say "Stopping whisper-server LaunchAgent…"
if launchctl list 2>/dev/null | grep -q com.persian-dictation.whisper-server; then
    launchctl bootout "gui/$(id -u)/com.persian-dictation.whisper-server" 2>/dev/null || true
    ok "LaunchAgent stopped."
else
    warn "LaunchAgent not running."
fi

if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
    rm "$LAUNCH_AGENT_PLIST"
    ok "Removed LaunchAgent plist."
fi

say "Removing Hammerspoon config…"
if [[ -f "$HAMMERSPOON_CFG" ]]; then
    backup="$HAMMERSPOON_CFG.uninstall-$(date +%Y%m%d-%H%M%S)"
    mv "$HAMMERSPOON_CFG" "$backup"
    ok "Hammerspoon init.lua moved to: $backup"
fi

cat <<EOF

$(tput bold)Uninstalled.$(tput sgr0)

The following were NOT removed (preserve if you use them for other things):
  - Hammerspoon app (brew uninstall --cask hammerspoon)
  - whisper-cpp, sox, nowplaying-cli (brew uninstall …)
  - Whisper model at $MODEL_DIR  (~1.5 GB)

Remove them manually if desired.

EOF
