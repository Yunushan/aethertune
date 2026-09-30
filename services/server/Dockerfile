FROM dart:3.13.3@sha256:7e57e61d97813dc57dd0801656ff4d5c5efafa47bae563a681571543ad30f199 AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --enforce-lockfile

COPY bin ./bin
COPY lib ./lib
RUN mkdir -p /out \
    && dart compile exe bin/server.dart -o /out/aethertune-server \
    && dart compile exe bin/healthcheck.dart -o /out/aethertune-healthcheck \
    && mkdir -m 0700 /out/data

# Dart AOT uses glibc and bundled BoringSSL; retain CA certificates without system OpenSSL.
FROM gcr.io/distroless/base-nossl-debian13:nonroot@sha256:8c563c1fb5e120606f0d85733049775faed6192e2bd2223ef283a5393eec22b9

COPY --from=build /out/aethertune-server /usr/local/bin/aethertune-server
COPY --from=build /out/aethertune-healthcheck /usr/local/bin/aethertune-healthcheck
COPY --from=build --chown=10001:999 /out/data /data

# Preserve the previous image's numeric identity for existing data volumes.
USER 10001:999
ENV PORT=8080
ENV AETHERTUNE_DATA_DIR=/data

VOLUME ["/data"]
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/usr/local/bin/aethertune-healthcheck"]

CMD ["/usr/local/bin/aethertune-server"]
