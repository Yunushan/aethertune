.PHONY: bootstrap bootstrap-client bootstrap-mobile get client-get server-get analyze client-analyze server-analyze test client-test server-test format desktop-linux desktop-windows desktop-macos server-build server-run

bootstrap: bootstrap-client

bootstrap-client:
	./scripts/bootstrap_client.sh

bootstrap-mobile: bootstrap-client

get: client-get server-get

client-get:
	cd apps/mobile && flutter pub get

server-get:
	cd services/server && dart pub get

analyze: client-analyze server-analyze

client-analyze:
	cd apps/mobile && flutter analyze

server-analyze:
	cd services/server && dart analyze

test: client-test server-test

client-test:
	cd apps/mobile && flutter test

server-test:
	cd services/server && dart test

server-build:
	cd services/server && mkdir -p build && dart compile exe bin/server.dart -o build/aethertune-server

format:
	dart format apps/mobile/lib apps/mobile/test services/server/bin services/server/lib services/server/test

desktop-linux:
	flutter config --enable-linux-desktop
	./scripts/bootstrap_client.sh
	cd apps/mobile && flutter build linux --debug

desktop-windows:
	flutter config --enable-windows-desktop
	./scripts/bootstrap_client.sh
	cd apps/mobile && flutter build windows --debug

desktop-macos:
	flutter config --enable-macos-desktop
	./scripts/bootstrap_client.sh
	cd apps/mobile && flutter build macos --debug

server-run:
	cd services/server && dart run bin/server.dart
