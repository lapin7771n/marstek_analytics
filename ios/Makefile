SIM ?= iPhone 18 Pro
BUILD ?= 1
ARCHIVE := build/BatteryETA.xcarchive

.PHONY: project test icon archive upload

project:
	xcodegen generate

test: project
	xcodebuild test -project BatteryETA.xcodeproj -scheme BatteryETA -destination 'platform=iOS Simulator,name=$(SIM)' -quiet

icon:
	rsvg-convert -w 1024 -h 1024 App/icon.svg | magick - -alpha off App/Assets.xcassets/AppIcon.appiconset/icon-1024.png

archive: project
	xcodebuild archive -project BatteryETA.xcodeproj -scheme BatteryETA -configuration Release -destination 'generic/platform=iOS' -archivePath $(ARCHIVE) -allowProvisioningUpdates CURRENT_PROJECT_VERSION=$(BUILD)

upload: archive
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
