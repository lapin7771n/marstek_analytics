SIM ?= iPhone 18 Pro

.PHONY: project test

project:
	xcodegen generate

test: project
	xcodebuild test -project BatteryETA.xcodeproj -scheme BatteryETA -destination 'platform=iOS Simulator,name=$(SIM)' -quiet
