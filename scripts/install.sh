#!/usr/bin/bash

export MIX_ENV=prod
export PATH="/root/.cargo/bin:${PATH}"

apt update -y
apt install erlang elixir ca-certificates curl git cmake zip unzip -y
curl https://sh.rustup.rs -sSf | sh -s -- -y

git clone --branch dev https://kabei@github.com/kabei/ipnworker.git

cd ipnworker

mix local.hex --force
mix deps.get
mix local.rebar --force
mix compile

cp ../env_file ./

