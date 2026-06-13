APP_NAME   := SubEarn
BUNDLE_ID  := dev.tonyhuang.subearn
CONFIG     := release
BUILD_DIR  := .build/$(CONFIG)
APP_BUNDLE := $(APP_NAME).app
CONTENTS   := $(APP_BUNDLE)/Contents
MACOS_DIR  := $(CONTENTS)/MacOS
RES_DIR    := $(CONTENTS)/Resources

.PHONY: all build app sign run clean

all: sign

build:
	swift build -c $(CONFIG)

app: build
	@mkdir -p $(MACOS_DIR) $(RES_DIR)
	@cp $(BUILD_DIR)/$(APP_NAME) $(MACOS_DIR)/$(APP_NAME)
	@cp App/Info.plist $(CONTENTS)/Info.plist
	@printf 'APPL????' > $(CONTENTS)/PkgInfo
	@echo "Assembled $(APP_BUNDLE)"

sign: app
	@codesign --force --sign - --identifier $(BUNDLE_ID) $(APP_BUNDLE)
	@echo "Ad-hoc signed $(APP_BUNDLE)"

run: all
	@open $(APP_BUNDLE)

clean:
	@rm -rf .build $(APP_BUNDLE)
