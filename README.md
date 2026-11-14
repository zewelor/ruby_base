# Readme

## Publication

CI validates and publishes the `live` image for every push to `main`.
The image is tagged with the published commit SHA.

## Local Docker

Local development requires rootless Docker. Compose uses container UID/GID
`0:0`, which maps to the unprivileged host user. Run local commands from the
project root: `compose.yaml` mounts the checkout once at its absolute host path
and uses that path as the working directory. CI and production keep `/app`.

The runner checks the actual daemon before every invocation; use the sourced
aliases or `./dockerized.sh compose ...`. Direct `docker compose` calls bypass
this check. CI keeps its separate Compose file and image user.

The read-only root filesystem, dropped capabilities and no-new-privileges remain
in effect. `/tmp` is writable and is the local home/cache directory. The fresh
`bundler_rootless` volume skips copying image UID 1000 ownership, allowing writes
without additional capabilities. Existing cache volumes are preserved. Run
`just runner-checks` to test the startup guard with a fake daemon.

## Ruby version

The Dockerfile base-image tags are the source of truth for the Ruby version.
The `slim` and `trixie-distroless` images use the same version, and Renovate
updates those Docker tags directly. Project commands still run through
`dockerized.sh` as described in `AGENTS.md`.

The starter does not commit `Gemfile.lock`. Docker build stages create a
transient lockfile for the runtime image.

All runtime stages use the Bundler provided by their Ruby image. A derived
project may commit the generated `BUNDLED WITH` metadata, but must not require
that writer version to be installed in the runtime image.

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
