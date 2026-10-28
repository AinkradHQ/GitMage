DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
# The sideload directory is `<cacheRoot>/DevPlugins`, and cacheRoot is
# `~/Library/Application Support/<bundle-id>/Cache` (AinkradHome.defaultCacheRoot).
# Deliberately NOT under the user's Ainkrad Home: dev plugin bundles are
# rebuildable machine state, not vault data.
DEV_PLUGINS ?= $(HOME)/Library/Application Support/com.ainkrad.app/Cache/DevPlugins

.PHONY: generate build test sideload release
generate: ; xcodegen generate
build: lint generate ; xcodebuild -scheme GitMagePlugin -configuration Debug -derivedDataPath build -destination 'platform=macOS' build
test: lint generate ; xcodebuild -scheme GitMagePlugin -configuration Debug -derivedDataPath build -destination 'platform=macOS' test
sideload: build
	@case "$(DEV_PLUGINS)" in "$(HOME)/Library/Application Support/"*) \
		[ "$(CONFIRM_DAILY)" = 1 ] || { echo "refusing: DEV_PLUGINS is the daily app's folder (set DEV_PLUGINS=<fixture>/DevPlugins or CONFIRM_DAILY=1)"; exit 1; };; esac
	mkdir -p "$(DEV_PLUGINS)"
	rm -rf "$(DEV_PLUGINS)/GitMagePlugin.bundle"
	cp -R build/Build/Products/Debug/GitMagePlugin.bundle "$(DEV_PLUGINS)/GitMagePlugin.bundle"
release: ; ./scripts/release.sh $(V)

include scripts/guardrails.mk
