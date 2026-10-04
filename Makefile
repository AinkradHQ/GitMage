DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
# The sideload directory is `<cacheRoot>/DevPlugins`, and cacheRoot is
# `~/Library/Application Support/<bundle-id>/Cache` (AinkradHome.defaultCacheRoot).
# Deliberately NOT under the user's Ainkrad Home: dev plugin bundles are
# rebuildable machine state, not vault data.
DEV_PLUGINS := $(HOME)/Library/Application Support/com.ainkrad.app/Cache/DevPlugins

.PHONY: generate build test sideload release
generate: ; xcodegen generate
build: lint generate ; xcodebuild -scheme GitMagePlugin -configuration Debug -derivedDataPath build -destination 'platform=macOS' build
test: lint generate ; xcodebuild -scheme GitMagePlugin -configuration Debug -derivedDataPath build -destination 'platform=macOS' test
sideload: build
	mkdir -p "$(DEV_PLUGINS)"
	rm -rf "$(DEV_PLUGINS)/GitMagePlugin.bundle"
	cp -R build/Build/Products/Debug/GitMagePlugin.bundle "$(DEV_PLUGINS)/GitMagePlugin.bundle"
release: ; ./scripts/release.sh $(V)

include scripts/guardrails.mk
