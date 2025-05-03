#!/bin/bash

# Original script forked from:
# https://github.com/lifinance/contracts/blob/main/script/scriptMaster.sh

scriptMaster() {
  echo "[info] loading required resources and compiling contracts"
  # load env variables
  source .env

  # load deploy script & helper functions
  source script/deploy/deploySingleContract.sh
  source script/helpers.sh
  source script/config.sh
  source script/verify.sh
  # still not activated ---v
  #source script/deploy/deployUpgradesToSAFE.sh
  #for script in script/tasks/*.sh; do [ -f "$script" ] && source "$script"; done # sources all script in folder script/tasks/

  # make sure that all compiled artifacts are current
  forge build

  # start local anvil network if flag in config is set
  if [[ "$START_LOCAL_ANVIL_NETWORK_ON_SCRIPT_STARTUP" == "true" ]]; then
    # check if anvil is already running
    if pgrep -x "anvil" >/dev/null; then
      echoDebug "local testnetwork 'localanvil' is running"
    else
      echoDebug "Anvil process is not running. Starting network now."
      $(anvil -m "$MNEMONIC" -f $ETH_NODE_URI_MAINNET --fork-block-number 17427723 >/dev/null) &
      if pgrep -x "anvil" >/dev/null; then
        echoDebug "local testnetwork 'localanvil' is running"
      else
        error "local testnetwork 'localanvil' could not be started. Exiting script now."
      fi
    fi
  fi

  # determine environment: check if .env variable "PRODUCTION" is set to true
  if [[ "$PRODUCTION" == "true" ]]; then
    # make sure that PRODUCTION was selected intentionally by user
    echo "    "
    echo "    "
    printf '\033[31m%s\031\n' "!!!!!!!!!!!!!!!!!!!!!!!! ATTENTION !!!!!!!!!!!!!!!!!!!!!!!!"
    printf '\033[33m%s\033[0m\n' "The config environment variable PRODUCTION is set to true"
    printf '\033[33m%s\033[0m\n' "This means you will be deploying contracts to production"
    printf '\033[31m%s\031\n' "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "    "
    printf '\033[33m%s\033[0m\n' "Last chance: Do you want to skip?"
    PROD_SELECTION=$(
      gum choose \
        "yes" \
        "no"
    )

    if [[ $PROD_SELECTION != "no" ]]; then
      echo "...exiting script"
      exit 0
    fi

    ENVIRONMENT="production"
  else
    ENVIRONMENT="staging"
  fi

  # ask user to choose a deploy use case
  echo ""
  echo "You are executing transactions from this address: $(getDeployerAddress "" "$ENVIRONMENT") (except for network 'localanvil': 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266)"
  echo ""
  echo "Please choose one of the following options:"
  local SELECTION=$(
    gum choose \
      "1) Deploy one specific contract to one network" \
      "2) Deploy one specific contract to selected networks" \
      "3) Execute a script" \
      "4) Verify all unverified contracts" \
      "5) Deploy and configure protocol contracts to one network" \
  )

  #---------------------------------------------------------------------------------------------------------------------
  # use case 1: Deploy one specific contract to one network
  if [[ "$SELECTION" == "1)"* ]]; then
    echo "Is this a proxy deployment?"
    PROXY_SELECTION=$(
      gum choose \
        "yes" \
        "no"
    )
    echo ""
    echo "[info] selected use case: Deploy one specific contract to one network"
    # get user-selected network from list
    local NETWORK=$(cat ./networks | gum filter --placeholder "Network")

    echo "[info] selected network: $NETWORK"
    echo "[info] loading deployer wallet balance..."

    # get deployer wallet balance
    BALANCE=$(getDeployerBalance "$NETWORK" "$ENVIRONMENT")

    echo "[info] deployer wallet balance in this network: $BALANCE"
    echo ""
    checkRequiredVariablesInDotEnv $NETWORK

    # get user-selected deploy script and contract from list
    SCRIPT=$(ls -1 "$DEPLOY_SCRIPT_DIRECTORY" | sed -e 's/\.s.sol$//' | grep 'Deploy' | gum filter --placeholder "Deploy Script")
    CONTRACT=$(echo $SCRIPT | sed -e 's/Deploy//')

    # get current contract version
    local VERSION=$(getCurrentContractVersion "$CONTRACT" "1")

    if [[ "$PROXY_SELECTION" == "yes" ]]; then
      echo "[info] PROXY_SELECTION: $PROXY_SELECTION"
      IS_PROXY="true"
    else
      IS_PROXY="false"
    fi
    # just deploy the contract
    deploySingleContract "$CONTRACT" "$NETWORK" "$ENVIRONMENT" "$VERSION" false "$IS_PROXY"

    # check if last command was executed successfully, otherwise exit script with error message
    checkFailure $? "deploy contract $CONTRACT to network $NETWORK"

  #---------------------------------------------------------------------------------------------------------------------
  # use case 2: Deploy one specific contract to selected networks
  elif [[ "$SELECTION" == "2)"* ]]; then
    echo ""
    echo "[info] selected use case: Deploy one specific contract to selected networks"
    echo "Is this a proxy deployment?"
    PROXY_SELECTION=$(
      gum choose \
        "yes" \
        "no"
    )
    echo ""
    echo "[info] selected use case: Deploy one specific contract to selected networks"
    echo ""
    local NETWORKS=$(cat ./networks | gum filter --placeholder "Networks" --no-limit)
    echo ""
    echo "[info] selected networks: $NETWORKS"
    echo ""

    # get user-selected deploy script and contract from list
    local SCRIPT=$(ls -1 "$DEPLOY_SCRIPT_DIRECTORY" | sed -e 's/.s.sol$//' | grep 'Deploy' | gum filter --placeholder "Deploy Script")
    local CONTRACT=$(echo $SCRIPT | sed -e 's/Deploy//')

    # get current contract version
    local VERSION=$(getCurrentContractVersion "$CONTRACT" "1")

    # loop through all networks
    for NETWORK in $NETWORKS; do
      echo ""
      echo ""
      echo "[info] >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> now deploying contract $CONTRACT to network $NETWORK...."

      # get deployer wallet balance
      BALANCE=$(getDeployerBalance "$NETWORK" "$ENVIRONMENT")
      echo "[info] deployer wallet balance in this network: $BALANCE"
      echo ""
      checkRequiredVariablesInDotEnv "$NETWORK"
      if [[ "$PROXY_SELECTION" == "yes" ]]; then
        echo "[info] PROXY_SELECTION: $PROXY_SELECTION"
        IS_PROXY="true"
      else
        IS_PROXY="false"
      fi
      # just deploy the contract
      deploySingleContract "$CONTRACT" "$NETWORK" "$ENVIRONMENT" "$VERSION" false "$IS_PROXY"

      echo "[info] <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< network $NETWORK done"
    done
  #---------------------------------------------------------------------------------------------------------------------
  # use case 3: Execute a script
  elif [[ "$SELECTION" == "3)"* ]]; then
    echo ""
    SCRIPT=$(ls -1p "$TASKS_SCRIPT_DIRECTORY" | grep -v "/$" | sed -e 's/\.sh$//' | gum filter --placeholder "Please select the script you would like to execute: ")
    if [[ -z "$SCRIPT" ]]; then
      error "invalid value selected - exiting script now"
      exit 1
    fi

    echo "[info] selected script: $SCRIPT"

    # execute the selected script
    eval "$SCRIPT" '""' "$ENVIRONMENT"

  #---------------------------------------------------------------------------------------------------------------------
  # use case 4: Verify all unverified contracts
  elif [[ "$SELECTION" == "4)"* ]]; then
    verifyAllUnverifiedContractsInLogFile
    playNotificationSound
  
  #---------------------------------------------------------------------------------------------------------------------
  # use case 6: Propose upgrade TX to Gnosis SAFE
  #elif [[ "$SELECTION" == "6)"* ]]; then
  #  deployUpgradesToSAFE $ENVIRONMENT
  #else
  #  error "invalid use case selected ('$SELECTION') - exiting script"
  #  cleanup
  #  exit 1
  elif [[ "$SELECTION" == "5)"* ]]; then
    echo "[info] selected: deploy protocol contract to network"
    local NETWORK=$(cat ./networks | gum filter --placeholder "Network")

    echo "[info] selected network: $NETWORK"
    echo "[info] loading deployer wallet balance..."

    # get deployer wallet balance
    BALANCE=$(getDeployerBalance "$NETWORK" "$ENVIRONMENT")

    echo "[info] deployer wallet balance in this network: $BALANCE"
    echo ""
    checkRequiredVariablesInDotEnv $NETWORK

    # -- Deploy registries w proxy ---
    # get current contract version
    local VERSION=$(getCurrentContractVersion "FulfillableRegistry" "1")
    deploySingleContract "FulfillableRegistry" "$NETWORK" "$ENVIRONMENT" "$VERSION" false true

    # get current erc20 token registry contract version
    local VERSION=$(getCurrentContractVersion "ERC20TokenRegistry" "1")
    deploySingleContract "ERC20TokenRegistry" "$NETWORK" "$ENVIRONMENT" "$VERSION" false true

    # -- Deploy escrow contracts ---
    # get current escrow contract version
    local VERSION=$(getCurrentContractVersion "BandoFulfillable" "1")
    deploySingleContract "BandoFulfillable" "$NETWORK" "$ENVIRONMENT" "$VERSION" false true

    # get current erc20 escrow contract version
    local VERSION=$(getCurrentContractVersion "BandoERC20Fulfillable" "1")
    deploySingleContract "BandoERC20Fulfillable" "$NETWORK" "$ENVIRONMENT" "$VERSION" false true

    # -- Deploy Router ---
    # get current router contract version
    local VERSION=$(getCurrentContractVersion "BandoRouter" "1")
    deploySingleContract "BandoRouter" "$NETWORK" "$ENVIRONMENT" "$VERSION" false true

    # -- Deploy Manager ---
    # get current manager contract version
    local VERSION=$(getCurrentContractVersion "BandoFulfillmentManager" "1")
    deploySingleContract "BandoFulfillmentManager" "$NETWORK" "$ENVIRONMENT" "$VERSION" false true

    # -- Deploy V1.1 Registry ---
    # get current registry contract version
    local VERSION=$(getCurrentContractVersion "FulfillableRegistryV1_1" "1.1")
    deploySingleContract "FulfillableRegistryV1_1" "$NETWORK" "$ENVIRONMENT" "$VERSION" false false

    # -- Deploy V1.2 Escrows ---
    # get current escrow contract version
    local VERSION=$(getCurrentContractVersion "BandoFulfillableV1_2" "1.2")
    deploySingleContract "BandoFulfillableV1_2" "$NETWORK" "$ENVIRONMENT" "$VERSION" false false

    # get current erc20 escrow contract version
    local VERSION=$(getCurrentContractVersion "BandoERC20FulfillableV1_2" "1.2")
    deploySingleContract "BandoERC20FulfillableV1_2" "$NETWORK" "$ENVIRONMENT" "$VERSION" false false

    # -- Deploy V1.1 Router ---
    # get current router contract version
    local VERSION=$(getCurrentContractVersion "BandoRouterV1_1" "1.1")
    deploySingleContract "BandoRouterV1_1" "$NETWORK" "$ENVIRONMENT" "$VERSION" false false

    # -- Deploy V1.2 Manager ---
    # get current manager contract version
    local VERSION=$(getCurrentContractVersion "BandoFulfillmentManagerV1_2" "1.2")
    deploySingleContract "BandoFulfillmentManagerV1_2" "$NETWORK" "$ENVIRONMENT" "$VERSION" false false

    # configure contracts
    npx hardhat --network "$NETWORK" run scripts/configureBFP.js

    # check if last command was executed successfully, otherwise exit script with error message
    checkFailure $? "configure contracts"
    
  fi

  cleanup

  # inform user and end script
  echo ""
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "[info] PLEASE CHECK THE LOG CAREFULLY FOR WARNINGS AND ERRORS"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
}

cleanup() {
  # end local anvil network if flag in config is set
  if [[ "$END_LOCAL_ANVIL_NETWORK_ON_SCRIPT_COMPLETION" == "true" ]]; then
    echoDebug "ending anvil network and removing localanvil deploy logs"
    # kills all local anvil network sessions that might still be running
    killall anvil >/dev/null 2>&1
    # delete log files
    rm deployments/localanvil.json >/dev/null 2>&1
    rm deployments/localanvil.staging.json >/dev/null 2>&1
  fi
}

scriptMaster