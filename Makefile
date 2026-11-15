APP_NAME := A2141Monitor
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR := $(APP_BUNDLE)/Contents/MacOS

CC := clang
CXX := clang++
ARCH := -arch x86_64 -mmacosx-version-min=12.0 -mavx2 -mfma
CFLAGS := $(ARCH) -O3 -Wall -Wextra -Wno-deprecated-declarations -Iinclude
OBJCXXFLAGS := $(ARCH) -O3 -fobjc-arc -Wall -Wextra -Wno-deprecated-declarations -Iinclude
LDFLAGS := $(ARCH) -framework Cocoa -framework IOKit -framework QuartzCore -framework CoreFoundation -lpthread

.PHONY: all i9 clean run

all: $(MACOS_DIR)/$(APP_NAME)

i9:
	@$(MAKE) BUILD_DIR=build-i9 \
		CFLAGS="$(CFLAGS) -DA2141_MODEL_I9=1" \
		OBJCXXFLAGS="$(OBJCXXFLAGS) -DA2141_MODEL_I9=1" all

$(MACOS_DIR)/$(APP_NAME): src/A2141MonitorApp.mm src/smc_bridge.c include/smc_bridge.h resources/Info.plist resources/AppIcon.icns
	@mkdir -p $(MACOS_DIR) $(APP_BUNDLE)/Contents/Resources
	$(CC) $(CFLAGS) -c src/smc_bridge.c -o $(BUILD_DIR)/smc_bridge.o
	$(CXX) $(OBJCXXFLAGS) -c src/A2141MonitorApp.mm -o $(BUILD_DIR)/A2141MonitorApp.o
	$(CXX) $(BUILD_DIR)/smc_bridge.o $(BUILD_DIR)/A2141MonitorApp.o $(LDFLAGS) -o $(MACOS_DIR)/$(APP_NAME)
	@cp resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@cp resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@codesign --force --deep --sign - $(APP_BUNDLE) 2>/dev/null || true
	@echo "[+] Aplicacion nativa compilada con icono en: $(APP_BUNDLE)"

run: all
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR) build-i9 electron-app/out
