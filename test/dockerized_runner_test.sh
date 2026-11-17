#!/usr/bin/env bash
# Exercise the public runner with a fake daemon; no Docker access is needed.
# Fixture strings deliberately defer expansion or exercise literal argument forwarding.
# shellcheck disable=SC2016
set -euo pipefail
runner="${1:-./dockerized.sh}"
runner="$(cd -- "$(dirname -- "$runner")" && pwd -P)/$(basename -- "$runner")"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
project="$fixture/project with spaces"
mkdir -p "$project/nested" "$project/bin" "$fixture/bin" "$fixture/calls"
cp "$runner" "$project/dockerized.sh"
cp "${runner%/*}/compose.yaml" "$project/compose.yaml"
cp "${runner%/*}/bin/lefthook" "$project/bin/lefthook"
export DOCKER_TEST_DIR="$fixture" DOCKER_TEST_MODE=rootless DOCKER_TEST_IMAGE=true
export DOCKER_TEST_PLUGIN="$fixture/bin/compose" DOCKER_TEST_EXIT=0 DOCKER_TEST_BUILD_EXIT=0 DOCKER_TEST_GIT_EXIT=0
export PATH="$fixture/bin:$PATH"
unset COMPOSE_PROJECT_NAME COMPOSE_FILE DOCKER_PROJECT_DIR DOCKER_BUNDLE_DIR DOCKER_CACHE_DIR DOCKER_GIT_COMMON_DIR
cat > "$fixture/bin/git" <<'SH'
#!/usr/bin/env bash
set -eu
[[ "$#" == 5 && "$1" == -C && "$3" == rev-parse && "$4" == --path-format=absolute && "$5" == --git-common-dir ]] || exit 99
[[ "$DOCKER_TEST_GIT_EXIT" == 0 ]] || exit "$DOCKER_TEST_GIT_EXIT"
printf '%s\n' "$DOCKER_TEST_DIR/shared metadata/.git"
SH
cat > "$fixture/bin/docker" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$DOCKER_TEST_DIR/docker-calls"
case "$1" in
  info)
    if [[ "$*" == *ClientInfo.Plugins* ]]; then
      printf '%s\n' "$DOCKER_TEST_PLUGIN"
    else
      case "$DOCKER_TEST_MODE" in
        rootless) printf '%s\n' '["name=seccomp,profile=builtin","name=rootless"]' ;;
        rootful) printf '%s\n' '["name=seccomp,profile=builtin"]' ;;
        unavailable) exit 42 ;;
      esac
    fi ;;
  image) [[ "$DOCKER_TEST_IMAGE" == true ]] ;;
  compose) shift; exec "$DOCKER_TEST_PLUGIN" "$@" ;;
  *) exit 99 ;;
esac
SH
cat > "$fixture/bin/compose" <<'SH'
#!/usr/bin/env bash
set -eu
count=$(find "$DOCKER_TEST_DIR/calls" -mindepth 1 -maxdepth 1 -type d | wc -l)
call="$DOCKER_TEST_DIR/calls/$((count + 1))"
mkdir "$call"
printf '%s\0' "$@" > "$call/args"
printf '%s\n' "$PWD" > "$call/cwd"
printf '%s\n' "${COMPOSE_PROJECT_NAME-}" > "$call/project"
printf '%s\n' "${DOCKER_PROJECT_DIR-}" > "$call/root"
printf '%s\n' "${DOCKER_GIT_COMMON_DIR-}" > "$call/git-common"
printf '%s\n' "${DOCKER_BUNDLE_DIR-}" > "$call/bundle"
printf '%s\n' "${DOCKER_CACHE_DIR-}" > "$call/cache"
for arg in "$@"; do
  case "$arg" in
    config)
      if [[ "$*" == *--images* ]]; then printf '%s\n' prepared-image; fi
      exit 0 ;;
    build) exit "$DOCKER_TEST_BUILD_EXIT" ;;
    run|exec|up) exit "$DOCKER_TEST_EXIT" ;;
  esac
done
exit 0
SH
chmod +x "$fixture/bin/git" "$fixture/bin/docker" "$fixture/bin/compose"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
reset_calls() { rm -rf "$fixture/calls"; mkdir "$fixture/calls"; : > "$fixture/docker-calls"; }
load_last_call() {
  local count
  count=$(find "$fixture/calls" -mindepth 1 -maxdepth 1 -type d | wc -l)
  [[ "$count" -gt 0 ]] || fail 'Expected a Compose invocation'
  call="$fixture/calls/$count"
  mapfile -d '' -t actual < "$call/args"
}
assert_arg() {
  local arg
  for arg in "${actual[@]}"; do [[ "$arg" != "$1" ]] || return 0; done
  fail "Missing argument: $1"
}
assert_pair() {
  local i
  for ((i=0; i+1<${#actual[@]}; i++)); do
    if [[ "${actual[i]}" == "$1" && "${actual[i+1]}" == "$2" ]]; then return 0; fi
  done
  fail "Missing argument pair: $1 $2"
}
assert_suffix() {
  local offset=$((${#actual[@]} - $#)) expected
  for expected in "$@"; do
    [[ "$offset" -ge 0 && "${actual[offset]}" == "$expected" ]] || fail "Wrong command argument: $expected"
    offset=$((offset + 1))
  done
}
run_in() { (cd -- "$1"; shift; "$project/dockerized.sh" "$@"); }
expect_status() {
  local expected="$1" status=0
  shift
  "$@" > "$fixture/stdout" 2> "$fixture/stderr" || status=$?
  [[ "$status" == "$expected" ]] || fail "Expected exit $expected, got $status: $(cat "$fixture/stderr")"
}

# A relative file argument must resolve in the caller's directory in this checkout.
reset_calls
run_in "$project/nested" ruby -e 'literal $(touch never-created)' 'argument with spaces' $'two\nlines'
load_last_call
assert_pair --workdir "$project/nested"
assert_pair --project-directory "$project"
assert_pair --file "$project/compose.yaml"
assert_pair --pull never
assert_arg --no-deps
assert_arg -T
assert_suffix app ruby -e 'literal $(touch never-created)' 'argument with spaces' $'two\nlines'
[[ ! -e "$project/nested/never-created" ]] || fail 'Runner evaluated command arguments'
[[ "$(cat "$call/root")" == "$project" ]] || fail 'Wrong checkout root'
[[ "$(cat "$call/git-common")" == "$fixture/shared metadata/.git" ]] || fail 'Git metadata path was not resolved/exported'
[[ "$(cat "$call/bundle")" == "$project/.bundle/gems" ]] || fail 'Wrong bundle directory'
[[ "$(cat "$call/cache")" == "$project/.dev/cache" ]] || fail 'Wrong cache directory'
[[ ! -e "$project/.bundle" && ! -e "$project/.dev" ]] || fail 'Ordinary command prepared caches'
project_name="$(cat "$call/project")"

# Project identity is anchored to the checkout, independent of caller overrides/cwd.
COMPOSE_PROJECT_NAME=unrelated COMPOSE_FILE=compose.ci.yaml run_in "$project" bundle exec standardrb
load_last_call
assert_suffix app bundle exec standardrb
[[ "$(cat "$call/project")" == "$project_name" ]] || fail 'Caller changed checkout identity'
assert_pair --file "$project/compose.yaml"
other="$fixture/other checkout"
mkdir -p "$other"
cp "$project/dockerized.sh" "$project/compose.yaml" "$other/"
(cd -- "$other"; ./dockerized.sh ruby -e exit)
load_last_call
[[ "$(cat "$call/project")" != "$project_name" ]] || fail 'Different checkouts share an identity'
[[ "$(cat "$call/bundle")" == "$other/.bundle/gems" ]] || fail 'Different checkout reused bundle'
[[ "$(cat "$call/git-common")" == "$fixture/shared metadata/.git" ]] || fail 'Shared Git metadata changed between worktrees'
expect_status 37 env DOCKER_TEST_EXIT=37 bash -c 'cd "$1"; "$1/dockerized.sh" ruby -e exit' bash "$project"

# Failed Git metadata discovery must stop before any Docker operations.
reset_calls
expect_status 128 env DOCKER_TEST_GIT_EXIT=128 bash -c 'cd "$1"; ./dockerized.sh ruby -e exit' bash "$project"
[[ ! -s "$fixture/docker-calls" ]] || fail 'Git metadata failure reached Docker'

# Refuse unsupported daemons, missing images/plugin, and commands outside this checkout.
for mode in rootful unavailable; do
  reset_calls
  expect_status 1 env DOCKER_TEST_MODE="$mode" bash -c 'cd "$1"; ./dockerized.sh ruby -e exit' bash "$project"
  [[ -z "$(ls -A "$fixture/calls")" ]] || fail 'Unsupported daemon reached Compose'
  grep -qi rootless "$fixture/stderr" || fail 'Missing daemon diagnosis'
done
reset_calls
expect_status 1 env DOCKER_TEST_IMAGE=false bash -c 'cd "$1"; ./dockerized.sh ruby -e exit' bash "$project"
load_last_call
assert_arg config
grep -q setup "$fixture/stderr" || fail 'Missing image recovery instruction'
expect_status 1 env DOCKER_TEST_PLUGIN="$fixture/missing-plugin" bash -c 'cd "$1"; ./dockerized.sh ruby -e exit' bash "$project"
reset_calls
expect_status 1 run_in "$fixture" ruby -e exit
[[ ! -s "$fixture/docker-calls" ]] || fail 'Outside-checkout command contacted Docker'
expect_status 2 run_in "$project"
reset_calls
expect_status 2 bash -c 'source "$1/dockerized.sh"' bash "$project"
[[ ! -s "$fixture/docker-calls" ]] || fail 'Sourcing contacted Docker'

# Compose administration remains explicit; its arguments reach Compose unchanged.
reset_calls
run_in "$project" compose --profile optional config --services
load_last_call
assert_suffix --profile optional config --services

# Setup alone prepares caches/builds and explicitly permits local lockfile creation.
reset_calls
run_in "$project" setup
[[ -d "$project/.bundle/gems" && -d "$project/.dev/cache" ]] || fail 'Setup did not prepare checkout caches'
mapfile -d '' -t actual < "$fixture/calls/2/args"
[[ " ${actual[*]} " != *" --entrypoint "* ]] || fail 'Setup install bypasses image init'
assert_pair --env BUNDLE_FROZEN=false
assert_pair --pull never
assert_suffix app bundle install
load_last_call
[[ " ${actual[*]} " != *" --entrypoint "* ]] || fail 'Setup hook install bypasses image init'
assert_suffix app bundle exec lefthook install
[[ ! -e "$project/Gemfile.lock" ]] || fail 'Fake setup unexpectedly wrote a lockfile'
reset_calls
expect_status 29 env DOCKER_TEST_BUILD_EXIT=29 bash -c 'cd "$1"; ./dockerized.sh setup' bash "$project"
[[ -d "$fixture/calls/1" && ! -e "$fixture/calls/2" ]] || fail 'Setup continued after build failure'

# LSP requires preparation and starts only the offline editor service.
reset_calls
expect_status 1 run_in "$project" lsp
[[ -z "$(ls -A "$fixture/calls")" ]] || fail 'Unprepared editor reached Compose'
printf 'fixture lockfile\n' > "$project/Gemfile.lock"
run_in "$project/nested" lsp
load_last_call
assert_pair --pull never
assert_arg --no-deps
assert_arg -T
assert_suffix editor
expect_status 1 env DOCKER_TEST_IMAGE=false bash -c 'cd "$1"; ./dockerized.sh lsp' bash "$project"

# The tracked hook bridge runs through Docker, with no host Ruby/Lefthook executable.
reset_calls
(cd -- "$project/nested"; "$project/bin/lefthook" run pre-commit 'argument with spaces')
load_last_call
assert_pair --workdir "$project"
assert_suffix app bundle exec lefthook run pre-commit 'argument with spaces'
printf '%s\n' 'Runner checks passed (literal arguments, cwd, checkout isolation, daemon/image failures, setup, offline LSP, hook bridge).'
