
#!/bin/bash

# defines the environment (true=production, false=staging)
PRODUCTION=true

# the maximum time in seconds that the script will wait for blockchain to sync contract deployment
# we use this as double check to make sure that a contract was actually deployed
MAX_WAITING_TIME_FOR_BLOCKCHAIN_SYNC=60

# the maximum number of attempts to deploy a single contract
MAX_ATTEMPTS_PER_CONTRACT_DEPLOYMENT=10

# the maximum number of attempts to verify contract
MAX_ATTEMPTS_PER_CONTRACT_VERIFICATION=5

# the maximum number of attempts to execute a script (e.g. diamondUpdate)
MAX_ATTEMPTS_PER_SCRIPT_EXECUTION=5

# the root directory of all contract src files
CONTRACT_DIRECTORY="contracts/"

# the directory of all deploy and update script
DEPLOY_SCRIPT_DIRECTORY="script/deploy/"

# the directory of all task script
TASKS_SCRIPT_DIRECTORY="script/tasks/"

# the path of the JSON file that contains the deployment log file
LOG_FILE_PATH="deployments/_deployments_log_file.json"

# the path of the JSON file that contains the bytecode storage file
BYTECODE_STORAGE_PATH="deployments/_bytecode_storage.json"

# the path of the JSON file that contains deploy requirements per contract
DEPLOY_REQUIREMENTS_PATH="script/deploy/resources/deployRequirements.json"

# the path of the JSON files that contains deploy configuration per contract
DEPLOY_CONFIG_FILE_PATH="config/"

# any networks listed here will be excluded from actions that are applied to "all networks"
# exclude all test networks:       EXCLUDE_NETWORKS="bsctest,goerli,sepolia,mumbai,lineatest,localanvil"
# exclude all production networks: EXCLUDE_NETWORKS="mainnet,polygon,bsc,gnosis,fantom,okx,avalanche,arbitrum,optimism,moonriver,moonbeam,celo,fuse,cronos,velas,harmony,evmos,aurora,boba,nova"
#EXCLUDE_NETWORKS="gnosis,okx,moonbeam,celo,fuse,cronos,velas,harmony,evmos,boba,nova,bsctest,goerli,sepolia,mumbai,lineatest"
EXCLUDE_NETWORKS="lineatest,localanvil"

# a list of all networks that are testnets
TEST_NETWORKS="bsc-testnet,goerli,sepolia,mumbai,lineatest,localanvil"

# will output more detailed information for debugging purposes
DEBUG=true

# defines if newly deployed contracts should be verified or not
VERIFY_CONTRACTS=false

# contract verification will be deactivated for any network listed here
DO_NOT_VERIFY_IN_THESE_NETWORKS="gnosis,testNetwork,aurora,localanvil"

# the path to the file that contains a list of all networks
NETWORKS_FILE_PATH="./networks"

# enable/disable notification sounds for long-running scripts
NOTIFICATION_SOUNDS=true

# Defines the maximum gas price for mainnet transactions (otherwise the script will wait until gas price is down)
MAINNET_MAXIMUM_GAS_PRICE=50000000000 # = 50 Gwei

# used to start a local (Foundry) anvil network with the same private keys for testing purposes
MNEMONIC="test test test test test test test test test test test junk"
PRIVATE_KEY_ANVIL=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 # address: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
START_LOCAL_ANVIL_NETWORK_ON_SCRIPT_STARTUP=false
END_LOCAL_ANVIL_NETWORK_ON_SCRIPT_COMPLETION=true # set to false if you want to run several scripts on the same data/contracts without redeploying
