FROM dart:3.12.2@sha256:13140e26d84f4fda57cea31942222112aeb2eec10e5e6874c1c0f70beed189ab AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --enforce-lockfile

COPY bin ./bin
COPY lib ./lib
RUN mkdir -p /out \
    && dart compile exe bin/server.dart -o /out/aethertune-server

FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818

RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --create-home aethertune \
    && mkdir /data \
    && chown aethertune:aethertune /data

COPY --from=build /out/aethertune-server /usr/local/bin/aethertune-server

USER aethertune
ENV PORT=8080
ENV AETHERTUNE_DATA_DIR=/data

VOLUME ["/data"]
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["curl", "--fail", "--silent", "http://127.0.0.1:8080/ready"]

CMD ["aethertune-server"]
