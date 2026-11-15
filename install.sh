#!/bin/zsh
set -e

echo "=================================================================="
echo " Instalador de A2141 Monitor (macOS Native Telemetry & Graphs)"
echo " Autor: mylnzon58 (Juan Monzon)"
echo "=================================================================="

echo "[+] 1. Compilando A2141Monitor.app..."
make clean
make all

echo "[+] 2. Instalando en /Applications/A2141Monitor.app..."
rm -rf /Applications/A2141Monitor.app 2>/dev/null || sudo rm -rf /Applications/A2141Monitor.app
cp -R build/A2141Monitor.app /Applications/A2141Monitor.app 2>/dev/null || sudo cp -R build/A2141Monitor.app /Applications/A2141Monitor.app

echo "[+] 3. Abriendo A2141 Monitor..."
open /Applications/A2141Monitor.app

echo ""
echo "[OK] A2141 Monitor instalado en /Applications/A2141Monitor.app y en tu barra superior."
