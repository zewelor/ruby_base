# Readme

## Publication

CI validates and publishes the `live` image for every push to `main`.
The image is tagged with the published commit SHA.

## Local Docker

Local development requires rootless Docker. Compose uses container UID/GID
`0:0`, which maps to the unprivileged host user. The runner resolves the project
root from its own location, gives each checkout a stable Compose project name,
and mounts the checkout once at its absolute host path as the working directory.
CI and production keep `/app`.

Use `./dockerized.sh setup` to build the `app` development image and run
`bundle install`. It prepares the ignored bundle at `.bundle/gems` and cache
directory at `.dev/cache` as the invoking user, and may write the ignored local
`Gemfile.lock`. App containers use `.dev/cache` for XDG caches and
`.dev/cache/rubocop` for RuboCop. Run setup after changing the Gemfile. Use
`./dockerized.sh lsp` for the editor Ruby LSP; it requires the prepared lock,
bundle and image and does not build, pull, or install dependencies on startup.
Sourcing the runner only configures the project `PATH`; it does not create
caches or install tools.

Run setup in each checkout or cloud environment instead of copying binary bundle
caches between machines. Existing `~/.cache/docker-bundle` data is left untouched
and is no longer used by this project. Before deleting a checkout, stop its
services with `./dockerized.sh compose down`. Deleting the checkout removes its
`.bundle` and `.dev/cache`; Docker images and build layers remain separate Docker
state and are not pruned automatically.

Sourcing `dockerized.sh` in Bash or Zsh silently prepends this checkout's
`.dev/bin` to `PATH` and removes the previously active project bin.
Static symlinks expose `ruby-lsp` and the supported CLI commands to child
processes. `ruby-lsp` uses the existing prepared LSP route; wrappers do not
install host tools.

The runner checks the actual daemon before every invocation. Source `dockerized.sh`
to use project wrappers, or run `./dockerized.sh compose ...`. Direct `docker compose`
calls bypass this check and the shared project context. CI keeps its separate
Compose file and image user.

The read-only root filesystem, dropped capabilities and no-new-privileges remain
in effect. `/tmp` is writable and is the container home. The checkout bind makes
the bundle available at the same absolute host and container path. Run
`just runner-checks` to test the startup guard with a fake daemon.

## Ruby version

The Dockerfile base-image tags are the source of truth for the Ruby version.
The `slim` and `trixie-distroless` images use the same version, and Renovate
updates those Docker tags directly. Project commands still run through
`dockerized.sh` as described in `AGENTS.md`.

The starter ignores `Gemfile.lock` in Git. Explicit local setup creates or
updates it for frozen editor startup; Docker build stages create a separate
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
