# Bando EVM Smart Contracts

The Bando Fulfillment Protocol EVM smart contracts suite suite.

[![Run Tests and Coverage](https://github.com/bandohq/evm-fulfillment-protocol/actions/workflows/ci.yaml/badge.svg)](https://github.com/bandohq/evm-fulfillment-protocol/actions/workflows/ci.yaml)
[![Build](https://github.com/bandohq/evm-fulfillment-protocol/actions/workflows/build-abis.yml/badge.svg)](https://github.com/bandohq/evm-fulfillment-protocol/actions/workflows/build-abis.yml)

## Overview 
For a more detail view of the protocol architecture, security considerations, and product as a whole, please refer to the [Official Docs](https://docs.bando.cool).

The project is a hybrid of hardhat and forge. 
We run integration tests with hardhat and deploy and run other tests with forge.

## Pre-requisites

- Node.js v16.x
- Foundry
- Hardhat
- Solidity 0.8.20

## Installation

Install dependencies with forge
```shell
forge install
```
Install hardhat project dependencies
```shell
yarn install
```

## Compile Contracts

Compile contracts with forge
```shell
forge build [--sizes]
```

## Run Tests

Run tests with hardhat
```shell
yarn hardhat test
```

Run coverage report with hardhat
```shell
yarn hardhat coverage
```
