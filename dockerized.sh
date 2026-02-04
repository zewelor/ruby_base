#!/bin/bash

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
# - Non-interactive (either is not TTY): disable TTY with `-T`
docker_compose_run_on_exec () {
  local container_name="$1"
  shift
  local -a tty_args=()
  if ! [ -t 0 ] || ! [ -t 1 ]; then
    tty_args=(-T)
  fi

  if docker compose ps --services --status running | grep -qx "$container_name"
  then
    docker compose --progress quiet exec "${tty_args[@]}" "$container_name" "$@"
  else
    docker compose --progress quiet run --rm "${tty_args[@]}" --service-ports "$container_name" "$@"
  fi
}

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
echo "Dockerized aliasses set"
