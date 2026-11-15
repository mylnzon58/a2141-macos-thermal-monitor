#!/bin/zsh
echo "[+] Cerrando y desinstalando A2141 Monitor..."
killall A2141Monitor 2>/dev/null || true
rm -rf /Applications/A2141Monitor.app 2>/dev/null || sudo rm -rf /Applications/A2141Monitor.app
echo "[OK] A2141 Monitor fue eliminado de /Applications."
