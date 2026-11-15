#!/usr/bin/env bash
# Verify project-scoped PATH activation and external child wrappers with fake Docker only.
set -eu

runner="${1:-./dockerized.sh}"
runner="$(cd "$(dirname "$runner")" && pwd -P)/$(basename "$runner")"
runner_root="$(dirname "$runner")"
test_repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
project="$fixture/Ruby Project"
other_project="$fixture/Other Project"
mkdir -p "$project" "$other_project" "$fixture/bin"
cp "$runner" "$project/dockerized.sh"
cp "$runner" "$other_project/dockerized.sh"
if [[ -d "$runner_root/.dev" ]]; then
  for checkout in "$project" "$other_project"; do
    mkdir -p "$checkout/.dev"
    cp -a "$runner_root/.dev/run" "$checkout/.dev/run"
    if [[ -d "$runner_root/.dev/bin" ]]; then
      cp -a "$runner_root/.dev/bin" "$checkout/.dev/bin"
    fi
  done
fi

unset HOME XDG_CACHE_HOME
export DOCKER_TEST_DIR="$fixture" DOCKER_TEST_UID="$(id -u)"
export PATH="$fixture/bin:/usr/bin:/bin"
cat > "$fixture/bin/docker" <<'SH'
#!/usr/bin/env bash
set -eu
if [[ "$1" == info ]]; then
  printf '%s\n' '["name=seccomp,profile=builtin","name=rootless"]'
  exit
fi
n=0
[[ ! -f "$DOCKER_TEST_DIR/call-count" ]] || read -r n < "$DOCKER_TEST_DIR/call-count"
n=$((n + 1))
printf '%s\n' "$n" > "$DOCKER_TEST_DIR/call-count"
printf '%s\0' "$@" > "$DOCKER_TEST_DIR/call-$n.argv"
{
  printf 'PWD=%s\n' "$PWD"
  printf 'COMPOSE_PROJECT_NAME=%s\n' "${COMPOSE_PROJECT_NAME-}"
  printf 'DOCKER_BUNDLE_DIR=%s\n' "${DOCKER_BUNDLE_DIR-}"
  printf 'DOCKER_CACHE_DIR=%s\n' "${DOCKER_CACHE_DIR-}"
} > "$DOCKER_TEST_DIR/call-$n.env"
if [[ "$1" == image && "$2" == inspect ]]; then
  exit
fi
[[ "$1" == compose ]] || exit 99
subcommand=""
for arg in "$@"; do
  case "$arg" in
    config|ps|run|exec|up) subcommand="$arg"; break ;;
  esac
done
case "$subcommand" in
  config) printf '%s\n' "${COMPOSE_PROJECT_NAME}-app" ;;
  ps) ;;
  run|exec|up)
    if [[ " $* " == *" editor "* ]]; then
      printf '%s\n' ruby-lsp-protocol
    fi
    ;;
  *) exit 98 ;;
esac
SH
chmod +x "$fixture/bin/docker"

failures=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}
assert_call_args() {
  local number="$1"
  shift
  printf '%s\0' "$@" > "$fixture/expected.argv"
  cmp "$fixture/expected.argv" "$fixture/call-$number.argv"
}

reset_calls() {
  rm -f "$fixture"/call-[0-9]*.argv "$fixture"/call-[0-9]*.env "$fixture/call-count"
  : > "$fixture/stdout"
  : > "$fixture/stderr"
}
assert_env_value() {
  local number="$1" key="$2" value="$3"
  grep -Fqx "$key=$value" "$fixture/call-$number.env"
}
project_name() {
  local project_path="$1" slug digest
  slug="${project_path##*/}"
  slug="${slug,,}"
  slug="${slug//[^a-z0-9_-]/-}"
  digest="$(printf '%s' "$project_path" | sha256sum)"
  printf 'dev-%s-%s' "${slug:0:32}" "${digest:0:12}"
}

# Sourcing must be silent, preserve cwd and shell flags, and move one absolute bin to PATH.
reset_calls
if ! bash -c '
  project="$1"
  bin="$project/.dev/bin"
  before_pwd="$PWD"
  before_flags="$-"
  ruby() { return 0; }
  rake() { return 0; }
  eval "function bin/old { :; }"
  _dockerized_path_functions=(bin/old)
  source "$project/dockerized.sh"
  if typeset -f bin/old >/dev/null 2>&1; then exit 81; fi
  [[ "$PWD" == "$before_pwd" && "$-" == "$before_flags" ]] || exit 11
  source "$project/dockerized.sh"
  if typeset -f bin/old >/dev/null 2>&1; then exit 81; fi
  [[ "$PWD" == "$before_pwd" && "$-" == "$before_flags" ]] || exit 12
  [[ "${PATH%%:*}" == "$bin" ]] || exit 13
  count="$(printf "%s\n" "$PATH" | tr ":" "\n" | grep -Fxc "$bin" || true)"
  [[ "$count" == 1 ]] || exit 14
  [[ "$(type -P ruby-lsp)" == "$bin/ruby-lsp" ]] || exit 15
  [[ "$(type -t ruby)" == file ]] || exit 16
  [[ "$(type -t rake)" == file ]] || exit 17
' bash "$project" > "$fixture/stdout" 2> "$fixture/stderr"; then
  fail 'Bash source contract'
fi
[[ ! -s "$fixture/stdout" && ! -s "$fixture/stderr" ]] || fail 'Bash source must be silent'
[[ ! -e "$fixture/call-count" ]] || fail 'Bash source must not call Docker'
[[ ! -e "$project/.bundle/gems" && ! -e "$project/.dev/cache" ]] || fail 'Sourcing must not create project caches'

if command -v zsh >/dev/null 2>&1; then
  if ! zsh -c '
    project="$1"
    bin="$project/.dev/bin"
    before_pwd="$PWD"
    before_flags="$-"
    ruby() { return 0; }
    rake() { return 0; }
  eval "function bin/old { :; }"
  _dockerized_path_functions=(bin/old)
    source "$project/dockerized.sh"
  if typeset -f bin/old >/dev/null 2>&1; then exit 81; fi
    [[ "$PWD" == "$before_pwd" && "$-" == "$before_flags" ]] || exit 21
    source "$project/dockerized.sh"
  if typeset -f bin/old >/dev/null 2>&1; then exit 81; fi
    [[ "$PWD" == "$before_pwd" && "$-" == "$before_flags" ]] || exit 22
    [[ "${PATH%%:*}" == "$bin" ]] || exit 23
    count="$(print -r -- "$PATH" | tr ":" "\n" | grep -Fxc "$bin" || true)"
    [[ "$count" == 1 ]] || exit 24
    [[ "$(whence -p ruby-lsp)" == "$bin/ruby-lsp" ]] || exit 25
    [[ "$(whence -w ruby)" == "ruby: command" ]] || exit 26
  ' zsh "$project" > "$fixture/stdout" 2> "$fixture/stderr"; then
    fail 'Zsh source contract'
  fi
  [[ ! -s "$fixture/stdout" && ! -s "$fixture/stderr" ]] || fail 'Zsh source must be silent'
  [[ ! -e "$fixture/call-count" ]] || fail 'Zsh source must not call Docker'

  if ! zsh -c '
    source "$1/dockerized.sh"
    source "$2/dockerized.sh"
    source "$2/dockerized.sh"
    bin="$2/.dev/bin"
    [[ "${PATH%%:*}" == "$bin" ]] || exit 26
    count="$(print -r -- "$PATH" | tr ":" "\n" | grep -Fxc "$bin" || true)"
    [[ "$count" == 1 ]] || exit 27
    [[ "$(whence -p ruby-lsp)" == "$bin/ruby-lsp" ]] || exit 28
    source "$1/dockerized.sh"
    bin="$1/.dev/bin"
    [[ "${PATH%%:*}" == "$bin" ]] || exit 29
    count="$(print -r -- "$PATH" | tr ":" "\n" | grep -Fxc "$bin" || true)"
    [[ "$count" == 1 ]] || exit 30
    [[ "$(whence -p ruby-lsp)" == "$bin/ruby-lsp" ]] || exit 31
    other_count="$(print -r -- "$PATH" | tr ":" "\n" | grep -Fxc "$2/.dev/bin" || true)"
    [[ "$other_count" == 0 ]] || exit 32
  ' zsh "$project" "$other_project" > "$fixture/stdout" 2> "$fixture/stderr"; then
    fail 'Zsh project switch'
  fi
  [[ ! -s "$fixture/stdout" && ! -s "$fixture/stderr" ]] || fail 'Zsh project switch must be silent'
else
  printf '%s\n' 'SKIP: zsh is not installed' >&2
fi

if ! bash -c '
  source "$1/dockerized.sh"
  source "$2/dockerized.sh"
  source "$2/dockerized.sh"
  bin="$2/.dev/bin"
  [[ "${PATH%%:*}" == "$bin" ]] || exit 31
  count="$(printf "%s\n" "$PATH" | tr ":" "\n" | grep -Fxc "$bin" || true)"
  [[ "$count" == 1 ]] || exit 32
  [[ "$(type -P ruby-lsp)" == "$bin/ruby-lsp" ]] || exit 33
  source "$1/dockerized.sh"
  bin="$1/.dev/bin"
  [[ "${PATH%%:*}" == "$bin" ]] || exit 34
  count="$(printf "%s\n" "$PATH" | tr ":" "\n" | grep -Fxc "$bin" || true)"
  [[ "$count" == 1 ]] || exit 35
  [[ "$(type -P ruby-lsp)" == "$bin/ruby-lsp" ]] || exit 36
  other_count="$(printf "%s\n" "$PATH" | tr ":" "\n" | grep -Fxc "$2/.dev/bin" || true)"
  [[ "$other_count" == 0 ]] || exit 37
' bash "$project" "$other_project" > "$fixture/stdout" 2> "$fixture/stderr"; then
  fail 'Bash project switch'
fi
[[ ! -s "$fixture/stdout" && ! -s "$fixture/stderr" ]] || fail 'Bash project switch must be silent'
[[ ! -e "$fixture/call-count" ]] || fail 'Project switching must not call Docker'

# Separate checkout copies resolve generated paths from their own real project roots.
reset_calls
if ! "$project/dockerized.sh" compose config --images app > "$fixture/stdout" 2> "$fixture/stderr"; then
  fail 'Project cache context'
fi
[[ ! -s "$fixture/stderr" ]] || fail 'Project cache context stderr'
assert_env_value 1 PWD "$project" || fail 'Project PWD context'
assert_env_value 1 DOCKER_BUNDLE_DIR "$project/.bundle/gems" || fail 'Project bundle path'
assert_env_value 1 DOCKER_CACHE_DIR "$project/.dev/cache" || fail 'Project cache path'
[[ ! -e "$project/.dev/cache/npm" ]] || fail 'Compose config must not create the Wrangler cache'
reset_calls
if ! "$other_project/dockerized.sh" compose config --images app > "$fixture/stdout" 2> "$fixture/stderr"; then
  fail 'Other project cache context'
fi
[[ ! -s "$fixture/stderr" ]] || fail 'Other project cache context stderr'
assert_env_value 1 PWD "$other_project" || fail 'Other project PWD context'
assert_env_value 1 DOCKER_BUNDLE_DIR "$other_project/.bundle/gems" || fail 'Other project bundle path'
assert_env_value 1 DOCKER_CACHE_DIR "$other_project/.dev/cache" || fail 'Other project cache path'
[[ ! -e "$other_project/.dev/cache/npm" ]] || fail 'Other Compose config must not create the Wrangler cache'

# The links are static and expose only commands the project already routes.
case "$test_repo_root" in
  */ruby_base) supported="ruby gem bundle rails rake standardrb rubocop rspec lefthook spring brakeman" ;;
  */dottales) supported="ruby bundle rake gem standardrb rubocop rspec lefthook jekyll yamllint wrangler" ;;
  *) fail "Unknown project command set: $test_repo_root"; supported="ruby rake" ;;
esac
for name in ruby-lsp $supported; do
  [[ -L "$project/.dev/bin/$name" ]] || fail "Missing wrapper link: $name"
  [[ "$(readlink "$project/.dev/bin/$name" 2>/dev/null || true)" == ../run ]] || fail "Wrong wrapper target: $name"
  [[ -x "$project/.dev/bin/$name" ]] || fail "Wrapper is not executable: $name"
done
[[ -x "$project/.dev/run" ]] || fail '.dev/run must be executable'
[[ ! -e "$project/.dev/bin/dprint" ]] || fail 'dprint is not supported by this project'

# A separate Bash process inherits PATH, resolves the project wrappers, and calls only fake Docker.
if [[ -x "$project/.dev/bin/ruby-lsp" && -x "$project/.dev/bin/ruby" ]]; then
  mkdir -p "$project/.bundle/gems"
  touch "$project/Gemfile.lock"
  reset_calls
  child_script='project="$1"
test "$(command -v ruby-lsp)" = "$project/.dev/bin/ruby-lsp" || exit 41
test "$(command -v ruby)" = "$project/.dev/bin/ruby" || exit 42
ruby-lsp --stdio
ruby -e "argument with spaces"'
  if ! bash -c 'project="$1"; source "$project/dockerized.sh"; bash -c "$2" bash "$project"' bash "$project" "$child_script" > "$fixture/stdout" 2> "$fixture/stderr"; then
    fail 'Child-process PATH wrappers'
  fi
  [[ "$(cat "$fixture/stdout")" == ruby-lsp-protocol ]] || fail 'Child wrapper stdout'
  [[ ! -s "$fixture/stderr" ]] || fail 'Child wrapper stderr'
  [[ "$(cat "$fixture/call-count")" -eq 5 ]] || fail 'Child wrapper Docker call count'
  expected_name="$(project_name "$project")"
  assert_call_args 1 compose --progress quiet config --no-env-resolution --images editor || fail 'LSP config args'
  assert_call_args 2 image inspect "${expected_name}-app" || fail 'LSP image args'
  assert_call_args 3 compose --progress quiet run --rm --no-deps -T --pull never editor || fail 'LSP run args'
  assert_call_args 4 compose ps --services --status running || fail 'Ruby service check args'
  if [[ "$test_repo_root" == */ruby_base ]]; then
    assert_call_args 5 compose --progress quiet run --rm -T --service-ports app ruby -e 'argument with spaces' || fail 'Ruby wrapper args'
  else
    assert_call_args 5 compose --progress quiet run --rm -T app ruby -e 'argument with spaces' || fail 'Ruby wrapper args'
    [[ ! -e "$project/.dev/cache/npm" ]] || fail 'Ruby LSP and app wrappers must not create the Wrangler cache'
  fi
else
  fail 'Child-process wrappers are unavailable'
fi

if [[ "$test_repo_root" == */dottales ]]; then
  rm -rf "$project/.dev/cache"
  : > "$project/.dev/cache"
  reset_calls
  if "$project/dockerized.sh" wrangler whoami > "$fixture/stdout" 2> "$fixture/stderr"; then
    fail 'Wrangler must stop when its local npm cache cannot be created'
  fi
  grep -qi 'Could not prepare the checkout Wrangler npm cache' "$fixture/stderr" || fail 'Wrangler cache failure must be visible'
  [[ ! -f "$fixture/call-count" ]] || fail 'Wrangler cache failure must stop before Compose'
  rm -f "$project/.dev/cache"

  reset_calls
  if ! "$project/dockerized.sh" wrangler whoami > "$fixture/stdout" 2> "$fixture/stderr"; then
    fail 'Wrangler wrapper with local npm cache'
  fi
  [[ ! -s "$fixture/stderr" ]] || fail 'Wrangler wrapper stderr'
  [[ -d "$project/.dev/cache/npm" && "$(stat -c %u "$project/.dev/cache/npm")" == "$DOCKER_TEST_UID" ]] || fail 'Wrangler cache must be precreated as the invoking user'
  assert_env_value 1 DOCKER_CACHE_DIR "$project/.dev/cache" || fail 'Wrangler cache context'

  rm -rf "$project/.dev/cache"
  reset_calls
  if ! "$project/dockerized.sh" compose up --remove-orphans worker-dev > "$fixture/stdout" 2> "$fixture/stderr"; then
    fail 'worker-dev Compose context with local npm cache'
  fi
  [[ ! -s "$fixture/stderr" ]] || fail 'worker-dev Compose stderr'
  [[ -d "$project/.dev/cache/npm" && "$(stat -c %u "$project/.dev/cache/npm")" == "$DOCKER_TEST_UID" ]] || fail 'worker-dev cache must be precreated as the invoking user'
  assert_env_value 1 DOCKER_CACHE_DIR "$project/.dev/cache" || fail 'worker-dev cache context'
fi

[[ "$failures" -eq 0 ]] || exit 1
echo 'Project path checks passed (Bash, Zsh, project switching, and child wrappers).'
