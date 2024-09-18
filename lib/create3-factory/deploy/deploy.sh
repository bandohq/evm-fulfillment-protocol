#!/bin/bash

# load env variables
source .env

deploy() {
	NETWORK=$1

	# get deployer address
	DEPLOYER_ADDRESS=$(cast wallet address "$PRIVATE_KEY")
	echo "You are deploying from address: $DEPLOYER_ADDRESS (should be 0x11F11121DF7256C40339393b0FB045321022ce44 for 0x123 diamond address)"

	RAW_RETURN_DATA=$(forge script script/Deploy.s.sol -f $NETWORK -vvvv --json --verify --legacy --silent --broadcast)
	# RAW_RETURN_DATA=$(forge script script/Deploy.s.sol -f $NETWORK -vvvv --json --silent --verify --verifier "blockscout" --verifier-url "https://explorer.immutable.com/api" --broadcast)
	RETURN_DATA=$(echo $RAW_RETURN_DATA | jq -r '.returns' 2>/dev/null)

	factory=$(echo $RETURN_DATA | jq -r '.factory.value')

	saveContract $NETWORK CREATE3Factory $factory
}

saveContract() {
	NETWORK=$1
	CONTRACT=$2
	ADDRESS=$3

	ADDRESSES_FILE=./deployments/$NETWORK.json

	# create an empty json if it does not exist
	if [[ ! -e $ADDRESSES_FILE ]]; then
		echo "{}" >"$ADDRESSES_FILE"
	fi
	result=$(cat "$ADDRESSES_FILE" | jq -r ". + {\"$CONTRACT\": \"$ADDRESS\"}")
	printf %s "$result" >"$ADDRESSES_FILE"
}

deploy $1
