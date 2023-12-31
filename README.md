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

## Installation 
### Generate env_file
```bash
echo "
NAME=miner
VID=<number>
SECRET_KEY=<same-secret-key-from-ipncore>
CLUSTER_KEY=<same-cluster-key-from-ipncore>
MINER=miner@192.168.0.1
PGHOST=localhost
PGDATABASE=ippan
PGUSER=kambei
PGPASSWORD=<secret>
DATA_DIR=/usr/src/data
NODES=miner@192.168.0.1" > env_file
```

### Download and execute script
```bash
curl https://github.com/kabei/releases/download/0.5/ipncore-install.sh \
&& chmod +x ipncore-install.sh \
&& ./ipncore-install.sh
```

```bash
cd ipnworker

echo "
import Config

# History enable. (default: false)
config :ipnworker, :history, true
# Cluster API enable (Admin remote control)
config :ipnworker, :remote, false
# Call API enable (default: true)
config :ipnworker, :call, true
" > config/options.exs
```

### History mode
Allows write history of transactions in database remote
```Elixir
config :ipnworker, :history, true
```
## Run

```bash
./run.sh
```
## Docker
See docker/README.md

## Settings
|||
|-|-|
|Blockchain|IPPAN|
|Block Time|5 seconds|
|Native Token|IPN|
|Block file Max size|10 MB|
|Transaction Max size|8192 bytes|
|Tx note Max size|255 bytes|
|Refund transaction timeout|72 hours|
|Max tranfer amount|Thousand billion units|
|P2P port|5815|
|Cluster port|4848|
|HTTP port|8080|
