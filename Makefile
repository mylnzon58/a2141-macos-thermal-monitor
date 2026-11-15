APP_NAME := A2141Monitor
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR := $(APP_BUNDLE)/Contents/MacOS

CC := clang
CXX := clang++
ARCH := -arch x86_64
CFLAGS := $(ARCH) -O3 -march=native -Wall -Wextra -Wno-deprecated-declarations -Iinclude
OBJCXXFLAGS := $(ARCH) -O3 -march=native -fobjc-arc -Wall -Wextra -Wno-deprecated-declarations -Iinclude
LDFLAGS := $(ARCH) -framework Cocoa -framework IOKit -framework QuartzCore -framework CoreFoundation -lpthread

.PHONY: all clean run

all: $(MACOS_DIR)/$(APP_NAME)

$(MACOS_DIR)/$(APP_NAME): src/A2141MonitorApp.mm src/smc_bridge.c include/smc_bridge.h
	@mkdir -p $(MACOS_DIR)
	$(CC) $(CFLAGS) -c src/smc_bridge.c -o $(BUILD_DIR)/smc_bridge.o
	$(CXX) $(OBJCXXFLAGS) -c src/A2141MonitorApp.mm -o $(BUILD_DIR)/A2141MonitorApp.o
	$(CXX) $(BUILD_DIR)/smc_bridge.o $(BUILD_DIR)/A2141MonitorApp.o $(LDFLAGS) -o $(MACOS_DIR)/$(APP_NAME)
	@cp resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@echo "[+] Aplicacion nativa compilada en: $(APP_BUNDLE)"

run: all
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR) electron-app/out
