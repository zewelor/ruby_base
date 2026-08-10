# Readme

## Ruby version

The Dockerfile base-image tags are the source of truth for the Ruby version.
The `slim` and `trixie-distroless` images use the same version, and Renovate
updates those Docker tags directly. Project commands still run through
`dockerized.sh` as described in `AGENTS.md`.

The starter does not commit `Gemfile.lock`. Docker build stages create a
transient lockfile for the runtime image.

## Image targets

Local development uses `dev`; CI validates `ci` and builds the default `live`
production image. The Dockerfile also provides `distroless` as an explicit
optional target:

```bash
docker build --target distroless .
```

Choose one production target for a derived project instead of building both.

## Build cache

CI zapisuje cache builda w GHA z `scope=ci`, a produkcyjny build (`live`) używa
`scope=live` z fallbackiem do `scope=ci`. Dzięki temu wspólne warstwy (np. base)
mogą być współdzielone między jobami.
