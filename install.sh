#!/bin/zsh
set -e

echo "=================================================================="
echo " Instalador de A2141 Monitor (macOS Native Telemetry & Graphs)"
echo " Autor: mylnzon58 (Juan Monzon)"
echo "=================================================================="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHYS_CPUS="$(sysctl -n hw.physicalcpu 2>/dev/null || echo 6)"
MODEL_TAG="i7 (6C/12T)"
PREBUILT_SUBDIR="prebuilt"
MAKE_TARGET="all"
BUILD_SUBDIR="build"
if [[ "$PHYS_CPUS" -eq 8 ]]; then
    MODEL_TAG="i9 (8C/16T)"
    PREBUILT_SUBDIR="prebuilt-i9"
    MAKE_TARGET="i9"
    BUILD_SUBDIR="build-i9"
fi

echo "[+] Detectado procesador MacBookPro16,1 A2141 [$MODEL_TAG]"
if [[ "${1:-}" == "--compile" ]]; then
    echo "[+] 1. Compilando A2141Monitor.app desde código fuente ($MAKE_TARGET)..."
    make -C "$SCRIPT_DIR" clean
    make -C "$SCRIPT_DIR" "$MAKE_TARGET"
    APP_SRC="$SCRIPT_DIR/$BUILD_SUBDIR/A2141Monitor.app"
elif [[ -d "$SCRIPT_DIR/$PREBUILT_SUBDIR/A2141Monitor.app" ]]; then
    echo "[+] 1. Usando versión precompilada lista para abrir ($PREBUILT_SUBDIR/A2141Monitor.app)..."
    APP_SRC="$SCRIPT_DIR/$PREBUILT_SUBDIR/A2141Monitor.app"
elif [[ -d "$SCRIPT_DIR/$BUILD_SUBDIR/A2141Monitor.app" ]]; then
    echo "[+] 1. Usando versión compilada en $BUILD_SUBDIR/A2141Monitor.app..."
    APP_SRC="$SCRIPT_DIR/$BUILD_SUBDIR/A2141Monitor.app"
else
    echo "[+] 1. Compilando A2141Monitor.app ($MAKE_TARGET)..."
    make -C "$SCRIPT_DIR" clean
    make -C "$SCRIPT_DIR" "$MAKE_TARGET"
    APP_SRC="$SCRIPT_DIR/$BUILD_SUBDIR/A2141Monitor.app"
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
