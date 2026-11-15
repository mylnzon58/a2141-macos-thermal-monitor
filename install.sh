#!/bin/zsh
set -e

echo "=================================================================="
echo " Instalador de A2141 Monitor (macOS Native Telemetry & Graphs)"
echo " Autor: mylnzon58 (Juan Monzon)"
echo "=================================================================="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "${1:-}" == "--compile" ]]; then
    echo "[+] 1. Compilando A2141Monitor.app desde código fuente..."
    make -C "$SCRIPT_DIR" clean
    make -C "$SCRIPT_DIR" all
    APP_SRC="$SCRIPT_DIR/build/A2141Monitor.app"
elif [[ -d "$SCRIPT_DIR/prebuilt/A2141Monitor.app" ]]; then
    echo "[+] 1. Usando versión precompilada lista para abrir (prebuilt/A2141Monitor.app)..."
    APP_SRC="$SCRIPT_DIR/prebuilt/A2141Monitor.app"
elif [[ -d "$SCRIPT_DIR/build/A2141Monitor.app" ]]; then
    echo "[+] 1. Usando versión compilada en build/A2141Monitor.app..."
    APP_SRC="$SCRIPT_DIR/build/A2141Monitor.app"
else
    echo "[+] 1. Compilando A2141Monitor.app..."
    make -C "$SCRIPT_DIR" clean
    make -C "$SCRIPT_DIR" all
    APP_SRC="$SCRIPT_DIR/build/A2141Monitor.app"
fi

echo "[+] 2. Instalando en /Applications/A2141Monitor.app..."
killall A2141Monitor 2>/dev/null || true
rm -rf /Applications/A2141Monitor.app 2>/dev/null || sudo rm -rf /Applications/A2141Monitor.app
cp -R "$APP_SRC" /Applications/A2141Monitor.app 2>/dev/null || sudo cp -R "$APP_SRC" /Applications/A2141Monitor.app
xattr -cr /Applications/A2141Monitor.app 2>/dev/null || sudo xattr -cr /Applications/A2141Monitor.app 2>/dev/null || true

echo "[+] 3. Abriendo A2141 Monitor..."
open /Applications/A2141Monitor.app

echo ""
echo "[OK] A2141 Monitor instalado en /Applications/A2141Monitor.app y en tu barra superior."
