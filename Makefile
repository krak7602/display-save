.PHONY: build run test assets dmg release

build:
	bash scripts/build-app.sh

run: build
	open "dist/Display Save.app"

test:
	swift test

assets:
	swift scripts/generate-assets.swift

dmg: build
	bash scripts/create-dmg.sh

release:
	UNIVERSAL=1 bash scripts/build-app.sh
	ARCH_LABEL=universal bash scripts/create-dmg.sh
	cd dist && shasum -a 256 "Display-Save-$$(cat ../VERSION)-universal.dmg" > SHA256SUMS.txt
