#!/bin/bash

# load env variables
source .env

# load script
source script/config.sh

ZERO_ADDRESS=0x0000000000000000000000000000000000000000
RED='\033[0;31m'   # Red color
GREEN='\033[0;32m' # Green color
GRAY='\033[0;37m'  # Light gray color
BLUE='\033[1;34m'  # Light blue color

NC='\033[0m' # No color
function getChainId() {
  # read function arguments into variables
  NETWORK="$1"

  # return chainId
  case $NETWORK in
  "mainnet")
    echo "1"
    return 0
    ;;
  "blast")
    echo "81457"
    return 0
    ;;
  "bsc")
    echo "56"
    return 0
    ;;
  "polygon")
    echo "137"
    return 0
    ;;
  "polygonzkevm")
    echo "1101"
    return 0
    ;;
  "rootstock")
    echo "30"
    return 0
    ;;
  "gnosis")
    echo "100"
    return 0
    ;;
  "fraxtal")
    echo "252"
    return 0
    ;;
  "fantom")
    echo "250"
    return 0
    ;;
  "gravity")
    echo "1625"
    return 0
    ;;
  "okx")
    echo "66"
    return 0
    ;;
  "avalanche")
    echo "43114"
    return 0
    ;;
  "arbitrum")
    echo "42161"
    return 0
    ;;
  "optimism")
    echo "10"
    return 0
    ;;
  "moonriver")
    echo "1285"
    return 0
    ;;
  "moonbeam")
    echo "1284"
    return 0
    ;;
  "celo")
    echo "42220"
    return 0
    ;;
  "fuse")
    echo "122"
    return 0
    ;;
  "cronos")
    echo "25"
    return 0
    ;;
  "velas")
    echo "106"
    return 0
    ;;
  "harmony")
    echo "1666600000"
    return 0
    ;;
  "evmos")
    echo "9001"
    return 0
    ;;
  "aurora")
    echo "1313161554"
    return 0
    ;;
  "base")
    echo "8453"
    return 0
    ;;
  "boba")
    echo "288"
    return 0
    ;;
  "nova")
    echo "87"
    return 0
    ;;
  "mode")
    echo "34443"
    return 0
    ;;
  "scroll")
    echo "534352"
    return 0
    ;;
  "goerli")
    echo "5"
    return 0
    ;;
  "bsc-testnet")
    echo "97"
    return 0
    ;;
  "sepolia")
    echo "11155111"
    return 0
    ;;
  "mumbai")
    echo "80001"
    return 0
    ;;
  "lineatest")
    echo "59140"
    return 0
    ;;
  "linea")
    echo "59144"
    return 0
    ;;
  "opbnb")
    echo "204"
    return 0
    ;;
  "metis")
    echo "1088"
    return 0
    ;;
  "localanvil")
    echo "31337"
    return 0
    ;;
  "zksync")
    echo "324"
    return 0
    ;;
  "mantle")
    echo "5000"
    return 0
    ;;
  "sei")
    echo "1329"
    return 0
    ;;
  "immutablezkevm")
    echo "13371"
    return 0
    ;;
  "xlayer")
    echo "196"
    return 0
    ;;
  "taiko")
    echo "167000"
    return 0
    ;;
  "unichain")
    echo "130"
    return 0
    ;;
  "berachain")
    echo "80094"
    return 0
    ;;
  *)
    return 1
    ;;
  esac

}
function checkFailure() {
  # read function arguments into variables
  RESULT=$1
  ERROR_MESSAGE=$2

  # check RESULT code and display error message if code != 0
  if [[ $RESULT -ne 0 ]]; then
    echo "Failed to $ERROR_MESSAGE"
    exit 1
  fi
}
function echoDebug() {
  # read function arguments into variables
  local MESSAGE="$1"

  # write message to console if debug flag is set to true
  if [[ $DEBUG == "true" ]]; then
    printf "$BLUE[debug] %s$NC\n" "$MESSAGE"
  fi
}
function error() {
  printf '\033[31m[error] %s\033[0m\n' "$1"
}
function warning() {
  printf '\033[33m[warning] %s\033[0m\n' "$1"
}
function success() {
  printf '\033[0;32m[success] %s\033[0m\n' "$1"
}
function getFileSuffix() {
  # read function arguments into variables
  ENVIRONMENT="$1"

  # check if env variable "PRODUCTION" is true, otherwise deploy as staging
  if [[ "$ENVIRONMENT" == "production" ]]; then
    echo ""
  else
    echo "staging."
  fi
}
function getPrivateKey() {
  # read function arguments into variables
  NETWORK="$1"
  ENVIRONMENT="$2"

  # skip for local network
  if [[ "$NETWORK" == "localanvil" || "$NETWORK" == "LOCALANVIL" ]]; then
    echo "$PRIVATE_KEY_ANVIL"
    return 0
  fi

  # check environment value
  if [[ "$ENVIRONMENT" == *"staging"* ]]; then
    # check if env variable is set/available
    if [[ -z "$PRIVATE_KEY" ]]; then
      error "could not find PRIVATE_KEY value in your .env file"
      return 1
    else
      echo "$PRIVATE_KEY"
      return 0
    fi
  else
    # check if env variable is set/available
    if [[ -z "$PRIVATE_KEY_PRODUCTION" ]]; then
      error "could not find PRIVATE_KEY_PRODUCTION value in your .env file"
      return 1
    else
      echo "$PRIVATE_KEY_PRODUCTION"
      return 0
    fi
  fi
}
function getDeployerAddress() {
  # read function arguments into variables
  local NETWORK=$1
  local ENVIRONMENT=$2

  PRIV_KEY="$(getPrivateKey "$NETWORK" "$ENVIRONMENT")"

  # prepare web3 code to be executed
  jsCode="const { Web3 } = require('web3');
    const web3 = new Web3();
    const deployerAddress = (web3.eth.accounts.privateKeyToAccount('$PRIV_KEY')).address
    const checksumAddress = web3.utils.toChecksumAddress(deployerAddress);
    console.log(checksumAddress);"

  # execute code using web3
  DEPLOYER_ADDRESS=$(node -e "$jsCode")

  # return deployer address
  echo "$DEPLOYER_ADDRESS"
}
function checkIfFileExists() {
  # read function arguments into variables
  local FILE_PATH="$1"

  # Check if FILE exists
  if [ ! -f "$FILE_PATH" ]; then
    echo "false"
    return 1
  else
    echo "true"
    return 0
  fi
}
function getContractFilePath() {
  # read function arguments into variables
  CONTRACT="$1"
  # define directory to be searched
  local dir=$CONTRACT_DIRECTORY
  local FILENAME="$CONTRACT.sol"
  # find FILE path
  local file_path=$(find "${dir%/}" -name $FILENAME -print)

  # return FILE path or throw error if FILE path does not have a value
  if [ -n "$file_path" ]; then
    echo "$file_path"
  else
    error "could not find src FILE path for contract $CONTRACT"
    exit 1
  fi
}
function getRPCUrl() {
  # read function arguments into variables
  local NETWORK=$1

  # get RPC KEY
  RPC_KEY="ETH_NODE_URI_$(tr '[:lower:]' '[:upper:]' <<<"$NETWORK")"
  if [[ "$NETWORK" == "bsc-testnet" ]]; then
    RPC_KEY="ETH_NODE_URI_BSCTEST"
  fi
  # return RPC URL
  echo "${!RPC_KEY}"
}
function getDeployerBalance() {
  # read function arguments into variables
  local NETWORK=$1
  local ENVIRONMENT=$2

  # get RPC URL
  RPC_URL=$(getRPCUrl "$NETWORK")

  # get deployer address
  ADDRESS=$(getDeployerAddress "$NETWORK" "$ENVIRONMENT")

  # get balance in given network
  BALANCE=$(cast balance "$ADDRESS" --rpc-url "$RPC_URL")

  # return formatted balance
  echo "$(echo "scale=10;$BALANCE / 1000000000000000000" | bc)"
}
function checkRequiredVariablesInDotEnv() {
  # read function arguments into variables
  local NETWORK=$1

  # skip for local network
  if [[ "$NETWORK" == "localanvil" ]]; then
    return 0
  fi

  # skip for local network
  if [[ "$NETWORK" == "localanvil" ]]; then
    return 0
  fi

  local PRIVATE_KEY="$PRIVATE_KEY"
  local RPC_URL=$(getRPCUrl "$NETWORK")

  # special handling for BSC testnet
  # uses same block explorer key as bsc mainnet
  if [[ "$NETWORK" == "bsc-testnet" ]]; then
    NETWORK="bsc"
    RPC_URL="${!ETH_NODE_URI_BSCTEST}"
  fi

  local BLOCKEXPLORER_API="$(tr '[:lower:]' '[:upper:]' <<<"$NETWORK")""_ETHERSCAN_API_KEY"
  local BLOCKEXPLORER_API_KEY="${!BLOCKEXPLORER_API}"

  if [[ -z "$PRIVATE_KEY" || -z "$RPC_URL" || -z "$BLOCKEXPLORER_API_KEY" ]]; then
    # throw error if any of the essential keys is missing
    error "your .env file is missing essential entries for this network (required are: PRIVATE_KEY, $RPC and $BLOCKEXPLORER_API)"
    return 1
  fi

  # all good - continue
  return 0
}
function getContractAddressFromSalt() {
  # read function arguments into variables
  local SALT=$1
  local NETWORK=$2
  local CONTRACT_NAME=$3
  local ENVIRONMENT=$4

  # get RPC URL
  local RPC_URL="ETH_NODE_URI_$(tr '[:lower:]' '[:upper:]' <<<"$NETWORK")"
  if [[ "$NETWORK" == "bsc-testnet" ]]; then
    RPC_URL="ETH_NODE_URI_BSCTEST"
  fi

  # get deployer address
  local DEPLOYER_ADDRESS=$(getDeployerAddress "$NETWORK" "$ENVIRONMENT")

  # get actual deploy salt (as we do in DeployScriptBase:  keccak256(abi.encodePacked(saltPrefix, contractName));)
  # prepare web3 code to be executed
  jsCode="const { Web3 } = require('web3');
    const web3 = new Web3();
    const result = web3.utils.soliditySha3({t: 'string', v: '$SALT'},{t: 'string', v: '$CONTRACT_NAME'})
    console.log(result);"

  # execute code using web3
  ACTUAL_SALT=$(node -e "$jsCode")

  # call create3 factory to obtain contract address
  RESULT=$(cast call "$CREATE3_FACTORY_ADDRESS" "getDeployed(address,bytes32) returns (address)" "$DEPLOYER_ADDRESS" "$ACTUAL_SALT" --rpc-url "${!RPC_URL}")

  # return address
  echo "$RESULT"

}
function getCurrentGasPrice() {
  # read function arguments into variables
  local NETWORK=$1

  # get RPC URL for given network
  RPC_URL=$(getRPCUrl "$NETWORK")

  GAS_PRICE=$(cast gas-price --rpc-url "$RPC_URL")

  echo "$GAS_PRICE"
}
function getCurrentContractVersion() {
  # read function arguments into variables
  local CONTRACT="$1"
  local VERSION="$2"
  # get src FILE path for contract
  local FILEPATH=$(getContractFilePath "$CONTRACT" "$VERSION")

  # Check if FILE exists
  if [ ! -f "$FILEPATH" ]; then
    error "the following filepath is invalid: $FILEPATH"
    return 1
  fi

  # Search for "@custom:bfp-version" in the file and store the first result in the variable
  local VERSION=$(grep "@custom:bfp-version" "$FILEPATH" | cut -d ' ' -f 3)

  # Check if VERSION is empty
  if [ -z "$VERSION" ]; then
    error "'@custom:bfp-version' string not found in $FILEPATH"
    return 1
  fi

  echo "$VERSION"
}
function getValueFromJSONFile() {
  # read function arguments into variable
  local FILE_PATH=$1
  local KEY=$2

  # check if file exists
  if ! checkIfFileExists "$FILE_PATH" >/dev/null; then
    error "file does not exist: $FILE_PATH (access attempted by function 'getValueFromJSONFile')"
    return 1
  fi

  # extract and return value from file
  VALUE=$(cat "$FILE_PATH" | jq -r ".$KEY")
  echo "$VALUE"
}
function getBytecodeFromArtifact() {
  # read function arguments into variables
  local contract="$1"

  # get filepath
  local file_path="out/$contract.sol/$contract.json"

  # ensure file exists
  if ! checkIfFileExists "$file_path" >/dev/null; then
    error "file does not exist: $file_path (access attempted by function 'getBytecodeFromArtifact')"
    return 1
  fi

  # read bytecode value from json
  bytecode_json=$(getValueFromJSONFile "$file_path" "bytecode.object")

  # Check if the value obtained starts with "0x"
  if [[ $bytecode_json == 0x* ]]; then
    echo "$bytecode_json"
    return 0
  else
    error "no bytecode found for $contract in file $file_path. Script cannot continue."
    exit 1
  fi
}
function doesAddressContainBytecode() {
  # read function arguments into variables
  NETWORK="$1"
  ADDRESS="$2"

  # check address value
  if [[ "$ADDRESS" == "null" || "$ADDRESS" == "" ]]; then
    echo "[warning]: trying to verify deployment at invalid address: ($ADDRESS)"
    return 1
  fi

  # get correct node URL for given NETWORK
  NODE_URL_KEY="ETH_NODE_URI_$(tr '[:lower:]' '[:upper:]' <<<$NETWORK)"
  if [[ "$NETWORK" == "bsc-testnet" ]]; then
    NODE_URL_KEY="ETH_NODE_URI_BSCTEST"
  fi
  NODE_URL=${!NODE_URL_KEY}

  # check if NODE_URL is available
  if [ -z "$NODE_URL" ]; then
    error ": no node url found for NETWORK $NETWORK. Please update your .env FILE and make sure it has a value for the following key: $NODE_URL_KEY"
    return 1
  fi

  # get contract code from address using cast
  contract_code=$(cast code "$ADDRESS" --rpc-url "$NODE_URL")
  # return ƒalse if ADDRESS does not contain CONTRACT code, otherwise true
  if [[ "$contract_code" == "0x" || "$contract_code" == "" ]]; then
    echo "false"
  else
    echo $contract_code
  fi
}
function doNotContinueUnlessGasIsBelowThreshold() {
  # read function arguments into variables
  local NETWORK=$1

  if [ "$NETWORK" != "mainnet" ]; then
    return 0
  fi

  echo "ensuring gas price is below maximum threshold as defined in config (for mainnet only)"

  # Start the do-while loop
  while true; do
    # Get the current gas price
    CURRENT_GAS_PRICE=$(getCurrentGasPrice "mainnet")

    # Check if the counter variable has reached 10
    if [ "$MAINNET_MAXIMUM_GAS_PRICE" -gt "$CURRENT_GAS_PRICE" ]; then
      # If the counter variable has reached 10, exit the loop
      echo "gas price ($CURRENT_GAS_PRICE) is below maximum threshold ($MAINNET_MAXIMUM_GAS_PRICE) - continuing with script execution"
      return 0
    else
      echo "gas price ($CURRENT_GAS_PRICE) is above maximum ($MAINNET_MAXIMUM_GAS_PRICE) - waiting..."
      echo ""
    fi

    # wait 5 seconds before checking gas price again
    sleep 5
  done
}
function findContractInMasterLog() {
  # read function arguments into variables
  local CONTRACT="$1"
  local NETWORK="$2"
  local ENVIRONMENT="$3"
  local VERSION="$4"

  local FOUND=false

  # Check if log file exists
  if [ ! -f "$LOG_FILE_PATH" ]; then
    echo "deployments log file does not exist in path $LOG_FILE_PATH. Please check and run the script again."
    exit 1
  fi

  # Process JSON data incrementally using jq
  entries=$(jq --arg CONTRACT "$CONTRACT" --arg NETWORK "$NETWORK" --arg ENVIRONMENT "$ENVIRONMENT" --arg VERSION "$VERSION" '
    . as $data |
    keys[] as $contract |
    $data[$contract] |
    keys[] as $network |
    $data[$contract][$network] |
    keys[] as $environment |
    $data[$contract][$network][$environment] |
    keys[] as $version |
    select($contract == $CONTRACT and $network == $NETWORK and $environment == $ENVIRONMENT and $version == $VERSION) |
    $data[$contract][$network][$environment][$version][0]
  ' "$LOG_FILE_PATH")

  # Loop through the entries
  while IFS= read -r entry; do
    if [[ -n "$entry" ]]; then # If entry is not empty
      FOUND=true
      echo "$entry"
    fi
  done <<<"$entries"

  if ! $FOUND; then
    echo "[info] No matching entry found in deployments log file for CONTRACT=$CONTRACT, NETWORK=$NETWORK, ENVIRONMENT=$ENVIRONMENT, VERSION=$VERSION"
    exit 1
  fi

  exit 0
}
function getOptimizerRuns() {
  # define FILE path for foundry config FILE
  FILEPATH="foundry.toml"

  # Check if FILE exists
  if [ ! -f "$FILEPATH" ]; then
    error ": $FILEPATH does not exist."
    return 1
  fi

  # Search for "optimizer_runs =" in the FILE and store the first RESULT in the variable
  VERSION=$(grep "optimizer_runs =" $FILEPATH | cut -d ' ' -f 3)

  # Check if VERSION is empty
  if [ -z "$VERSION" ]; then
    error ": optimizer_runs string not found in $FILEPATH."
    return 1
  fi

  # return OPTIMIZER_RUNS value
  echo "$VERSION"

}
function logContractDeploymentInfo {
  # read function arguments into variables
  local CONTRACT="$1"
  local NETWORK="$2"
  local TIMESTAMP="$3"
  local VERSION="$4"
  local OPTIMIZER_RUNS="$5"
  local CONSTRUCTOR_ARGS="$6"
  local ENVIRONMENT="$7"
  local ADDRESS="$8"
  local VERIFIED="$9"
  local SALT="${10}"
  local CONTRACT_FILE_PATH="${11}"
  local CONTRACT_NAME="${12}"

  if [[ "$ADDRESS" == "null" || -z "$ADDRESS" ]]; then
    error "trying to log an invalid address value (=$ADDRESS) for $CONTRACT on network $NETWORK (environment=$ENVIRONMENT) to master log file. Log will not be updated. Please check and run this script again to secure deploy log data."
    return 1
  fi

  # logging for debug purposes
  echo ""
  echoDebug "in function logContractDeploymentInfo"
  echoDebug "CONTRACT=$CONTRACT"
  echoDebug "NETWORK=$NETWORK"
  echoDebug "TIMESTAMP=$TIMESTAMP"
  echoDebug "VERSION=$VERSION"
  echoDebug "OPTIMIZER_RUNS=$OPTIMIZER_RUNS"
  echoDebug "CONSTRUCTOR_ARGS=$CONSTRUCTOR_ARGS"
  echoDebug "ENVIRONMENT=$ENVIRONMENT"
  echoDebug "ADDRESS=$ADDRESS"
  echoDebug "VERIFIED=$VERIFIED"
  echoDebug "SALT=$SALT"
  echo ""

  # Check if log FILE exists, if not create it
  if [ ! -f "$LOG_FILE_PATH" ]; then
    echo "{}" >"$LOG_FILE_PATH"
  fi

  # Check if entry already exists in log FILE
  local existing_entry=$(jq --arg CONTRACT "$CONTRACT" \
    --arg NETWORK "$NETWORK" \
    --arg ENVIRONMENT "$ENVIRONMENT" \
    --arg VERSION "$VERSION" \
    '.[$CONTRACT][$NETWORK][$ENVIRONMENT][$VERSION]' \
    "$LOG_FILE_PATH")

  # Update existing entry or add new entry to log FILE
  if [[ "$existing_entry" == "null" ]]; then
    jq --arg CONTRACT "$CONTRACT" \
      --arg NETWORK "$NETWORK" \
      --arg ENVIRONMENT "$ENVIRONMENT" \
      --arg VERSION "$VERSION" \
      --arg ADDRESS "$ADDRESS" \
      --arg OPTIMIZER_RUNS "$OPTIMIZER_RUNS" \
      --arg TIMESTAMP "$TIMESTAMP" \
      --arg CONSTRUCTOR_ARGS "$CONSTRUCTOR_ARGS" \
      --arg VERIFIED "$VERIFIED" \
      --arg SALT "$SALT" \
      --arg CONTRACT_FILE_PATH "$CONTRACT_FILE_PATH" \
      --arg CONTRACT_NAME "$CONTRACT_NAME" \
      '.[$CONTRACT][$NETWORK][$ENVIRONMENT][$VERSION] += [{ ADDRESS: $ADDRESS, OPTIMIZER_RUNS: $OPTIMIZER_RUNS, TIMESTAMP: $TIMESTAMP, CONSTRUCTOR_ARGS: $CONSTRUCTOR_ARGS, SALT: $SALT, VERIFIED: $VERIFIED, CONTRACT_FILE_PATH: $CONTRACT_FILE_PATH, CONTRACT_NAME: $CONTRACT_NAME }]' \
      "$LOG_FILE_PATH" >tmpfile && mv tmpfile "$LOG_FILE_PATH"
  else
    jq --arg CONTRACT "$CONTRACT" \
      --arg NETWORK "$NETWORK" \
      --arg ENVIRONMENT "$ENVIRONMENT" \
      --arg VERSION "$VERSION" \
      --arg ADDRESS "$ADDRESS" \
      --arg OPTIMIZER_RUNS "$OPTIMIZER_RUNS" \
      --arg TIMESTAMP "$TIMESTAMP" \
      --arg CONSTRUCTOR_ARGS "$CONSTRUCTOR_ARGS" \
      --arg VERIFIED "$VERIFIED" \
      --arg SALT "$SALT" \
      --arg CONTRACT_FILE_PATH "$CONTRACT_FILE_PATH" \
      --arg CONTRACT_NAME "$CONTRACT_NAME" \
      '.[$CONTRACT][$NETWORK][$ENVIRONMENT][$VERSION][-1] |= { ADDRESS: $ADDRESS, OPTIMIZER_RUNS: $OPTIMIZER_RUNS, TIMESTAMP: $TIMESTAMP, CONSTRUCTOR_ARGS: $CONSTRUCTOR_ARGS, SALT: $SALT, VERIFIED: $VERIFIED, CONTRACT_FILE_PATH: $CONTRACT_FILE_PATH, CONTRACT_NAME: $CONTRACT_NAME }' \
      "$LOG_FILE_PATH" >tmpfile && mv tmpfile "$LOG_FILE_PATH"
  fi

  echoDebug "contract deployment info added to log FILE (CONTRACT=$CONTRACT, NETWORK=$NETWORK, ENVIRONMENT=$ENVIRONMENT, VERSION=$VERSION)"
}
function saveContract() {
  # read function arguments into variables
  local NETWORK=$1
  local CONTRACT=$2
  local ADDRESS=$3
  local FILE_SUFFIX=$4

  # load JSON FILE that contains deployment addresses
  ADDRESSES_FILE="./deployments/${NETWORK}.${FILE_SUFFIX}json"

  # logging for debug purposes
  echo ""
  echoDebug "in function saveContract"
  echoDebug "NETWORK=$NETWORK"
  echoDebug "CONTRACT=$CONTRACT"
  echoDebug "ADDRESS=$ADDRESS"
  echoDebug "FILE_SUFFIX=$FILE_SUFFIX"
  echoDebug "ADDRESSES_FILE=$ADDRESSES_FILE"

  if [[ "$ADDRESS" == *"null"* || -z "$ADDRESS" ]]; then
    error "trying to write a 'null' address to $ADDRESSES_FILE for $CONTRACT. Log file will not be updated."
    return 1
  fi

  # create an empty json if it does not exist
  if [[ ! -e $ADDRESSES_FILE ]]; then
    echo "{}" >"$ADDRESSES_FILE"
  fi

  # add new address to address log FILE
  RESULT=$(cat "$ADDRESSES_FILE" | jq -r ". + {\"$CONTRACT\": \"$ADDRESS\"}" || cat "$ADDRESSES_FILE")
  printf %s "$RESULT" >"$ADDRESSES_FILE"
}
