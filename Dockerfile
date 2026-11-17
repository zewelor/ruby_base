ARG RUNTIME_PACKAGES=""
ARG DEV_PACKAGES="build-essential git libyaml-dev"

FROM ghcr.io/zewelor/ruby:4.0.9-slim@sha256:7fe782af8e5ca83e9a72899f245fd9fbff797f89c84e899cf355c68a21b7fda2 AS base

WORKDIR /app

ARG RUNTIME_PACKAGES

# We mount whole . dir into app, so vendor/bundle would get overwritten
ENV DEBIAN_FRONTEND=noninteractive \
  BUNDLE_PATH=/bundle \
  BUNDLE_VERSION=system \
  GEM_HOME=/bundle

# install runtime dependencies
# SC2086: Double quote to prevent globbing - intentionally unquoted for word splitting
# DL3008: Pin versions in apt-get - versions come from ARG, pinning not practical
# hadolint ignore=SC2086,DL3008
RUN set -eux; \
    chown app:app /app; \
    if [ -n "$RUNTIME_PACKAGES" ]; then \
      apt-get update; \
      apt-get install -y --no-install-recommends $RUNTIME_PACKAGES; \
      apt-get clean; \
      rm -rf /var/lib/apt/lists/*; \
    fi; \
    rm -rf /tmp/* /var/tmp/*

FROM base AS basedev

ARG DEV_PACKAGES

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

WORKDIR /

ENV BUNDLE_AUTO_INSTALL=false \
    BUNDLE_CLEAN=true

RUN mkdir -p "$BUNDLE_PATH" && \
    chown -R app:app "$BUNDLE_PATH"

USER app

# https://code.visualstudio.com/remote/advancedcontainers/avoid-extension-reinstalls
RUN mkdir -p "$HOME/.vscode-server/"

FROM basedev AS baseliveci

COPY --chown=app:app Gemfile /app/

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

FROM live_builder AS distroless_builder

COPY --chown=app:app bin/ /app/bin/
COPY --chown=app:app lib/ /app/lib/

RUN set -eux; \
    chown -R 65532:65532 /bundle /app

FROM ghcr.io/zewelor/ruby:4.0.9-trixie-distroless@sha256:1767a3e824fda3115a904e5d7644a192709371d33ef1ce2320c90fe7c1b41e54 AS distroless

ENV BUNDLE_PATH=/bundle \
  BUNDLE_VERSION=system \
  GEM_HOME=/bundle \
  BUNDLE_DEPLOYMENT="1" \
  BUNDLE_WITHOUT="development:test" \
  RUBYOPT='--disable-did_you_mean'

WORKDIR /app

COPY --from=distroless_builder /bundle/ /bundle/
COPY --from=distroless_builder /app/ /app/

USER nonroot

CMD ["ruby", "bin/cli"]

FROM base AS live

# We enable `BUNDLE_DEPLOYMENT` so that bundler won't take the liberty to upgrade any gems.
ENV BUNDLE_DEPLOYMENT="1" \
  BUNDLE_WITHOUT="development:test" \
  RUBYOPT='--disable-did_you_mean'

COPY --chown=app:app --from=live_builder $BUNDLE_PATH $BUNDLE_PATH
COPY --chown=app:app --from=live_builder /app/Gemfile.lock /app/Gemfile.lock
COPY --chown=app:app Gemfile /app/
COPY --chown=app:app bin/ /app/bin/
COPY --chown=app:app lib/ /app/lib/

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

CMD ["ruby", "bin/cli"]
