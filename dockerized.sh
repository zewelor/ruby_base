#!/usr/bin/env bash
# Explicit Docker command runner; the caller's shell and PATH stay unchanged.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo 'Run ./dockerized.sh COMMAND [ARG...]; do not source this script.' >&2
  return 2
fi
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
caller_dir="$(pwd -P)"
case "$caller_dir/" in
  "$project_root/"*) ;;
  *) echo "Working directory [$caller_dir] is outside this checkout [$project_root]." >&2; exit 1 ;;
esac
if [[ $# == 0 ]]; then
  echo "Usage: $0 COMMAND [ARG...] | setup | lsp | compose [ARG...]" >&2
  exit 2
fi

digest="$(printf '%s' "$project_root" | sha256sum)"
slug="${project_root##*/}"
slug="${slug,,}"
slug="${slug//[^a-z0-9_-]/-}"
export COMPOSE_PROJECT_NAME="dev-${slug:0:32}-${digest:0:12}"
export DOCKER_PROJECT_DIR="$project_root"
DOCKER_GIT_COMMON_DIR="$(git -C "$project_root" rev-parse --path-format=absolute --git-common-dir)"
export DOCKER_GIT_COMMON_DIR
export DOCKER_BUNDLE_DIR="$project_root/.bundle/gems"
export DOCKER_CACHE_DIR="$project_root/.dev/cache"

# Container root maps to the unprivileged daemon user only with rootless Docker.
if ! security_options="$(docker info --format '{{json .SecurityOptions}}')"; then
  echo 'Could not verify rootless Docker; refusing to start local containers.' >&2
  exit 1
fi
if [[ "$security_options" != *'"name=rootless"'* ]]; then
  echo 'Local containers require rootless Docker; refusing to start.' >&2
  exit 1
fi

# Execute the registered plugin directly so it receives signals and preserves exit status.
compose_binary="$(docker info --format '{{range .ClientInfo.Plugins}}{{if eq .Name "compose"}}{{.Path}}{{end}}{{end}}')"
if [[ -z "$compose_binary" || ! -x "$compose_binary" ]]; then
  echo 'Docker Compose plugin is unavailable; install it before running ./dockerized.sh setup.' >&2
  exit 1
fi
compose=("$compose_binary" --project-directory "$project_root" --file "$project_root/compose.yaml" --progress quiet)

require_image() {
  local image
  image="$("${compose[@]}" config --no-env-resolution --images "$1")"
  if ! docker image inspect "$image" >/dev/null; then
    echo "Image [$image] is missing; run ./dockerized.sh setup in [$project_root]." >&2
    exit 1
  fi
}

case "$1" in
  setup)
    mkdir -p "$DOCKER_BUNDLE_DIR" "$DOCKER_CACHE_DIR"
    "${compose[@]}" build app
    # This starter deliberately ignores Gemfile.lock; setup may create/update it.
    "${compose[@]}" run --pull never --rm --no-deps -T --env BUNDLE_FROZEN=false app bundle install
    exec "${compose[@]}" run --pull never --rm --no-deps -T app bundle exec lefthook install
    ;;
  lsp)
    # Opening an editor must never build, pull, or install dependencies.
    if [[ ! -f "$project_root/Gemfile.lock" || ! -d "$DOCKER_BUNDLE_DIR" ]]; then
      echo "Ruby LSP [$project_root]: run ./dockerized.sh setup to prepare the bundle." >&2
      exit 1
    fi
    require_image editor
    exec "${compose[@]}" run --pull never --rm --no-deps -T editor
    ;;
  compose)
    shift
    exec "${compose[@]}" "$@"
    ;;
  *)
    require_image app
    # Disable the TTY when either end is piped or redirected, preserving literal I/O.
    tty_args=()
    if [[ ! -t 0 || ! -t 1 ]]; then tty_args=(-T); fi
    exec "${compose[@]}" run --pull never --rm --no-deps "${tty_args[@]}" --workdir "$caller_dir" app "$@"
    ;;
esac
