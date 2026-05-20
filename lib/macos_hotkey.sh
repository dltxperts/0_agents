#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREENSHOT_SCRIPT="$SCRIPT_DIR/screenshot-upload.sh"

if ! [ -x "$SCREENSHOT_SCRIPT" ]; then
    echo "screenshot-upload.sh not found or not executable at: $SCREENSHOT_SCRIPT" >&2
    exit 1
fi

# 1. Установка Hammerspoon если ещё нет
if ! [ -d "/Applications/Hammerspoon.app" ]; then
    brew install --cask hammerspoon
fi

# 2. Создание конфига
mkdir -p ~/.hammerspoon
cat > ~/.hammerspoon/init.lua <<EOF
hs.hotkey.bind({"cmd", "shift"}, "3", function()
  hs.task.new(
    "$SCREENSHOT_SCRIPT",
    function(exitCode, stdOut, stdErr)
      if exitCode ~= 0 then
        hs.notify.new({
          title="Screenshot failed",
          informativeText=(stdErr ~= "" and stdErr or "exit "..exitCode)
        }):send()
      end
    end
  ):start()
end)

hs.alert.show("Hammerspoon loaded")
EOF

# 3. Запустить Hammerspoon (если не запущен) и перезагрузить конфиг
open -a Hammerspoon
sleep 1
osascript -e 'tell application "Hammerspoon" to reload config' 2>/dev/null || true

echo "Готово. Не забудь выдать Hammerspoon права на Screen Recording и Accessibility."

