#!/bin/sh

set -e

# Detect platform
platform_os=$(uname -s)
platform_arch=$(uname -m)
# mapping platform_arch to amd64 and arm64
if [ "$platform_arch" = "aarch64" ]; then
  platform_arch="arm64"
fi
if [ "$platform_arch" = "x86_64" ]; then
  platform_arch="amd64"
fi
echo "Platform: $platform_os - $platform_arch"

# Only allow `platform_os` is `Linux` or `Darwin`. `platform_arch` is `amd64` or `arm64`
if [ "$platform_os" != "Linux" ] && [ "$platform_os" != "Darwin" ]; then
  echo "Error: Unsupported platform_os: $platform_os"
  exit 1
fi
if [ "$platform_arch" != "amd64" ] && [ "$platform_arch" != "arm64" ]; then
  echo "Error: Unsupported platform_arch: $platform_arch"
  exit 1
fi

# get dir of script
SCRIPT_DIR=$(dirname $0)
CURRENT_DIR=$(pwd)

# check if have `sudo`
have_sudo="true"
if ! [ -x "$(command -v sudo)" ]; then  
  have_sudo="false"  
fi

################################################################
#                 Init cross platfrom functions                #
################################################################

if [ "$platform_os" = "Darwin" ]; then
    sed_inplace="sed -i ''"
else
    sed_inplace="sed -i"
fi

################################################################
#                 Ensure required programs exist               #
################################################################

# check if `jq` exists
if ! [ -x "$(command -v jq)" ]; then
  echo "Error: jq is not installed."
  exit 1
fi

# check if `curl` exists
if ! [ -x "$(command -v curl)" ]; then
  echo "Error: curl is not installed."
  exit 1
fi

# check if `go` exists
if ! [ -x "$(command -v go)" ]; then
  echo "Error: go is not installed."
  exit 1
fi

# check if `cosmovisor` exists
if ! [ -x "$(command -v cosmovisor)" ]; then
  echo "Error: cosmovisor is not installed."
  go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0
fi

# check if `sha256sum` exists
if ! [ -x "$(command -v sha256sum)" ]; then
  echo "Error: sha256sum is not installed. Please install coreutils"
  exit 1
fi

# check if `gzip` exists
if ! [ -x "$(command -v gzip)" ]; then
  echo "Error: gzip is not installed."
  exit 1
fi

# check if `tar` exists
if ! [ -x "$(command -v tar)" ]; then
  echo "Error: tar is not installed."
  exit 1
fi

################################################################
#                 Init environment and params                  #
################################################################

if [ -z "$HOME" ]; then
  HOME="/root"
fi
if [ -z "$HOME_DATA" ]; then
  HOME_DATA="$HOME"
fi
if [ -z "$TITAN_HOME" ]; then
  TITAN_HOME="$HOME_DATA/.titand"
fi

echo "HOME: $HOME"
echo "HOME_DATA: $HOME_DATA"
echo "TITAN_HOME: $TITAN_HOME"

export DAEMON_NAME=titand
echo "DAEMON_NAME: $DAEMON_NAME"
export DAEMON_HOME=$TITAN_HOME
echo "DAEMON_HOME: $DAEMON_HOME"
if [ -z "$DAEMON_RESTART_AFTER_UPGRADE" ]; then
  export DAEMON_RESTART_AFTER_UPGRADE=true
fi
echo "DAEMON_RESTART_AFTER_UPGRADE: $DAEMON_RESTART_AFTER_UPGRADE"
export DAEMON_ALLOW_DOWNLOAD_BINARIES=true
echo "DAEMON_ALLOW_DOWNLOAD_BINARIES: $DAEMON_ALLOW_DOWNLOAD_BINARIES"

force_init="false"

# print help function
print_help() {
  echo "Usage: titan-node-runner.sh [OPTIONS]"
  echo "Version: 1.1.0"
  echo "Options:"
  echo "  --chain-type <mainnet|testnet>  Chain type of titan network"
  echo "  --node-type <full|sentry|validator|seed>  Node type of titan network"
  echo "  --sync-type <fast|full>  Sync type of titan network"
  echo "  --force-init  Force init node"
  echo "  --init-only  Only init node"
  echo "  --moniker <string>  Moniker of node"
  echo "  --ext-addr <string>  External address of node. Example: 159.89.10.97:26656"
  echo "  --add-seeds <string>  Additional seeds of node. EX: 80fbc7606d7d8799825b7b44a0b4d53342d92211@ec2-val-1.ap-southeast-1.titan-testnet.internal:26656"
  echo "  --log <info|debug|error|warn>  Log level of node"
  echo "  --help  Print help"
  echo "  -- Pass all following arguments to cosmovisor"
  exit 1
}

# parse from params
params_for_cosmovisor=""
contain_params_for_cosmovisor=false
while [ "$#" -gt 0 ]; do
    if $contain_params_for_cosmovisor; then
        params_for_cosmovisor="$params_for_cosmovisor $1"
    else
        case $1 in
            --help )          print_help
                              exit 0
                              ;;
            --chain-type )    shift
                              TITAN_CHAIN_TYPE=$1
                              ;;
            --node-type )     shift
                              TITAN_NODE_TYPE=$1
                              ;;
            --sync-type )     shift
                              TITAN_SYNC_TYPE=$1
                              ;;
            --force-init )    force_init="true"
                              ;;
            --init-only )     init_only="true"
                              ;;
            --moniker )       shift
                              TITAN_NODE_MONIKER=$1
                              ;;
            --ext-addr )      shift
                              TITAN_EXTERNAL_ADDRESS=$1
                              ;;
            --add-seeds )     shift
                              additional_seeds=$1
                              ;;
            --log )           shift
                              TITAN_LOG=$1
                              ;;
            -- )              contain_params_for_cosmovisor=true
                              ;;
            * )               echo "Unknown parameter $1"
                              exit 1
        esac
    fi
    shift
done

# check TITAN_NODE_MONIKER env must be not empty
if [ -z "$TITAN_NODE_MONIKER" ]; then
  echo "moniker must be not empty"
  print_help
  exit 1
fi

# check TITAN_EXTERNAL_ADDRESS env must be not empty
if [ -z "$TITAN_EXTERNAL_ADDRESS" ]; then
  echo "ext-addr must be not empty"
  print_help
  exit 1
fi

# check TITAN_CHAIN_TYPE env must be one in [mainnet, testnet]
if [ "$TITAN_CHAIN_TYPE" != "mainnet" ] && [ "$TITAN_CHAIN_TYPE" != "testnet" ]; then
  echo "TITAN_CHAIN_TYPE must be one in [mainnet, testnet]"
  print_help
  exit 1
fi

# check TITAN_NODE_TYPE env must be one in [full, sentry, validator, seed]
if [ "$TITAN_NODE_TYPE" != "full" ] && [ "$TITAN_NODE_TYPE" != "sentry" ] && [ "$TITAN_NODE_TYPE" != "validator" ] && [ "$TITAN_NODE_TYPE" != "seed" ]; then
  echo "TITAN_NODE_TYPE must be one in [full, sentry, validator, seed]"
  print_help
  exit 1
fi

# check TITAN_SYNC_TYPE env must be one in [fast, full]
if [ "$TITAN_SYNC_TYPE" != "fast" ] && [ "$TITAN_SYNC_TYPE" != "full" ]; then
  echo "TITAN_SYNC_TYPE must be one in [fast, full]"
  print_help
  exit 1
fi

# check force_init env must be one in [true, false] if it is not empty
if [ "$force_init" != "true" ] && [ "$force_init" != "false" ]; then
  echo "force_init must be one in [true, false]"
  print_help
  exit 1
fi

#check log env must be one in [info, debug, error, warn]
if [ "$TITAN_LOG" != "info" ] && [ "$TITAN_LOG" != "debug" ] && [ "$TITAN_LOG" != "error" ] && [ "$TITAN_LOG" != "warn" ]; then
  echo "log must be one in [info, debug, error, warn]"
  print_help
  exit 1
fi

# if TITAN_NODE_TYPE is full, TITAN_SYNC_TYPE must be full
if [ "$TITAN_NODE_TYPE" = "full" ] && [ "$TITAN_SYNC_TYPE" != "full" ]; then
  echo "if TITAN_NODE_TYPE is full, TITAN_SYNC_TYPE must be full"
  print_help
  exit 1
fi


# if $TITAN_HOME/data already contains *.db => node is already initialized
skip_init_node="false"
if [ -d $TITAN_HOME/data/application.db ] && [ -d $TITAN_HOME/data/state.db ] && [ -d $TITAN_HOME/data/blockstore.db ]; then

  if [ "$force_init" = "true" ]; then
    skip_init_node="false"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!!!! NOTE: Node is already initialized with data. INITIALIZING NODE WILL BE FORCE.!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    
    # ask user to confirm
    echo "Do you want to continue? (y/N)"
    read confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
      echo "Exit"
      exit 0
    fi
  else
    skip_init_node="true"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!!!! NOTE: Node is already initialized with data. Chain type, node type and sync type will be ignored. Initializing node will be skip.!!!!!!!!!!!!"  
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  fi

fi

if [ "$TITAN_CHAIN_TYPE" = "mainnet" ]; then
  chain_id="titan_18888-1"
  genesis_url="https://github.com/titantkx/titan-mainnet/raw/main/public/genesis.json.gz"
  if [ -z "$TITAN_SEEDS" ]; then
    TITAN_SEEDS="bee5ef5680cf90fe40d6cde872cdc52e53c8338d@titan-p2p-seed-1.titanlab.io:26656,cf2f46da018e9b61c2db74012bd930d292478bb6@titan-p2p-1.titanlab.io:26656,0538c914eccc67a335eb64d99406c71ba7b110ca@titan-p2p-2.titanlab.io:26656"
  fi
  if [ -z "$TITAN_RPC_ENDPOINT" ]; then
    TITAN_RPC_ENDPOINT="https://titan-rpc.titanlab.io:443"
  fi
  if [ -z "$TITAN_RPC_STATE_SYNC_ENDPOINT" ]; then
    TITAN_RPC_STATE_SYNC_ENDPOINT="https://titan-rpc-1.titanlab.io:443,https://titan-rpc-2.titanlab.io:443,https://titan-rpc-seed-1.titanlab.io:443,https://titan-rpc-full-1.titanlab.io:443"
  fi
elif [ "$TITAN_CHAIN_TYPE" = "testnet" ]; then
  chain_id="titan_18889-1"
  genesis_url="https://github.com/titantkx/titan-testnets/raw/main/public/genesis.json.gz"
  if [ -z "$TITAN_SEEDS" ]; then
    TITAN_SEEDS="acb90d29636059abd5c4ca36f3731a69de73cf5b@titan-testnet-seed-1.titanlab.io:26656,1f61a190809e4413079174b6236bc00a502722b6@titan-testnet-node-1.titanlab.io:26656,c580270d0741f08d8ed88eda5d7de272622e7c02@titan-testnet-node-2.titanlab.io:26656"
  fi
  if [ -z "$TITAN_RPC_ENDPOINT" ]; then
    TITAN_RPC_ENDPOINT="https://titan-testnet-rpc.titanlab.io:443"
  fi
  if [ -z "$TITAN_RPC_STATE_SYNC_ENDPOINT" ]; then
    TITAN_RPC_STATE_SYNC_ENDPOINT="https://titan-testnet-rpc-1.titanlab.io:443,https://titan-testnet-rpc-2.titanlab.io:443,https://titan-testnet-rpc-3.titanlab.io:443,https://titan-testnet-rpc-4.titanlab.io:443"
  fi
fi

if [ ! -z "$additional_seeds" ]; then
  TITAN_SEEDS="$TITAN_SEEDS,$additional_seeds"
fi

config_updatable() {
  echo "Config updatable"
  echo "TITAN_NODE_MONIKER: $TITAN_NODE_MONIKER"
  echo "TITAN_EXTERNAL_ADDRESS: $TITAN_EXTERNAL_ADDRESS"
  echo "TITAN_SEEDS: $TITAN_SEEDS"
  echo "TITAN_LOG: $TITAN_LOG"

  # config moniker in config.toml
  $sed_inplace "s/\(moniker = \).*/\1\"$TITAN_NODE_MONIKER\"/" $TITAN_HOME/config/config.toml
  # config TITAN_EXTERNAL_ADDRESS in config.toml
  $sed_inplace "s/\(TITAN_EXTERNAL_ADDRESS = \).*/\1\"$TITAN_EXTERNAL_ADDRESS\"/" $TITAN_HOME/config/config.toml
  # config log
  $sed_inplace "s/\(log_level = \).*/\1\"$TITAN_LOG\"/" $TITAN_HOME/config/config.toml
  # config seeds
  $sed_inplace "s/\(seeds = \).*/\1\"$TITAN_SEEDS\"/" $TITAN_HOME/config/config.toml
}

if [ "$skip_init_node" = "true" ]; then
################################################################
#                 Start titand node                            #
################################################################

  config_updatable
      
  # get current version of titand  
  titand_current_version=$(cosmovisor run version 2>&1) || {    
    echo "titand version command failed: $titand_current_version"
    # if `titand_current_version` contain `error while loading shared libraries` or `Library not loaded`
    if echo $titand_current_version | grep -q "error while loading shared libraries" || echo $titand_current_version | grep -q "Library not loaded"; then    
      echo " "
      echo "Fix share lib for version 2.0.0 or smaller. Copy share lib to /usr/lib/ or /usr/local/lib/"
      if [ "$platform_os" = "Darwin" ]; then
        if [ "$have_sudo" = "true" ]; then
          sudo cp $TITAN_HOME/cosmovisor/current/lib/* /usr/local/lib/
        else
          cp $TITAN_HOME/cosmovisor/current/lib/* /usr/local/lib/
        fi
      else
        if [ "$have_sudo" = "true" ]; then
          sudo cp $TITAN_HOME/cosmovisor/current/lib/* /usr/lib/
        else
          cp $TITAN_HOME/cosmovisor/current/lib/* /usr/lib/
        fi
      fi
    fi    
  }

  titand_current_version=$(cosmovisor run version | sed -n '2p')
  echo "Current version of titand: $titand_current_version"  

  # if params_for_titand is not empty, run cosmovisor with params
  if [ "$contain_params_for_cosmovisor" = "true" ]; then
    # if params_for_cosmovisor contain `run`, append `--home $TITAN_HOME`
    if echo $params_for_cosmovisor | grep -q "run"; then
      params_for_cosmovisor="$params_for_cosmovisor --home $TITAN_HOME"    
    fi    
    echo " "
    cosmovisor $params_for_cosmovisor
    exit 0
  elif [ "$init_only" = "true" ]; then
    exit 0
  else
    # start 
    echo " "
    cosmovisor run start --x-crisis-skip-assert-invariants --home $TITAN_HOME
    exit 0
  fi
fi

####################################################################################
#                 Init node with chain type, node type, sync type                  #
####################################################################################

# backup $TITAN_HOME/config and $TITAN_HOME/data/priv_validator_state.json if exists
backed_up="false"
current_time=$(date "+%Y.%m.%d-%H.%M.%S")
if [ -d $TITAN_HOME/config ]; then
  mkdir -p $HOME_DATA/bak_$current_time
  cp -R $TITAN_HOME/config $HOME_DATA/bak_$current_time/config
  backed_up="true"
fi
if [ -f $TITAN_HOME/data/priv_validator_state.json ]; then
  mkdir -p $HOME_DATA/bak_$current_time
  cp $TITAN_HOME/data/priv_validator_state.json $HOME_DATA/bak_$current_time/priv_validator_state.json
fi

# clean up old data
rm -rf $TITAN_HOME
rm -rf $HOME_DATA/titan

################################################################
#                 Download start titand bin                    #
################################################################

if [ "$TITAN_SYNC_TYPE" = "full" ]; then
  if [ "$TITAN_CHAIN_TYPE" = "mainnet" ]; then
    titand_start_version="2.0.1"
  elif [ "$TITAN_CHAIN_TYPE" = "testnet" ]; then
    titand_start_version="1.0.0"
  fi
elif [ "$TITAN_SYNC_TYPE" = "fast" ]; then
  # get current version of rpc node from $TITAN_RPC_ENDPOINT/abci_info
  current_abci_info=$(curl -s $TITAN_RPC_ENDPOINT/abci_info)
  # get current version of rpc node
  titand_start_version=$(echo $current_abci_info | jq -r '.result.response.version')
  last_block_height=$(echo $current_abci_info | jq -r '.result.response.last_block_height')
fi

echo "Current version of titand: $titand_start_version"
echo "Last block height: $last_block_height"

# download checksums.txt
echo "Download checksums.txt"
curl -L "https://github.com/titantkx/titan/releases/download/v${titand_start_version}/checksums.txt" -o $HOME_DATA/checksums.txt

# download titand bin from `https://github.com/titantkx/titan/releases/download/v<version>/titan_<version>_<os>_<arch>.tar.gz`
echo "Download titand archive"
curl -L "https://github.com/titantkx/titan/releases/download/v${titand_start_version}/titan_${titand_start_version}_${platform_os}_${platform_arch}.tar.gz" -o $HOME_DATA/"titan_${titand_start_version}_${platform_os}_${platform_arch}.tar.gz"

# verify checksums
cd $HOME_DATA
# Extract the line for the specific file from checksums.txt
checksum_line=$(grep "titan_${titand_start_version}_${platform_os}_${platform_arch}.tar.gz" checksums.txt)
echo "Checksum info: $checksum_line"
echo $checksum_line | sha256sum --strict -wc -
echo "Download titand archive successfully"
cd $CURRENT_DIR

echo "Extract titand archive"

mkdir -p $HOME_DATA/titan
tar -xzf "$HOME_DATA/titan_${titand_start_version}_${platform_os}_${platform_arch}.tar.gz" -C $HOME_DATA/titan

# get current version of titand
titand_current_version=$($HOME_DATA/titan/bin/titand version 2>&1) || {  
  echo "titand version command failed: $titand_current_version"
  # if `titand_current_version` contain `error while loading shared libraries`
  if echo $titand_current_version | grep -q "error while loading shared libraries" || echo $titand_current_version | grep -q "Library not loaded"; then    
    echo " "
    echo "Fix share lib for version 2.0.0 or smaller. Copy share lib to /usr/lib/ or /usr/local/lib/"
    if [ "$platform_os" = "Darwin" ]; then
      if [ "$have_sudo" = "true" ]; then
        sudo cp $HOME_DATA/titan/lib/* /usr/local/lib/
      else
        cp $HOME_DATA/titan/lib/* /usr/local/lib/
      fi
    else
      if [ "$have_sudo" = "true" ]; then
        sudo cp $HOME_DATA/titan/lib/* /usr/lib/
      else
        cp $HOME_DATA/titan/lib/* /usr/lib/
      fi
    fi
  fi
}

titand_current_version=$($HOME_DATA/titan/bin/titand version)

echo "Current version of titand: $titand_current_version"  

################################################################
#                             Init node                        #
################################################################

# init node
echo "Init node"
$HOME_DATA/titan/bin/titand init $TITAN_NODE_MONIKER --chain-id $chain_id --home $TITAN_HOME
echo " "

# copy genesis.json
curl -L $genesis_url -o $TITAN_HOME/config/genesis.json.gz
echo "Extract genesis.json"
gzip -fd $TITAN_HOME/config/genesis.json.gz

# copy coresponse config_tmp
cp $SCRIPT_DIR/configs_tmp/$TITAN_NODE_TYPE/app.toml $TITAN_HOME/config/app.toml
cp $SCRIPT_DIR/configs_tmp/$TITAN_NODE_TYPE/config.toml $TITAN_HOME/config/config.toml

# adjust app.toml and config.toml
echo "Adjust app.toml and config.toml"
$sed_inplace 's/\(global-labels = \).*/\1[[\"chain_id\", \"titan_18888-1\"]]/' $TITAN_HOME/config/app.toml

config_updatable

# config state sync
if [ "$TITAN_SYNC_TYPE" = "fast" ]; then  
  echo "Config state sync"

  echo "TITAN_RPC_STATE_SYNC_ENDPOINT: $TITAN_RPC_STATE_SYNC_ENDPOINT"

  $sed_inplace "/^\[statesync\]$/,/^\[/ s/\(enable = \).*/\1true/" $TITAN_HOME/config/config.toml
  TITAN_RPC_STATE_SYNC_ENDPOINT_REGEX=$(echo $TITAN_RPC_STATE_SYNC_ENDPOINT | sed 's/\//\\\//g')
  $sed_inplace "/^\[statesync\]$/,/^\[/ s/\(rpc_servers = \).*/\1\"$TITAN_RPC_STATE_SYNC_ENDPOINT_REGEX\"/" $TITAN_HOME/config/config.toml

  fast_sync_block_height=$((($last_block_height / 1000) * 1000))

  # get hash of block at fast_sync_block_height
  fast_sync_block_hash=$(curl -s $TITAN_RPC_ENDPOINT/block?height=$fast_sync_block_height | jq -r '.result.block_id.hash')
  if [ -z "$fast_sync_block_hash" ]; then
    echo "Cannot get block hash at height $fast_sync_block_height"
    exit 1
  fi

  echo "Fast sync block height: $fast_sync_block_height - hash: $fast_sync_block_hash"
  $sed_inplace "/^\[statesync\]$/,/^\[/ s/\(trust_height = \).*/\1$fast_sync_block_height/" $TITAN_HOME/config/config.toml
  $sed_inplace "/^\[statesync\]$/,/^\[/ s/\(trust_hash = \).*/\1\"$fast_sync_block_hash\"/" $TITAN_HOME/config/config.toml

  # disable evm index 
  $sed_inplace "/^\[json-rpc\]$/,/^\[/ s/\(enable-indexer = \).*/\1false/" $TITAN_HOME/config/app.toml
  # disable rossetta
  $sed_inplace "/^\[rosetta\]$/,/^\[/ s/\(enable = \).*/\1false/" $TITAN_HOME/config/app.toml
fi

if [ "$backed_up" = "true" ]; then
  echo "Recover node key"
  cp $HOME_DATA/bak_$current_time/config/node_key.json $TITAN_HOME/config/node_key.json
  cp $HOME_DATA/bak_$current_time/config/priv_validator_key.json $TITAN_HOME/config/priv_validator_key.json
  cp $HOME_DATA/bak_$current_time/priv_validator_state.json $TITAN_HOME/data/priv_validator_state.json
  echo " "  
fi

# Create cosmovisor folder
echo "Create cosmovisor folder"
mkdir -p $TITAN_HOME/cosmovisor
mkdir -p $TITAN_HOME/cosmovisor/genesis
mkdir -p $TITAN_HOME/cosmovisor/upgrades

# Copy titand binary to cosmovisor folder
echo "Copy titand binary to cosmovisor folder"
cp -R $HOME_DATA/titan/* $TITAN_HOME/cosmovisor/genesis/

cosmovisor init $TITAN_HOME/cosmovisor/genesis/bin/titand

# if contain_params_for_cosmovisor is not empty, run cosmovisor with params
if [ "$contain_params_for_cosmovisor" = "true" ]; then
  # if params_for_cosmovisor contain `run`, append `--home $TITAN_HOME`
  if echo $params_for_cosmovisor | grep -q "run"; then
    params_for_cosmovisor="$params_for_cosmovisor --home $TITAN_HOME"  
  fi    
  echo " "
  cosmovisor $params_for_cosmovisor
  exit 0
elif [ "$init_only" = "true" ]; then
  exit 0
else
  # start 
  echo " "
  cosmovisor run start --x-crisis-skip-assert-invariants --home $TITAN_HOME
  exit 0
fi