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

  # return RPC URL
  echo "${!RPC_KEY}"
}
function getDeployerAddress() {
  # read function arguments into variables
  local NETWORK=$1
  local ENVIRONMENT=$2

  PRIV_KEY="$(getPrivateKey "$NETWORK" "$ENVIRONMENT")"

  # prepare web3 code to be executed
  jsCode="const Web3 = require('web3');
    const web3 = new Web3();
    const deployerAddress = (web3.eth.accounts.privateKeyToAccount('$PRIV_KEY')).address
    const checksumAddress = web3.utils.toChecksumAddress(deployerAddress);
    console.log(checksumAddress);"

  # execute code using web3
  DEPLOYER_ADDRESS=$(node -e "$jsCode")

  # return deployer address
  echo "$DEPLOYER_ADDRESS"
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

  # get deployer address
  local DEPLOYER_ADDRESS=$(getDeployerAddress "$NETWORK" "$ENVIRONMENT")

  # get actual deploy salt (as we do in DeployScriptBase:  keccak256(abi.encodePacked(saltPrefix, contractName));)
  # prepare web3 code to be executed
  jsCode="const Web3 = require('web3');
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

  # get src FILE path for contract
  local FILEPATH=$(getContractFilePath "$CONTRACT")
  wait

  # Check if FILE exists
  if [ ! -f "$FILEPATH" ]; then
    error "the following filepath is invalid: $FILEPATH"
    return 1
  fi

  # Search for "@custom:version" in the file and store the first result in the variable
  local VERSION=$(grep "@custom:version" "$FILEPATH" | cut -d ' ' -f 3)

  # Check if VERSION is empty
  if [ -z "$VERSION" ]; then
    error "'@custom:version' string not found in $FILEPATH"
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
  NODE_URL=${!NODE_URL_KEY}

  # check if NODE_URL is available
  if [ -z "$NODE_URL" ]; then
    error ": no node url found for NETWORK $NETWORK. Please update your .env FILE and make sure it has a value for the following key: $NODE_URL_KEY"
    return 1
  fi

  # make sure address is in correct checksum format
  jsCode="const Web3 = require('web3');
    const web3 = new Web3();
    const address = '$ADDRESS';
    const checksumAddress = web3.utils.toChecksumAddress(address);
    console.log(checksumAddress);"
  CHECKSUM_ADDRESS=$(node -e "$jsCode")

  # get CONTRACT code from ADDRESS using web3
  jsCode="const Web3 = require('web3');
    const web3 = new Web3('$NODE_URL');
    web3.eth.getCode('$CHECKSUM_ADDRESS', (error, RESULT) => { console.log(RESULT); });"
  contract_code=$(node -e "$jsCode")

  # return ƒalse if ADDRESS does not contain CONTRACT code, otherwise true
  if [[ "$contract_code" == "0x" || "$contract_code" == "" ]]; then
    echo "false"
  else
    echo "true"
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
