ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.0.6
ARG DEBIAN_VERSION=trixie-20260918-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
    && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY apps/analysis/mix.exs apps/analysis/mix.exs
COPY apps/chess/mix.exs apps/chess/mix.exs
COPY apps/position_db/mix.exs apps/position_db/mix.exs
COPY apps/web/mix.exs apps/web/mix.exs

COPY config config

RUN mix deps.get --only prod
RUN mix deps.compile

COPY apps apps
COPY rel rel

RUN mix compile

RUN mix esbuild web --minify

RUN cd apps/web && mix phx.digest priv/static

RUN mix release openchesslab

FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    libncurses6 \
    locales \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

RUN chown nobody /app

ENV MIX_ENV=prod

COPY --from=builder --chown=nobody:root \
    /app/_build/prod/rel/openchesslab ./

USER nobody

CMD ["/app/bin/openchesslab", "start"]