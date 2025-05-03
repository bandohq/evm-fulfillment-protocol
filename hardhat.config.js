require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require("@nomicfoundation/hardhat-foundry");
require("dotenv").config();
/** @type import('hardhat/config').HardhatUserConfig */

const createConfig = (env) => {
  let signers;
  if (env !== 'prod') {
    signers = {
      managerOwner: process.env.MANAGER_OWNER,
      protocolOwner: process.env.PROTOCOL_OWNER,
      tokenRegistryOwner: process.env.TOKEN_REGISTRY_OWNER,
      fulfillerAddress: process.env.FULFILLER_ADDRESS,
    }
  } else {
    signers = {
      managerOwner: process.env.DEV_SIGNER_ADDRESS,
      protocolOwner: process.env.DEV_SIGNER_ADDRESS,
      tokenRegistryOwner: process.env.DEV_SIGNER_ADDRESS,
      fulfillerAddress: process.env.DEV_SIGNER_ADDRESS,
    }
  }
  if(env != 'test') {
    const privateKey = env === 'prod' ? process.env.PRIVATE_KEY_PRODUCTION : process.env.PRIVATE_KEY;
    return {
      solidity: "0.8.28",
      evm_version: "paris",
      networks: {
        arbitrum: {
          url: process.env.ETH_NODE_URI_ARBITRUM,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.ARBITRUM_AGREGGATOR_ADDRESS
        },
        celo: {
          url: process.env.ETH_NODE_URI_CELO,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.CELO_AGREGGATOR_ADDRESS
        },
        base: {
          url: process.env.ETH_NODE_URI_BASE,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.BASE_AGREGGATOR_ADDRESS
        },
        scroll: {
          url: process.env.ETH_NODE_URI_SCROLL,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.SCROLL_AGREGGATOR_ADDRESS
        },
        polygon: {
          url: process.env.ETH_NODE_URI_POLYGON,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.POLYGON_AGREGGATOR_ADDRESS
        },
        bsc: {
          url: process.env.ETH_NODE_URI_BSC,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.BSC_AGREGGATOR_ADDRESS
        },
        mantle: {
          url: process.env.ETH_NODE_URI_MANTLE,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.MANTLE_AGREGGATOR_ADDRESS
        },
        optimism: {
          url: process.env.ETH_NODE_URI_OPTIMISM,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.OPTIMISM_AGREGGATOR_ADDRESS
        },
        avalanche: {
          url: process.env.ETH_NODE_URI_AVALANCHE,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.AVALANCHE_AGREGGATOR_ADDRESS
        },
        polygonzkevm: {
          url: process.env.ETH_NODE_URI_POLYGONZKEVM,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.POLYGONZKEVM_AGREGGATOR_ADDRESS
        },
        blast: {
          url: process.env.ETH_NODE_URI_BLAST,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.BLAST_AGREGGATOR_ADDRESS
        },
        metis: {
          url: process.env.ETH_NODE_URI_METIS,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.METIS_AGREGGATOR_ADDRESS
        },
        linea: {
          url: process.env.ETH_NODE_URI_LINEA,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.LINEA_AGREGGATOR_ADDRESS
        },
        gnosis: {
          url: process.env.ETH_NODE_URI_GNOSIS,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.GNOSIS_AGREGGATOR_ADDRESS
        },
        unichain: {
          url: process.env.ETH_NODE_URI_UNICHAIN,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.UNICHAIN_AGREGGATOR_ADDRESS
        },
        berachain: {
          url: process.env.ETH_NODE_URI_BERACHAIN,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.BERACHAIN_AGREGGATOR_ADDRESS
        },
        abstract: {
          url: process.env.ETH_NODE_URI_ABSTRACT,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.ABSTRACT_AGREGGATOR_ADDRESS
        },
        mode: {
          url: process.env.ETH_NODE_URI_MODE,
          accounts: [privateKey],
          protocolOwner: signers.protocolOwner,
          managerOwner: signers.managerOwner,
          tokenRegistryOwner: signers.tokenRegistryOwner,
          fulfillerAddress: signers.fulfillerAddress,
          aggregatorAddress: process.env.MODE_AGREGGATOR_ADDRESS
        },
        // Add more networks here
      }
    }
  } else {
    return {
      solidity: "0.8.28",
      evm_version: "paris",
      networks: {
        hardhat: {
          chainId: 1337
        }
      }
    }
  }
}

module.exports = createConfig(process.env.HH_ENVIRONMENT);
