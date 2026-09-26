#!/bin/bash
# Quits the app (external monitors return to normal brightness) and removes it with its settings.
osascript -e 'quit app "Monitor Brightness"' >/dev/null 2>&1 || true
rm -rf "$HOME/Applications/Monitor Brightness.app"
rm -rf "$HOME/Library/Application Support/MonitorBrightness"
echo "Uninstalled."
