#!/bin/bash

# load env variables
source .env

# load helper functions
source script/helpers.sh

# load config
source script/config.sh

function verifyContract() {
  # read function arguments into variables
  local NETWORK=$1
  local CONTRACT=$2
  local ADDRESS=$3
  local ARGS=$4
  local CONTRACT_FILE_PATH=$5
  local CONTRACT_NAME=$6

  # get API key for blockchain explorer
  if [[ "$NETWORK" == "bsc-testnet" ]]; then
    API_KEY="BSC_ETHERSCAN_API_KEY"
  else
    API_KEY="$(tr '[:lower:]' '[:upper:]' <<<$NETWORK)_ETHERSCAN_API_KEY"
  fi

  # logging for debug purposes
  echo ""
  echoDebug "in function verifyContract"
  echoDebug "NETWORK=$NETWORK"
  echoDebug "CONTRACT=$CONTRACT"
  echoDebug "ADDRESS=$ADDRESS"
  echoDebug "ARGS=$ARGS"
  echoDebug "blockexplorer API_KEY=${API_KEY}"
  echoDebug "blockexplorer API_KEY value=${!API_KEY}"

  if [[ -n "$DO_NOT_VERIFY_IN_THESE_NETWORKS" ]]; then
    case ",$DO_NOT_VERIFY_IN_THESE_NETWORKS," in
    *,"$NETWORK",*)
      echoDebug "network $NETWORK is excluded for contract verification, therefore verification of contract $CONTRACT will be skipped"
      return 1
      ;;
    esac
  fi
  # get contract name from log file CONTRACT_NAME propert

  # verify contract using forge
  MAX_RETRIES=$MAX_ATTEMPTS_PER_CONTRACT_VERIFICATION
  RETRY_COUNT=0
  COMMAND_STATUS=1
  FULL_PATH="$CONTRACT_FILE_PATH"":""$CONTRACT_NAME"
  CHAIN_ID=$(getChainId "$NETWORK")

  if [ $? -ne 0 ]; then
    warning "could not find chainId for network $NETWORK (was this network recently added? Then update helper function 'getChainId'"
  fi

  while [ $COMMAND_STATUS -ne 0 -a $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ "$ARGS" = "0x" ]; then
      # only show output if DEBUG flag is activated
      if [[ "$DEBUG" == *"true"* ]]; then
        if [[ $NETWORK == "zksync" ]]; then
          # Verify using foundry-zksync from docker image
          docker run --rm -it -v .:/foundry -u $(id -u):$(id -g) -e FOUNDRY_PROFILE=zksync foundry-zksync forge verify-contract --zksync --watch --chain 324 "$ADDRESS" "$FULL_PATH" --skip-is-verified-check -e "${!API_KEY}"
        else
          forge verify-contract --watch --chain "$CHAIN_ID" "$ADDRESS" "$FULL_PATH" --skip-is-verified-check -e "${!API_KEY}"
        fi

        # TODO: add code that automatically identifies blockscout verification
      else
        if [[ $NETWORK == "zksync" ]]; then
          # Verify using foundry-zksync from docker image
          docker run --rm -it -v .:/foundry -u $(id -u):$(id -g) -e FOUNDRY_PROFILE=zksync foundry-zksync forge verify-contract --zksync --watch --chain "$CHAIN_ID" "$ADDRESS" "$FULL_PATH" --skip-is-verified-check -e "${!API_KEY}" >/dev/null 2>&1
        else
          forge verify-contract --watch --chain "$CHAIN_ID" "$ADDRESS" "$FULL_PATH"  --skip-is-verified-check -e "${!API_KEY}" >/dev/null 2>&1
        fi
      fi
    else
      # only show output if DEBUG flag is activated
      if [[ "$DEBUG" == *"true"* ]]; then
        if [[ $NETWORK == "zksync" ]]; then
          # Verify using foundry-zksync from docker image
         docker run --rm -it -v .:/foundry -u $(id -u):$(id -g) -e FOUNDRY_PROFILE=zksync foundry-zksync forge verify-contract --zksync --watch --chain "$CHAIN_ID" "$ADDRESS" "$FULL_PATH" --constructor-args $ARGS --skip-is-verified-check -e "${!API_KEY}"
        else
          forge verify-contract --watch --chain "$CHAIN_ID" "$ADDRESS" "$FULL_PATH" --constructor-args $ARGS --skip-is-verified-check -e "${!API_KEY}"
        fi
      else
        if [[ $NETWORK == "zksync" ]]; then
          # Verify using foundry-zksync from docker image
         docker run --rm -it -v .:/foundry -u $(id -u):$(id -g) -e FOUNDRY_PROFILE=zksync foundry-zksync forge verify-contract --zksync --watch --chain "$CHAIN_ID" "$ADDRESS" "$FULL_PATH" --constructor-args $ARGS --skip-is-verified-check -e "${!API_KEY}" >/dev/null 2>&1
        else
          forge verify-contract --watch --chain "$CHAIN_ID" "$ADDRESS" "$FULL_PATH" --constructor-ar --zksyncgs $ARGS --skip-is-verified-check -e "${!API_KEY}" >/dev/null 2>&1
        fi
      fi
    fi
    COMMAND_STATUS=$?
    RETRY_COUNT=$((RETRY_COUNT + 1))
  done

  # check the return status of the contract verification call
  if [ $COMMAND_STATUS -ne 0 ]; then
    warning "$CONTRACT on $NETWORK with address $ADDRESS could not be verified"
  else
    echo "[info] $CONTRACT on $NETWORK with address $ADDRESS successfully verified"
    return 0
  fi

  echo "[info] trying to verify $CONTRACT on $NETWORK with address $ADDRESS using Sourcify now"
  forge verify-contract \
    "$ADDRESS" \
    "$CONTRACT" \
    --chain-id "$CHAIN_ID" \
    --verifier  sourcify

  echo "[info] checking Sourcify verification now"
  forge verify-check $ADDRESS \
    --chain-id "$CHAIN_ID" \
    --verifier sourcify

  if [ $? -ne 0 ]; then
    # verification apparently failed
    warning "[info] $CONTRACT on $NETWORK with address $ADDRESS could not be verified using Sourcify"
    return 1
  else
    # verification successful
    echo "[info] $CONTRACT on $NETWORK with address $ADDRESS successfully verified using Sourcify"
    return 0
  fi
}
function verifyAllUnverifiedContractsInLogFile() {

    # load env variables
  source .env

  # load helper functions
  source script/helpers.sh

  # load config
  source script/config.sh
  # Check if target state FILE exists
  if [ ! -f "$LOG_FILE_PATH" ]; then
    error "log file does not exist in path $LOG_FILE_PATH"
    exit 1
  fi

  echo "[info] checking log file for unverified contracts"

  # initate counter
  local COUNTER=0

  # Read top-level keys into an array
  CONTRACTS=($(jq -r 'keys[]' "$LOG_FILE_PATH"))

  # Loop through the array of top-level keys
  for CONTRACT in "${CONTRACTS[@]}"; do

    # Read second-level keys for the current top-level key
    NETWORKS=($(jq -r ".${CONTRACT} | keys[]" "$LOG_FILE_PATH"))

    # Loop through the array of second-level keys
    for NETWORK in "${NETWORKS[@]}"; do

      #      if [[ $NETWORK != "mainnet" ]]; then
      #        continue
      #      fi

      # Read ENVIRONMENT keys for the network
      ENVIRONMENTS=($(jq -r --arg contract "$CONTRACT" --arg network "$NETWORK" '.[$contract][$network] | keys[]' "$LOG_FILE_PATH"))

      # go through all environments
      for ENVIRONMENT in "${ENVIRONMENTS[@]}"; do

        # Read VERSION keys for the network
        VERSIONS=($(jq -r --arg contract "$CONTRACT" --arg network "$NETWORK" --arg environment "$ENVIRONMENT" '.[$contract][$network][$environment] | keys[]' "$LOG_FILE_PATH"))

        # go through all versions
        for VERSION in "${VERSIONS[@]}"; do

          # get values of current entry
          ENTRY=$(cat "$LOG_FILE_PATH" | jq -r --arg contract "$CONTRACT" --arg network "$NETWORK" --arg environment "$ENVIRONMENT" --arg version "$VERSION" '.[$contract][$network][$environment][$version][0]')

          # extract necessary information from log
          ADDRESS=$(echo "$ENTRY" | awk -F'"' '/"ADDRESS":/{print $4}')
          VERIFIED=$(echo "$ENTRY" | awk -F'"' '/"VERIFIED":/{print $4}')
          OPTIMIZER_RUNS=$(echo "$ENTRY" | awk -F'"' '/"OPTIMIZER_RUNS":/{print $4}')
          TIMESTAMP=$(echo "$ENTRY" | awk -F'"' '/"TIMESTAMP":/{print $4}')
          CONSTRUCTOR_ARGS=$(echo "$ENTRY" | awk -F'"' '/"CONSTRUCTOR_ARGS":/{print $4}')
          CONTRACT_FILE_PATH=$(echo "$ENTRY" | awk -F'"' '/"CONTRACT_FILE_PATH":/{print $4}')
          CONTRACT_NAME=$(echo "$ENTRY" | awk -F'"' '/"CONTRACT_NAME":/{print $4}')

          # check if contract is verified
          if [[ "$VERIFIED" != "true" ]]; then
            echo ""
            echo "[info] trying to verify contract $CONTRACT on $NETWORK with address $ADDRESS...."
            if [[ "$DEBUG" == *"true"* ]]; then
              verifyContract "$NETWORK" "$CONTRACT" "$ADDRESS" "$CONSTRUCTOR_ARGS" "$CONTRACT_FILE_PATH" "$CONTRACT_NAME"
            else
              verifyContract "$NETWORK" "$CONTRACT" "$ADDRESS" "$CONSTRUCTOR_ARGS" "$CONTRACT_FILE_PATH" "$CONTRACT_NAME" 2>/dev/null
            fi

            # check result
            if [ $? -eq 0 ]; then
              # update log file
              logContractDeploymentInfo "$CONTRACT" "$NETWORK" "$TIMESTAMP" "$VERSION" "$OPTIMIZER_RUNS" "$CONSTRUCTOR_ARGS" "$ENVIRONMENT" "$ADDRESS" "true" "$SALT" "$CONTRACT_FILE_PATH" "$CONTRACT_NAME"

              # increase COUNTER
              COUNTER=$((COUNTER + 1))
            fi
          fi
        done
      done
    done
  done

  echo "[info] done (verified contracts: $COUNTER)"
}
