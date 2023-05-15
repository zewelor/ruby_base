FROM ghcr.io/zewelor/ruby:3.2.2-slim as base

ARG BUNDLER_VERSION=2.4.12
ARG RUNTIME_PACKAGES=""
ARG DEV_PACKAGES="build-essential git"

# We mount whole . dir into app, so vendor/bundle would get overwritten
ENV BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    GEM_HOME=/bundle

ENV PATH="${BUNDLE_BIN}:${PATH}"

# install dev dependencies
# hadolint ignore=SC2086,DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    $RUNTIME_PACKAGES && \
    apt-get clean && \
    rm -rf /var/lib/apt/ && \
    gem install bundler -v "$BUNDLER_VERSION"

FROM base as basedev

# install dev dependencies
# hadolint ignore=SC2086,DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    $DEV_PACKAGES && \
    apt-get clean && \
    rm -rf /var/lib/apt/

FROM basedev as dev

RUN mkdir -p "$BUNDLE_PATH" && \
    chown -R app:app "$BUNDLE_PATH"

USER app

# https://code.visualstudio.com/remote/advancedcontainers/avoid-extension-reinstalls
RUN gem install bundler -v "$BUNDLER_VERSION" && \
    mkdir -p "$HOME/.vscode-server/"

FROM basedev as baseliveci

# Workdir set in base image
# hadolint ignore=DL3045
COPY --chown=app:app Gemfile Gemfile.lock .ruby-version ./

FROM baseliveci as ci

# hadolint ignore=SC2086
RUN mkdir -p $BUNDLE_PATH && \
    chown -R app $BUNDLE_PATH

RUN bundle install "-j$(nproc)" --retry 3 && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

FROM baseliveci as live_builder

RUN bundle install "-j$(nproc)" --retry 3 && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

FROM base as live

# We enable `BUNDLE_DEPLOYMENT` so that bundler won't take the liberty to upgrade any gems.
ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development:test" \
    RUBYOPT='--disable-did_you_mean'

# Workdir set in base image
# hadolint ignore=DL3045
COPY --chown=app:app --from=live_builder $BUNDLE_PATH $BUNDLE_PATH
# hadolint ignore=DL3045
COPY --chown=app:app . .ruby-version ./

USER app

ENTRYPOINT ["tini", "--", "bin/cli"]
