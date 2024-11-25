# This repo contains script and docker file that support quickly startup Titan node belong with cosmovisor

## Requirement

Some programs is recommended to install in machine before using this script

- fish
- htop
- git
- jq
- go
- curl
- coreutil
- gzip
- tar

```bash
sudo apt update -y && \
sudo apt install -y fish htop git jq curl coreutils tar
```

```bash
curl -OL https://go.dev/dl/go1.21.0.linux-amd64.tar.gz && \
sudo tar -xvf go1.21.0.linux-amd64.tar.gz -C /usr/local
```

```bash
export PATH=$PATH:/usr/local/go/bin && \
export PATH=$PATH:$(go env GOPATH)/bin && \
echo "export PATH=\$PATH:/usr/local/go/bin:$(go env GOPATH)/bin" >> $HOME/.profile && \
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0
```

## Run with docker compose

Adjust `docker-compose.yml` file to chose type of node you want to run. Then run the following command to start the node. All data of node will be stored at `./data` folder.

```bash
docker-compose up -d
```

## Run with docker only

Same as `docker compose` all data of node will be store at `./data` folder depend on your mount option in command.

```bash
docker run --rm -it -v ./data:/root/data titantkx/titan-node-runner:1.3.5 --chain-type mainnet --node-type sentry --sync-type full --moniker test-node --ext-addr "0.0.0.0:26656" --log warn
```

## Run without docker (direct on machine)

This command will run titan node directly on your machine. All node data will be store at your home folder: `$HOME/.titand`

```bash
./titan-node-runner.sh --moniker test-2 --ext-addr "0.0.0.0:26656" --chain-type testnet --node-type validator --sync-type full --log info
```

## Script options

- `--help`: Show help message
- `--chain-type <>`: Chain type of node, support `mainnet`, `testnet`
- `--node-type <>`: Node type of node, support `validator`, `sentry`, `full`, `seed`
- `--sync-type <>`: Sync type of node, support `full`, `fast`
- `--moniker <>`: Moniker of node
- `--ext-addr <>`: External address of node
- `--add-seeds <>`: Add more seeds to node config. E.g.: <80fbc7606d7d8799825b7b44a0b4d53342d92211@ec2-val-1.ap-southeast-1.titan-testnet.internal>:26656
- `--log <>`: Log level of node, support `info`, `warn`, `error`, `debug`
- `--shell <>`: Run in shell mode, support `fish`, `bash`, `sh`
- `--force-init`: (WARNING) Force to init node data. This will clear all current data of node and init new one (it will try backup and restore node_key).
- `--init-only`: Only init node data, do not run node

### Run directly cosmovisor command

Any parameter after `--` will be passed to cosmovisor command. For example:

```bash
./titan-node-runner.sh --moniker test-2 --ext-addr "0.0.0.0:26656" --chain-type testnet --node-type validator --sync-type full --log info -- version
```

### Use to init only

You can use script to init node config only by using `--init-only` option. This will init node config and exit.

```bash
./titan-node-runner.sh \
    --moniker test-2 \
    --ext-addr 0.0.0.0:26656 \
    --chain-type testnet \
    --node-type validator \
    --sync-type full \
    --log info --init-only
```

Command will also output value of Environment variable that you can use to start node by using `cosmovisor` command directly.

```bash
TITAN_HOME: /Users/mac/.titand
DAEMON_NAME: titand
DAEMON_HOME: /Users/mac/.titand
DAEMON_RESTART_AFTER_UPGRADE: true
DAEMON_ALLOW_DOWNLOAD_BINARIES: true
```

After init, config above env and start node by using `cosmovisor` command directly:

```bash
cosmovisor run start --x-crisis-skip-assert-invariants --home $TITAN_HOME
```
