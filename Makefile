.PHONY: bootstrap get analyze test format

bootstrap:
	./scripts/bootstrap_mobile.sh

get:
	cd apps/mobile && flutter pub get

analyze:
	cd apps/mobile && flutter analyze

test:
	cd apps/mobile && flutter test

format:
	dart format apps/mobile/lib apps/mobile/test
