ARG RUNTIME_PACKAGES=""
ARG DEV_PACKAGES="build-essential git libyaml-dev"

FROM ghcr.io/zewelor/ruby:4.0.1-slim AS base

ARG RUNTIME_PACKAGES

# We mount whole . dir into app, so vendor/bundle would get overwritten
ENV DEBIAN_FRONTEND=noninteractive \
  BUNDLE_PATH=/bundle \
  GEM_HOME=/bundle

# install runtime dependencies
# SC2086: Double quote to prevent globbing - intentionally unquoted for word splitting
# DL3008: Pin versions in apt-get - versions come from ARG, pinning not practical
# hadolint ignore=SC2086,DL3008
RUN set -eux; \
  if [ -n "$RUNTIME_PACKAGES" ]; then \
  apt-get update; \
  apt-get install -y --no-install-recommends $RUNTIME_PACKAGES; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/*; \
  fi; \
  rm -rf /tmp/* /var/tmp/*

FROM base AS basedev

ARG DEV_PACKAGES

ENV BUNDLE_AUTO_INSTALL=true

# install development dependencies
# SC2086: Double quote to prevent globbing - intentionally unquoted for word splitting
# DL3008: Pin versions in apt-get - versions come from ARG, pinning not practical
# hadolint ignore=SC2086,DL3008
RUN set -eux; \
  if [ -n "$DEV_PACKAGES" ]; then \
  apt-get update; \
  apt-get install -y --no-install-recommends $DEV_PACKAGES; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/*; \
  fi; \
  rm -rf /tmp/* /var/tmp/*

FROM basedev AS dev

RUN mkdir -p "$BUNDLE_PATH" && \
  chown -R app:app "$BUNDLE_PATH"

USER app

# https://code.visualstudio.com/remote/advancedcontainers/avoid-extension-reinstalls
RUN mkdir -p "$HOME/.vscode-server/"

FROM basedev AS baseliveci

# DL3045: COPY to relative destination without WORKDIR - WORKDIR /app is set in base image
# hadolint ignore=DL3045
COPY --chown=app:app Gemfile ./

FROM baseliveci AS ci

# SC2086: Double quote to prevent globbing - variable is safe, quoting optional
# hadolint ignore=SC2086
RUN mkdir -p $BUNDLE_PATH && \
  chown -R app $BUNDLE_PATH

RUN bundle install "-j$(nproc)" --retry 3 && \
  rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

FROM baseliveci AS live_builder

ENV BUNDLE_WITHOUT="development:test"

RUN bundle install "-j$(nproc)" --retry 3 && \
  rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

FROM base AS live

# We enable `BUNDLE_DEPLOYMENT` so that bundler won't take the liberty to upgrade any gems.
ENV BUNDLE_DEPLOYMENT="1" \
  BUNDLE_WITHOUT="development:test" \
  RUBYOPT='--disable-did_you_mean'

# DL3045: COPY to relative destination without WORKDIR - WORKDIR /app is set in base image
# hadolint ignore=DL3045
COPY --chown=app:app --from=live_builder $BUNDLE_PATH $BUNDLE_PATH
# DL3045: COPY to relative destination without WORKDIR - WORKDIR /app is set in base image
# hadolint ignore=DL3045
COPY --chown=app:app . ./

# Minimal cleanup for runtime size (keep package manager intact).
RUN rm -rf \
  /usr/share/doc \
  /usr/share/man \
  /usr/share/info \
  /usr/share/lintian \
  /usr/share/locale \
  /var/log/* \
  /var/cache/* \
  /tmp/* \
  /var/tmp/*

USER app

ENTRYPOINT ["ruby", "bin/cli"]

FROM live_builder AS distroless_builder

# DL3045: COPY to relative destination without WORKDIR - WORKDIR /app is set in base image
# hadolint ignore=DL3045
COPY --chown=app:app . ./

RUN set -eux; \
  chown -R 65532:65532 /bundle /app

FROM ghcr.io/zewelor/ruby:latest-distroless AS distroless

ENV BUNDLE_PATH=/bundle \
  GEM_HOME=/bundle \
  BUNDLE_DEPLOYMENT="1" \
  BUNDLE_WITHOUT="development:test" \
  RUBYOPT='--disable-did_you_mean'

WORKDIR /app

COPY --from=distroless_builder /bundle/ /bundle/
COPY --from=distroless_builder /app/ /app/

USER nonroot

ENTRYPOINT ["ruby", "bin/cli"]
