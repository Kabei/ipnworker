## IPNWORKER
IPPAN blockchain transaction pre-verification node.

## Requirements
* Processor: 4 CPUs
* Memory: 4 GB RAM
* Storage: 50 GB SSD NVME
* Bandwitch: 1 Gbps
* Public IPv4 / IPv6

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
NAME=worker1
VID=<number>
SECRET_KEY=<same-secret-key-from-ipncore>
CLUSTER_KEY=<same-cluster-key-from-ipncore>
MINER=<name@hostname>
PGHOST=<hostname>
PGDATABASE=<database>
PGUSER=<username>
PGPASSWORD=<secret>
DATA_DIR=/usr/src/data
NODES=<name@hostname>" > env_file
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
config :ipnworker, :call, true
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
cp scripts/run.sh ./run.sh
chmod +x run.sh
./run.sh
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
