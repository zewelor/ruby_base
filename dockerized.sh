#!/bin/bash

# Prepare this checkout's wrapper path without invoking project commands.
_dockerized_prepend_project_bin() {
  local project_bin="$1"
  local active_bin="${_dockerized_active_bin-}"
  local path_is_set="${PATH+x}"
  local remaining_path="${PATH-}"
  local entry more new_path="" has_entries=0

  if [ "$path_is_set" = x ]; then
    while :; do
      case "$remaining_path" in
        *:*)
          entry="${remaining_path%%:*}"
          remaining_path="${remaining_path#*:}"
          more=true
          ;;
        *)
          entry="$remaining_path"
          more=false
          ;;
      esac

      if [ "$entry" != "$project_bin" ] && { [ -z "$active_bin" ] || [ "$entry" != "$active_bin" ]; }; then
        if [ "$has_entries" -eq 1 ]; then
          new_path="$new_path:$entry"
        else
          new_path="$entry"
          has_entries=1
        fi
      fi
      [ "$more" = true ] || break
    done
  fi

  if [ "$has_entries" -eq 1 ]; then
    PATH="$project_bin:$new_path"
  else
    PATH="$project_bin"
  fi
  export PATH
  _dockerized_active_bin="$project_bin"
}

_dockerized_clear_sourced_functions() {
  local command_name
  for command_name in "${_dockerized_path_functions[@]-}" ruby gem bundle rails rake standardrb rubocop rspec lefthook spring brakeman; do
    if typeset -f "$command_name" >/dev/null 2>&1; then
      unset -f "$command_name"
    fi
  done
}

# Resolve Zsh's source path before the Bash-only runner code below.
if [ -n "${ZSH_VERSION-}" ]; then
  _dockerized_project_root="${${(%):-%x}:A:h}"
  _dockerized_prepend_project_bin "$_dockerized_project_root/.dev/bin"
  _dockerized_clear_sourced_functions
  unset _dockerized_path_functions
  unset -f _dockerized_prepend_project_bin _dockerized_clear_sourced_functions
  unset _dockerized_project_root
  export LEFTHOOK_BIN="lefthook"
  return 0
fi

dockerized_require_rootless() {
  local docker_security_options
  if ! docker_security_options="$(docker info --format '{{json .SecurityOptions}}')"; then
    echo "Could not verify rootless Docker; refusing to start local containers." >&2
    return 1
  fi
  if [[ "$docker_security_options" != *'"name=rootless"'* ]]; then
    echo "Local containers require rootless Docker; refusing to start." >&2
    return 1
  fi
}

if ! _dockerized_project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"; then
  echo "Could not determine the dockerized project root." >&2
  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    exit 1
  else
    return 1
  fi
fi

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  _dockerized_prepend_project_bin "$_dockerized_project_root/.dev/bin"
  _dockerized_clear_sourced_functions
  unset _dockerized_path_functions
  unset -f _dockerized_prepend_project_bin _dockerized_clear_sourced_functions
  unset _dockerized_project_root
  export LEFTHOOK_BIN="lefthook"
  return 0
fi

# Keep CLI and editor clients in the same worktree context.
dockerized_context() {
  cd -- "$_dockerized_project_root" || return
  export PWD
  local digest slug
  digest="$(printf '%s' "$PWD" | sha256sum)" || return
  slug="${PWD##*/}"
  slug="${slug,,}"
  slug="${slug//[^a-z0-9_-]/-}"
  export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dev-${slug:0:32}-${digest:0:12}}"
  export DOCKER_BUNDLE_DIR="$PWD/.bundle/gems"
  export DOCKER_CACHE_DIR="$PWD/.dev/cache"
}

dockerized_compose() (
  dockerized_context || exit
  dockerized_require_rootless || exit
  docker compose --progress quiet "$@"
)

dockerized_setup() (
  dockerized_context || exit
  dockerized_require_rootless || exit
  mkdir -p -- "$DOCKER_BUNDLE_DIR" "$DOCKER_CACHE_DIR" || {
    echo "Could not prepare project cache directories for setup." >&2
    exit 1
  }
  docker compose --progress quiet build app || exit
  exec docker compose --progress quiet run --rm --no-deps -T --entrypoint '' app bundle install
)

# A prepared bundle is required: opening an editor must never build or install.
dockerized_lsp() (
  dockerized_context || exit
  dockerized_require_rootless || exit
  if [[ ! -f Gemfile.lock || ! -d "$DOCKER_BUNDLE_DIR" ]]; then
    echo "Ruby LSP [$PWD]: run ./dockerized.sh setup to prepare the bundle." >&2
    exit 1
  fi
  local image
  image="$(docker compose --progress quiet config --no-env-resolution --images editor)" || exit
  if [[ -z "$image" || "$image" == *$'\n'* ]]; then
    echo "Ruby LSP [$PWD]: expected one editor image in Compose configuration." >&2
    exit 1
  fi
  if ! docker image inspect "$image" >/dev/null; then
    echo "Ruby LSP [$PWD]: editor image is missing; run ./dockerized.sh setup." >&2
    exit 1
  fi
  exec docker compose --progress quiet run --rm --no-deps -T --pull never editor
)

# Why we detect TTY on both stdin and stdout:
#
# - If you pipe stdout (e.g. `rubocop | tee out.txt`), stdout is no longer a TTY.
# - If you redirect stdin (e.g. `echo x | ruby`), stdin is no longer a TTY.
#
# In both cases, forcing pseudo-TTY allocation (`-t`) can fail or behave oddly.
# For `docker compose`, the equivalent is using `-T/--no-TTY` when not interactive.
#
# Practical rule:
# - Interactive (stdin+stdout are TTY): allow TTY (default)
# - Non-interactive (either is not a TTY): disable TTY with `-T`
docker_compose_run_on_exec () (
  dockerized_context || exit
  dockerized_require_rootless || exit
  local container_name="$1"
  shift
  local -a tty_args=()
  if ! [ -t 0 ] || ! [ -t 1 ]; then
    tty_args=(-T)
  fi

  local running_services
  running_services="$(docker compose ps --services --status running)" || exit $?
  if printf '%s\n' "$running_services" | grep -qx "$container_name"; then
    docker compose --progress quiet exec "${tty_args[@]}" "$container_name" "$@"
  else
    docker compose --progress quiet run --rm "${tty_args[@]}" --service-ports "$container_name" "$@"
  fi
)

_define_docker_alias() {
  local name="$1"
  local body=""

  case "$name" in
    ruby|gem|bundle)
      body="docker_compose_run_on_exec app $name \"\$@\""
      ;;
    *)
      body="docker_compose_run_on_exec app bundle exec $name \"\$@\""
      ;;
  esac

  unset -f "$name" 2> /dev/null || true
  eval "
  function $name() {
    $body
  }
  "
}

names=("ruby" "gem" "bundle" "rails" "rake" "standardrb" "rubocop" "rspec" "lefthook" "spring" "brakeman")
for name in "${names[@]}"; do
  _define_docker_alias "$name"
done

export LEFTHOOK_BIN="lefthook" # Set the lefthook bin path, our custom wrappe

# Support guarded Compose commands and the sourced aliases as a CLI wrapper.
if [[ "${BASH_SOURCE[0]}" == "$0" ]] && [[ $# -gt 0 ]]; then
  case "$1" in
    compose)
      shift
      dockerized_compose "$@"
      ;;
    setup)
      dockerized_setup
      ;;
    lsp)
      dockerized_lsp
      ;;
    *)
      "$@"
      ;;
  esac
fi
