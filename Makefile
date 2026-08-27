SCHEME  := ReelsWorkout
PROJECT := ReelsWorkout.xcodeproj
DEVICE  := iPhone 17 Pro

.PHONY: bootstrap generate build test unit clean lint

## Copy the secrets template (if absent) and generate the Xcode project.
bootstrap:
	@test -f Config/Secrets.xcconfig || cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
	@$(MAKE) generate
	@echo "Fill in Config/Secrets.xcconfig, then: make build"

## Regenerate ReelsWorkout.xcodeproj from project.yml. Run after adding files.
generate:
	xcodegen generate

build:
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEVICE)' \
		-derivedDataPath build \
		CODE_SIGNING_ALLOWED=NO | xcbeautify || true

## Build, install, and launch the app in the simulator (like npm run dev).
run: build
	@xcrun simctl boot "$(DEVICE)" 2>/dev/null || true
	@open -a Simulator
	@xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/ReelsWorkout.app
	@xcrun simctl launch --terminate-running-process booted com.dongik.repreel

## Fast feedback loop — ReelsKit only, no simulator required.
unit:
	cd ReelsKit && swift test

## Full test run through the app scheme.
test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(DEVICE)' \
		CODE_SIGNING_ALLOWED=NO

clean:
	rm -rf build DerivedData ReelsKit/.build
