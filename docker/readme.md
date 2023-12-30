### Build image
```bash
docker build -t ipnworker:0.5 .
```

### Run a container
```bash
docker run \
-p 4848:4848 -p 5815:5815 -p 8080:8080 --volume data:/var/data \
--restart=on-failure:5 -d --name worker ipnworker:0.5
```

### Arguments to docker run:
* Node name: `-e NAME=<string>`
* Validator ID: `-e VID=<number>`
* Secret key: `-e SECRET_KEY=<base64-string>`
* Cluster secret key: `-e CLUSTER_KEY=<base64-string>`
* Nodes: `-e NODES=miner-name@127.0.0.1`
* Miner name: `-e MINER=<miner-name>`
* PG config:
`-e PGHOST=localhost`
`-e PGDATABASE=ippan`
`-e PGUSER=kambei`
`-e PGPASSWORD=<secret>`
* Data folder path: `-e DATA_DIR=<path>` (optional)
* Print logger file: `-e LOG=<filepath>` (optional)

### Docker interactive mode
```bash
docker exec -it miner /bin/bash
```
