## IPNWORKER
IPPAN blockchain transaction pre-verification node.

## Requirements
* Processor: 4 CPUs
* Memory: 4 GB RAM
* Storage: 50 GB SSD NVME
* Bandwitch: 1 Gbps
* Public IPv4 or web domain

## Dependencies
* Erlang 25
* Elixir 1.14
* cargo 1.70
* cmake 3.26
* git 2.41.0
* postgresql 15

## Installation 
### Generate env_file
```bash
echo "
name: workername
vid: V-0
secret_key: secret_in_base64
cluster_key: secret_in_base64
miner: miner
pgHost: localhost
pgDatabase: database
pgUser: user
pgPassword: secret
data_dir: /usr/src/data" > env_file
```

### Download and execute script
```bash
curl https://github.com/kabei/releases/download/0.5/ipnworker-install.sh \
&& chmod +x ipnworker-install.sh \
&& ./ipnworker-install.sh
```

```bash
cd ipnworker

echo "
import Config

# History mode (default: false)
config :ipnworker, :history, true
# Query API (default: true)
config :ipnworker, :api, true
# API Call (default: true)
config :ipnworker, :call, true
# Notify each tx (default: false)
config :ipnworker, :notify, true
" > config/options.exs
```

### History mode
Allows write history of transactions in database remote
```Elixir
# change in config/options.exs
config :ipnworker, :history, true
```
## Run

```bash
chmod +x scripts/run.sh
./scripts/run.sh
```
## Docker
See docker/README.md

## Config
|Name|Default|
|-|-|
|Blockchain|IPPAN|
|Native Token|IPN|
|Block file Max size|10 MB|
|Transaction Max size|8192 bytes|
|Tx note Max size|255 bytes|
|Refund transaction timeout|72 hours|
|Max tranfer amount|Thousand billion units|
|P2P port|5815|
|Cluster port|4848|
|HTTP port|8080|
