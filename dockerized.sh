#!/bin/bash

docker_compose_run_on_exec () {
  local container_name="$1"
  shift

  if docker compose ps | grep -q $container_name
  then
    docker compose exec -it $container_name "$@" 2>&1 | grep -v '^ app Pull'
    return ${PIPESTATUS[0]}
  else
    docker compose run --rm --quiet-pull -it --service-ports $container_name "$@" 2>&1 | grep -v '^ app Pull'
    return ${PIPESTATUS[0]}
  fi
}

# Declare functions for each name
names=("ruby" "rails" "bundle" "rake" "gem" "standardrb" "rubocop" "rspec" "lefthook" "spring" "brakeman")

for name in "${names[@]}"
do
  unset -f $name 2> /dev/null
  eval "
  function $name() {
    docker_compose_run_on_exec app $name \"\$@\"
  }
  "
done

export LEFTHOOK_BIN="lefthook" # Set the lefthook bin path, our custom wrappe
echo "Dockerized aliasses set"
