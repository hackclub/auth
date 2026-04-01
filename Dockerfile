# syntax=docker/dockerfile:1.4
# check=error=true;skip=SecretsUsedInArgOrEnv

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t identity_vault .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name identity_vault identity_vault

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.4
FROM docker.io/library/ruby:3.4.4-slim@sha256:4020c2d289c1266fe4a2ea1d0018c22c17435905c514c66f8437555da57723ad AS base

# Rails app lives here
WORKDIR /rails

# Install base packages with runtime libraries for libheif
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips imagemagick postgresql-client libffi-dev \
    libjpeg62-turbo libaom3 libx265-199 libde265-0 libpng16-16 wget libxmlsec1 libxmlsec1-openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG NODE_VERSION=23.6.0
ARG YARN_VERSION=1.22.22
ENV PATH=/usr/local/node/bin:$PATH
ARG NODE_BUILD_VERSION=v5.4.3
RUN curl -sL "https://github.com/nodenv/node-build/archive/refs/tags/${NODE_BUILD_VERSION}.tar.gz" \
      -o /tmp/node-build.tar.gz && \
    echo "1ff1a2c1fb51b5456d4d9edfd6a6fa9cc83dbdf473e0a61d7816a0ed935af165  /tmp/node-build.tar.gz" | sha256sum -c - && \
    tar xz -C /tmp/ -f /tmp/node-build.tar.gz && \
    /tmp/node-build-*/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    rm -rf /tmp/node-build* && \
    corepack enable && corepack prepare yarn@1.22.22+sha256.c17d3797fb9a9115bf375e31bfd30058cac6bc9c3b8807a3d8cb2094794b51ca


ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_LIBRARY_PATH="/usr/local/lib" \
    RAILS_ENV="production"

# Throw-away build stage to reduce size of final image
FROM base AS build

ARG LIBHEIF_VERSION=1.21.2
ARG LIBHEIF_SHA256=79996de959d28ca82ef070c382304683f5cdaf04cbe2953a74587160a3710a36
# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips imagemagick postgresql-client libffi-dev build-essential git libpq-dev libyaml-dev pkg-config \
    cmake libjpeg-dev libpng-dev libaom-dev libx265-dev libde265-dev libxmlsec1-dev libxmlsec1 libxmlsec1-openssl && \
    cd /tmp && \
     curl -sL "https://github.com/strukturag/libheif/archive/refs/tags/v${LIBHEIF_VERSION}.tar.gz" -o /tmp/libheif.tar.gz && \
     echo "${LIBHEIF_SHA256} /tmp/libheif.tar.gz" | sha256sum -c - && \
    tar xz -C /tmp/ -f /tmp/libheif.tar.gz && \
    cd /tmp/libheif-${LIBHEIF_VERSION} && \
    mkdir build && cd build && \
    cmake --preset=release -DWITH_EXAMPLES=ON -DENABLE_PLUGIN_LOADING=NO .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd / && rm -rf /tmp/libheif && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules

# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails
# Copy libheif libraries and examples from build stage
COPY --from=build /usr/local/lib/libheif* /usr/local/lib/
COPY --from=build /usr/local/bin/heif-* /usr/local/bin/
COPY --from=build /usr/local/include/libheif /usr/local/include/libheif
RUN ldconfig

# Run and own only the runtime files as a non-root users for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
