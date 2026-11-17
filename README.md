# Readme

## Publication

CI validates and publishes the `live` image for every push to `main`.
The image is tagged with the published commit SHA.

## Local Docker

Install Git, Bash 4+, `sha256sum`, rootless Docker and its Compose plugin, plus
`just` for recipes. The local daemon must be able to bind-mount the checkout at its
absolute host path.
Local containers run as UID/GID `0:0`, which maps to the unprivileged daemon user.
The runner checks the daemon on every invocation and refuses rootful or unavailable
Docker. Host Ruby and Bundler are not required.

```bash
just setup
./dockerized.sh bundle exec standardrb
just runner-checks
./bin/lefthook run pre-commit
```

Setup builds the development image, installs gems into `.bundle/gems`, prepares
`.dev/cache`, creates or updates the ignored local `Gemfile.lock`, and installs
Lefthook's Git hooks. Installed hooks call `bin/lefthook` to enter Docker before
running Ruby tools. Re-run setup after changing the Gemfile.
Ordinary commands require the prepared image and local lockfile; they never build
or pull images. Bundler automatically installs missing gems into `.bundle/gems`,
including after deleting the bundle cache. Installation failures stop the command
with a visible error. The lockfile stays frozen, so changing dependencies or
resolving them for the first time remains explicit:

```bash
./dockerized.sh env BUNDLE_FROZEN=false bundle install
./dockerized.sh env BUNDLE_FROZEN=false bundle update <gem>
```

The development image owns the auto-install setting. Compose inherits it for app
commands; the offline editor service explicitly disables it. Production images
disable auto-install and use only gems installed during the image build.
Run `just bundle-checks` to verify installation, cache reuse, visible failures and
the editor's prepared-bundle requirement with an isolated local gem fixture.

Use explicit commands; the runner does not activate a shell environment or add
wrappers to `PATH`. Arguments are passed literally and commands preserve the
caller's directory inside the checkout. For example, from `lib`, run
`../dockerized.sh ruby -e 'puts Dir.pwd'`. Invocations from outside the checkout
fail. Compose configuration, project identity, bundle and caches remain anchored
to the checkout; each checkout has its own resources. Git metadata is shared for
linked worktrees, while their gems and caches stay isolated. Use `just` recipes
from any subdirectory to run at the root. Use `./dockerized.sh compose ...` for explicit
Compose administration, including deliberate builds and pulls. The runner executes
the registered Compose plugin directly to preserve signals and command exit status.
CI and production retain their separate `/app` layout and image user.

For Ruby LSP, manually configure the editor to launch
`/absolute/path/to/checkout/dockerized.sh lsp` with a working directory inside that
checkout. It uses the prepared image, bundle and lockfile, with no network or app
services, and never builds, pulls or installs gems. No host `ruby-lsp` wrapper is
provided. The absolute checkout mount makes gem paths match the editor's paths.

Run setup separately in each checkout or cloud environment. Before deleting a
checkout, stop its services with `./dockerized.sh compose down`. Deleting it removes
its bundle and tool caches; Docker images and build layers require separate explicit
cleanup. Existing shared caches are left untouched. The read-only root filesystem,
dropped capabilities, no-new-privileges and writable `/tmp` remain in effect.
Run `just runner-checks` for isolated fake-Docker runner checks.

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
