docker_build:
  docker compose build --no-cache --build-arg RUBY_VERSION=$(cat .ruby-version)
