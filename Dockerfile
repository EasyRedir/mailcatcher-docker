# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3
FROM public.ecr.aws/docker/library/ruby:$RUBY_VERSION-slim AS base

# Install a newer version of RubyGems
ARG RUBYGEMS_VERSION=3.5.14
RUN <<EOF
  gem update --system $RUBYGEMS_VERSION
EOF

# Install packages needed for all stages
RUN <<EOF
  #!/usr/bin/env bash
  set -e
  apt-get update -qq
  apt-get install --no-install-recommends -y libjemalloc2
  rm -rf /var/lib/apt/lists /var/cache/apt/archives
EOF

# Set variables needed for all stages
ENV BUNDLE_PATH="/usr/local/bundle" \
	LANG="C.UTF-8" \
    LD_PRELOAD="libjemalloc.so.2" \
	HTTP_PORT=1080 \
    MALLOC_CONF="dirty_decay_ms:1000,narenas:2,background_thread:true" \
    SMTP_PORT=1025 \
	RUBY_YJIT_ENABLE="1"


# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gem
RUN <<EOF
  #!/usr/bin/env bash
  set -e
  apt-get update -qq
  apt-get install --no-install-recommends -y build-essential git libsqlite3-dev
EOF

# Install the mailcatcher gem
RUN <<EOF
  gem install mailcatcher --no-document
EOF


# Create an image the contains only the runtime dependencies
FROM base

# Copy the installed gem
COPY --from=build /usr/local/bundle /usr/local/bundle

# Run and own only the runtime files as a non-root user for security
RUN <<EOF
  useradd app --create-home --shell /bin/bash
EOF

USER app:app

# Start the server by default, this can be overwritten at runtime
EXPOSE ${SMTP_PORT} ${HTTP_PORT}
CMD mailcatcher --smtp-ip=0.0.0.0 --smtp-port=$SMTP_PORT --http-ip=0.0.0.0 --http-port=$HTTP_PORT -f
