#!/bin/bash

# Original script forked from:
# https://github.com/lifinance/contracts/blob/main/script/scriptMaster.sh

# TODO
#   >> minimize search master deploy log (takes a lot of time)
# - replace debug outputs with new helper method

# - make helper functions robust for networks with -
#   >>> including the solidity update config scripts

# - create function that checks if contract is deployed (get bytecode, predict address, check bytecode at address)
# - return master log to store all deployments (and return latest when inquired)
# - add use case to only remove a facet
# - check if use case 4 will also check if a contract is added to diamond already
# - create use case to deploy and add all periphery (or check if target state use case covers it)
# - merging two branches with deployments in same network (does it cause merge-conflicts?)

# - clean code
#   - local before variables
#   - make environment / file suffix global variables
#   - add function descriptions in helper functions

# - add fancy stuff
#   -  add low balance warnings and currency symbols for deployer wallet balance

scriptMaster() {
  echo "[info] loading required resources and compiling contracts"
  # load env variables
  source .env

  # load deploy script & helper functions
  source script/deploy/deploySingleContract.sh
  source script/helperFunctions.sh
  source script/config.sh
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
      "2) Deploy one specific contract to all (not-excluded) networks (=new contract)" \
      "3) Execute a script" \
      "4) Verify all unverified contracts" \
      "5) Propose upgrade TX to Gnosis SAFE"
  )

  #---------------------------------------------------------------------------------------------------------------------
  # use case 1: Deploy one specific contract to one network
  if [[ "$SELECTION" == "1)"* ]]; then
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
    local VERSION=$(getCurrentContractVersion "$CONTRACT")

    # just deploy the contract
    deploySingleContract "$CONTRACT" "$NETWORK" "$ENVIRONMENT" "" false

    # check if last command was executed successfully, otherwise exit script with error message
    checkFailure $? "deploy contract $CONTRACT to network $NETWORK"

  #---------------------------------------------------------------------------------------------------------------------
  # use case 2: Deploy one specific contract to all networks (=new contract)
  elif [[ "$SELECTION" == "2)"* ]]; then
    echo ""
    echo "[info] selected use case: Deploy one specific contract to all networks"

    # get user-selected deploy script and contract from list
    local SCRIPT=$(ls -1 "$DEPLOY_SCRIPT_DIRECTORY" | sed -e 's/.s.sol$//' | grep 'Deploy' | gum filter --placeholder "Deploy Script")
    local CONTRACT=$(echo $SCRIPT | sed -e 's/Deploy//')

    # get current contract version
    local VERSION=$(getCurrentContractVersion "$CONTRACT")

    # get array with all network names
    local NETWORKS=($(getIncludedNetworksArray))

    # loop through all networks
    for NETWORK in "${NETWORKS[@]}"; do
      echo ""
      echo ""
      echo "[info] >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> now deploying contract $CONTRACT to network $NETWORK...."

      # get deployer wallet balance
      BALANCE=$(getDeployerBalance "$NETWORK" "$ENVIRONMENT")
      echo "[info] deployer wallet balance in this network: $BALANCE"
      echo ""

      # just deploy the contract
      deploySingleContract "$CONTRACT" "$NETWORK" "$ENVIRONMENT" "$VERSION" false

      echo "[info] <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< network $NETWORK done"
    done

    playNotificationSound

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