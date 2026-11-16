#!/usr/bin/env bash
# Exercise setup, LSP, and project context with a fake Docker CLI.
set -eu
unset COMPOSE_PROJECT_NAME DOCKER_BUNDLE_DIR DOCKER_CACHE_DIR BUNDLE_GEMFILE HOME XDG_CACHE_HOME
runner="${1:-./dockerized.sh}"
runner="$(cd "$(dirname "$runner")" && pwd)/$(basename "$runner")"
source_runner="$runner"
source_runner_root="$(dirname "$source_runner")"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
project="$fixture/Ruby Project"
outside="$fixture/outside"
mkdir -p "$project" "$outside" "$fixture/bin"
cp "$runner" "$project/dockerized.sh"
if [[ -d "$source_runner_root/.dev" ]]; then
  mkdir -p "$project/.dev"
  cp -a "$source_runner_root/.dev/run" "$project/.dev/run"
  if [[ -d "$source_runner_root/.dev/bin" ]]; then
    cp -a "$source_runner_root/.dev/bin" "$project/.dev/bin"
  fi
fi
chmod +x "$project/dockerized.sh"
runner="$project/dockerized.sh"
export DOCKER_TEST_DIR="$fixture" DOCKER_TEST_MODE=rootless DOCKER_TEST_RUNNING=false
export DOCKER_TEST_IMAGE_EXISTS=true DOCKER_TEST_IMAGE_MODE=one
export PATH="$fixture/bin:$PATH" DOCKER_TEST_UID="$(id -u)"
cat > "$fixture/bin/docker" <<'SH'
#!/usr/bin/env bash
set -eu
if [[ "$1" == info ]]; then
  case "$DOCKER_TEST_MODE" in
    rootless) printf '%s\n' '["name=seccomp,profile=builtin","name=rootless"]' ;;
    rootful) printf '%s\n' '["name=seccomp,profile=builtin"]' ;;
    unavailable) exit 42 ;;
  esac
  exit 0
fi
n=0
[[ ! -f "$DOCKER_TEST_DIR/call-count" ]] || read -r n < "$DOCKER_TEST_DIR/call-count"
n=$((n + 1))
printf '%s\n' "$n" > "$DOCKER_TEST_DIR/call-count"
printf '%s\0' "$@" > "$DOCKER_TEST_DIR/call-$n.argv"
{
  printf 'PWD=%s\n' "$PWD"
  printf 'COMPOSE_PROJECT_NAME=%s\n' "${COMPOSE_PROJECT_NAME-}"
  printf 'COMPOSE_FILE=%s\n' "${COMPOSE_FILE-}"
  printf 'DOCKER_BUNDLE_DIR=%s\n' "${DOCKER_BUNDLE_DIR-}"
  printf 'DOCKER_CACHE_DIR=%s\n' "${DOCKER_CACHE_DIR-}"
  printf 'BUNDLE_GEMFILE=%s\n' "${BUNDLE_GEMFILE-}"
} > "$DOCKER_TEST_DIR/call-$n.env"
if [[ "${DOCKER_TEST_REQUIRE_SETUP_DIRS-false}" == true && "$1" == compose && "$2" == --progress && "$4" == build ]]; then
  for path in "${DOCKER_BUNDLE_DIR-}" "${DOCKER_CACHE_DIR-}"; do
    [[ -n "$path" && -d "$path" && "$(stat -c %u "$path")" == "$DOCKER_TEST_UID" ]] || {
      echo "setup must prepare $path as the invoking user before Compose writes" >&2
      exit 90
    }
  done
fi
if [[ "$1" == image && "$2" == inspect ]]; then
  [[ "$DOCKER_TEST_IMAGE_EXISTS" == true ]]
  exit
fi
[[ "$1" == compose ]] || exit 99
subcommand=""
for arg in "$@"; do
  case "$arg" in
    config|ps|build|run|exec) subcommand="$arg"; break ;;
  esac
done
case "$subcommand" in
  config)
    if [[ "$DOCKER_TEST_IMAGE_MODE" == two ]]; then
      printf '%s\n' "${COMPOSE_PROJECT_NAME:-}-app" "second-image"
    elif [[ " $* " == *" --images "* ]]; then
      printf '%s\n' "${COMPOSE_PROJECT_NAME:-}-app"
    fi
    ;;
  ps)
    [[ "$DOCKER_TEST_RUNNING" != true ]] || printf '%s\n' app
    ;;
  build) ;;
  run|exec)
    if [[ " $* " == *" editor "* ]]; then
      printf '%s\n' 'ruby-lsp-protocol'
    fi
    ;;
  *) exit 98 ;;
esac
SH
chmod +x "$fixture/bin/docker"
failures=0
check() {
  if ! "$@"; then
    printf 'FAIL: %s\n' "$*" >&2
    failures=$((failures + 1))
  fi
}
reset_calls() {
  rm -f "$fixture"/call-[0-9]*.argv "$fixture"/call-[0-9]*.env "$fixture/call-count"
  : > "$fixture/stderr"
  : > "$fixture/stdout"
}
assert_call_args() {
  local number="$1"
  shift
  printf '%s\0' "$@" > "$fixture/expected.argv"
  cmp "$fixture/expected.argv" "$fixture/call-$number.argv"
}
assert_env_value() {
  local number="$1" key="$2" value="$3"
  grep -Fqx "$key=$value" "$fixture/call-$number.env"
}
assert_call_has_arg() {
  local number="$1" expected="$2" arg
  local -a args=()
  mapfile -d '' -t args < "$fixture/call-$number.argv"
  for arg in "${args[@]}"; do [[ "$arg" != "$expected" ]] || return 0; done
  return 1
}
expected_name="dev-ruby-project-$(printf '%s' "$project" | sha256sum | cut -c1-12)"
expected_bundle="$project/.bundle/gems"
expected_cache_dir="$project/.dev/cache"

# CLI and sourced editor aliases resolve the script root, regardless of caller cwd.
reset_calls
check env -u HOME -u XDG_CACHE_HOME "$runner" compose config --images app >/dev/null
check assert_call_args 1 compose --progress quiet config --images app
check assert_env_value 1 PWD "$project"
check assert_env_value 1 COMPOSE_PROJECT_NAME "$expected_name"
check assert_env_value 1 DOCKER_BUNDLE_DIR "$expected_bundle"
check assert_env_value 1 DOCKER_CACHE_DIR "$expected_cache_dir"
check test ! -e "$expected_bundle"
check test ! -e "$fixture/cache"
reset_calls
check env HOME="$fixture/hostile-home" XDG_CACHE_HOME="$fixture/hostile-xdg" "$runner" compose config --images app >/dev/null
check assert_env_value 1 DOCKER_BUNDLE_DIR "$expected_bundle"
check assert_env_value 1 DOCKER_CACHE_DIR "$expected_cache_dir"
check test ! -e "$fixture/hostile-xdg"
reset_calls
check bash -c 'source_project=$1; caller_dir=$2; shift 2; cd "$source_project"; source_pwd=$PWD; before_project=${COMPOSE_PROJECT_NAME-}; DOCKER_BUNDLE_DIR=caller-value; DOCKER_CACHE_DIR=caller-cache; export DOCKER_BUNDLE_DIR DOCKER_CACHE_DIR; source ./dockerized.sh >/dev/null; [[ $PWD == "$source_pwd" && ${COMPOSE_PROJECT_NAME-} == "$before_project" && $DOCKER_BUNDLE_DIR == caller-value && $DOCKER_CACHE_DIR == caller-cache ]] || exit 11; cd "$caller_dir"; before_pwd=$PWD; ruby -e "argument with spaces"; [[ $PWD == "$before_pwd" && ${COMPOSE_PROJECT_NAME-} == "$before_project" && $DOCKER_BUNDLE_DIR == caller-value && $DOCKER_CACHE_DIR == caller-cache ]]' bash "$project" "$outside"
check assert_call_args 1 compose ps --services --status running
check assert_call_has_arg 2 'argument with spaces'
check assert_env_value 2 PWD "$project"
check assert_env_value 2 COMPOSE_PROJECT_NAME "$expected_name"
check assert_env_value 2 DOCKER_BUNDLE_DIR "$expected_bundle"
check assert_env_value 2 DOCKER_CACHE_DIR "$expected_cache_dir"
check test ! -e "$expected_bundle"
reset_calls
check env COMPOSE_PROJECT_NAME=editor-project "$runner" compose config --images app >/dev/null
check assert_env_value 1 COMPOSE_PROJECT_NAME editor-project
check assert_env_value 1 DOCKER_BUNDLE_DIR "$expected_bundle"
check assert_env_value 1 DOCKER_CACHE_DIR "$expected_cache_dir"
reset_calls
check env COMPOSE_FILE=compose.ci.yaml "$runner" compose config >/dev/null
check assert_env_value 1 COMPOSE_FILE compose.ci.yaml

# setup builds explicitly and installs dependencies without starting the app command.
reset_calls
export DOCKER_TEST_REQUIRE_SETUP_DIRS=true
check bash -c 'cd "$1" && "$2" setup' bash "$outside" "$runner"
check assert_call_args 1 compose --progress quiet build app
check assert_call_args 2 compose --progress quiet run --rm --no-deps -T app bundle install
check test -d "$expected_bundle"
check test -d "$expected_cache_dir"
check assert_env_value 2 PWD "$project"
check assert_env_value 2 COMPOSE_PROJECT_NAME "$expected_name"
unset DOCKER_TEST_REQUIRE_SETUP_DIRS

# An unprepared checkout fails closed without creating its lockfile or cache.
reset_calls
check test ! -e "$project/Gemfile.lock"
if (cd "$outside" && "$runner" lsp) > "$fixture/stdout" 2> "$fixture/stderr"; then check false; fi
check test ! -s "$fixture/stdout"
check grep -qi setup "$fixture/stderr"
check test ! -e "$project/Gemfile.lock"
check test "$(if [[ -f "$fixture/call-count" ]]; then cat "$fixture/call-count"; else printf 0; fi)" -eq 0

# LSP also requires a pre-existing cache and never creates one itself.
rm -rf "$expected_bundle"
touch "$project/Gemfile.lock"
reset_calls
if (cd "$outside" && "$runner" lsp) > "$fixture/stdout" 2> "$fixture/stderr"; then check false; fi
check test ! -s "$fixture/stdout"
check grep -qi setup "$fixture/stderr"
check test ! -e "$expected_bundle"
check test "$(if [[ -f "$fixture/call-count" ]]; then cat "$fixture/call-count"; else printf 0; fi)" -eq 0
mkdir -p "$expected_bundle"

# LSP validates one configured image and an existing local image before running.
reset_calls
export DOCKER_TEST_IMAGE_MODE=two
if (cd "$outside" && "$runner" lsp) > "$fixture/stdout" 2> "$fixture/stderr"; then check false; fi
check test ! -s "$fixture/stdout"
check test "$(cat "$fixture/call-count")" -eq 1
check assert_call_args 1 compose --progress quiet config --no-env-resolution --images editor
export DOCKER_TEST_IMAGE_MODE=one DOCKER_TEST_IMAGE_EXISTS=false
reset_calls
if (cd "$outside" && "$runner" lsp) > "$fixture/stdout" 2> "$fixture/stderr"; then check false; fi
check test ! -s "$fixture/stdout"
check grep -qi image "$fixture/stderr"
check test "$(cat "$fixture/call-count")" -eq 2
check assert_call_args 1 compose --progress quiet config --no-env-resolution --images editor
check assert_call_has_arg 2 "${expected_name}-app"
export DOCKER_TEST_IMAGE_EXISTS=true

# A prepared LSP uses one dedicated run with exact isolation flags and stdout passthrough.
reset_calls
check bash -c 'cd "$1" && "$2" lsp' bash "$outside" "$runner" > "$fixture/stdout" 2> "$fixture/stderr"
check test "$(cat "$fixture/stdout")" = ruby-lsp-protocol
check test ! -s "$fixture/stderr"
check test "$(cat "$fixture/call-count")" -eq 3
check assert_call_args 1 compose --progress quiet config --no-env-resolution --images editor
check assert_call_args 2 image inspect "${expected_name}-app"
check assert_call_args 3 compose --progress quiet run --rm --no-deps -T --pull never editor
check assert_env_value 3 PWD "$project"
check assert_env_value 3 COMPOSE_PROJECT_NAME "$expected_name"
check assert_env_value 3 DOCKER_BUNDLE_DIR "$expected_bundle"
check assert_env_value 3 DOCKER_CACHE_DIR "$expected_cache_dir"

# Rootful and unavailable daemons never reach setup or LSP commands.
for mode in rootful unavailable; do
  export DOCKER_TEST_MODE="$mode"
  for command in setup lsp; do
    reset_calls
    if (cd "$outside" && "$runner" "$command") > "$fixture/stdout" 2> "$fixture/stderr"; then check false; fi
    check test ! -s "$fixture/stdout"
    check grep -qi rootless "$fixture/stderr"
    check test "$(if [[ -f "$fixture/call-count" ]]; then cat "$fixture/call-count"; else printf 0; fi)" -eq 0
  done
done

if [[ "$failures" -gt 0 ]]; then
  printf '%s editor runner checks failed\n' "$failures" >&2
  exit 1
fi
bash "$(dirname "$0")/dockerized_project_path_test.sh" "$source_runner"
echo 'Editor runner checks passed (context, setup, LSP preflight, daemon guard, and arguments).'
