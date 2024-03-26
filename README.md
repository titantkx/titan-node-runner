# This repo contains script and docker file that support quickly startup Titan node belong with cosmovisor

## Run with docker compose

Adjust `docker-compose.yml` file to chose type of node you want to run. Then run the following command to start the node. All data of node will be stored at `./data` folder.

```bash
docker-compose up -d
```

## Run with docker only

Same as `docker compose` all data of node will be store at `./data` folder depend on your mount option in command.

```bash
docker run --rm -it -v ./data:/root/data titantkx/titan-node-runner:1.0.0 --chain-type mainnet --node-type sentry --sync-type full --moniker test-node --ext-addr "0.0.0.0:26656" --log warn
```

## Run without docker (direct on machine)

This command will run titan node directly on your machine. All node data will be store at your home folder: `$HOME/.titand`

```bash
./titan-node-runner.sh --moniker test-2 --ext-addr "0.0.0.0:26656" --chain-type testnet --node-type validator --sync-type full --log info
```

## Script options

- `--help`: Show help message
- `--chain-type`: Chain type of node, support `mainnet`, `testnet`
- `--node-type`: Node type of node, support `validator`, `sentry`, `full`, `seed`
- `--sync-type`: Sync type of node, support `full`, `fast`
- `--moniker`: Moniker of node
- `--ext-addr`: External address of node
- `--log`: Log level of node, support `info`, `warn`, `error`, `debug`
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
./titan-node-runner.sh --moniker test-2 --ext-addr 0.0.0.0:26656 --chain-type testnet --node-type validator --sync-type full --log info --init-only
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
