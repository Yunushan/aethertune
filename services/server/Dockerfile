FROM dart:3.12.2@sha256:5ac89dbcae4327278b257920e2786df0f22c87adc630017266b67cfcceef8348 AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --enforce-lockfile

COPY bin ./bin
COPY lib ./lib
RUN mkdir -p /out \
    && dart compile exe bin/server.dart -o /out/aethertune-server

FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241

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
