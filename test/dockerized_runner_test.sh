#!/usr/bin/env bash
# Exercise the public runner with a fake daemon; no Docker access is needed.
set -eu
runner="${1:-./dockerized.sh}"
runner="$(cd "$(dirname "$runner")" && pwd)/$(basename "$runner")"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin"
export DOCKER_TEST_DIR="$fixture" DOCKER_TEST_MODE=rootless DOCKER_TEST_RUNNING=false DOCKER_TEST_PS_FAIL=false
export PATH="$fixture/bin:$PATH"
cat > "$fixture/bin/docker" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == info ]]; then
  case "$DOCKER_TEST_MODE" in
    rootless) printf '%s\n' '["name=seccomp,profile=builtin","name=rootless"]' ;;
    rootful) printf '%s\n' '["name=seccomp,profile=builtin"]' ;;
    unavailable) exit 42 ;;
  esac
  exit 0
fi
printf '%s\n' "$@" > "$DOCKER_TEST_DIR/arguments"
for arg in "$@"; do
  case "$arg" in
    ps)
      [[ "$DOCKER_TEST_PS_FAIL" != true ]] || exit 42
      [[ "$DOCKER_TEST_RUNNING" != true ]] || echo app
      exit 0 ;;
    run|exec|up) echo "$arg" >> "$DOCKER_TEST_DIR/launches"; exit 0 ;;
  esac
done
exit 99
SH
chmod +x "$fixture/bin/docker"
failures=0
check() {
  if ! "$@"; then
    printf 'FAIL: %s\n' "$*" >&2
    failures=$((failures + 1))
  fi
}
reset_calls() { : > "$fixture/launches"; : > "$fixture/stderr"; }
alias_run() { bash -c 'runner="$1"; shift; source "$runner" >/dev/null; ruby -e "argument with spaces"' bash "$runner"; }
reset_calls
check alias_run
check test "$(cat "$fixture/launches")" = run
check test "$(tail -n 1 "$fixture/arguments")" = 'argument with spaces'
export DOCKER_TEST_RUNNING=true
reset_calls
check alias_run
check test "$(cat "$fixture/launches")" = exec
export DOCKER_TEST_RUNNING=false
for mode in rootful unavailable; do
  export DOCKER_TEST_MODE="$mode" DOCKER_CONTEXT=rootless
  reset_calls
  if alias_run 2> "$fixture/stderr"; then check false; fi
  check test ! -s "$fixture/launches"
  check grep -qi rootless "$fixture/stderr"
  reset_calls
  if COMPOSE_FILE=compose.ci.yaml bash "$runner" compose -f compose.yaml up > /dev/null 2> "$fixture/stderr"; then check false; fi
  check test ! -s "$fixture/launches"
  check grep -qi rootless "$fixture/stderr"
done
export DOCKER_TEST_MODE=rootless DOCKER_TEST_PS_FAIL=true
reset_calls
if alias_run 2> "$fixture/stderr"; then check false; fi
check test ! -s "$fixture/launches"
export DOCKER_TEST_PS_FAIL=false
reset_calls
if bash -c 'runner="$1"; shift; source "$runner" >/dev/null; ruby -e first; export DOCKER_TEST_MODE=rootful; ruby -e second' bash "$runner" 2> "$fixture/stderr"; then check false; fi
check test "$(wc -l < "$fixture/launches")" -eq 1
reset_calls
check bash "$runner" compose run --rm app ruby -e 'argument with spaces' > "$fixture/stdout"
check test ! -s "$fixture/stdout"
check test "$(cat "$fixture/launches")" = run
check test "$(tail -n 1 "$fixture/arguments")" = 'argument with spaces'
if [[ "$failures" -gt 0 ]]; then
  printf '%s runner checks failed\n' "$failures" >&2
  exit 1
fi
echo 'Runner checks passed (run, exec, rootful, unavailable, CI override, ps failure, recheck, argument forwarding).'
