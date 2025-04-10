require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require("@nomicfoundation/hardhat-foundry");
require("dotenv").config();
/** @type import('hardhat/config').HardhatUserConfig */

const createConfig = (env) => {
  if(env != 'test') {
    const privateKey = env === 'prod' ? process.env.PRIVATE_KEY_PRODUCTION : process.env.PRIVATE_KEY;
    return {
      solidity: "0.8.28",
      evm_version: "paris",
      networks: {
        arbitrum: {
          url: process.env.ETH_NODE_URI_ARBITRUM,
          accounts: [privateKey],
          protocolOwner: process.env.PROTOCOL_OWNER,
          managerOwner: process.env.MANAGER_OWNER,
          tokenRegistryOwner: process.env.TOKEN_REGISTRY_OWNER,
        },
        celo: {
          url: process.env.ETH_NODE_URI_CELO,
          accounts: [privateKey],
          protocolOwner: process.env.PROTOCOL_OWNER,
          managerOwner: process.env.MANAGER_OWNER,
          tokenRegistryOwner: process.env.TOKEN_REGISTRY_OWNER,
        },
        base: {
          url: process.env.ETH_NODE_URI_BASE,
          accounts: [privateKey],
          protocolOwner: process.env.PROTOCOL_OWNER,
          managerOwner: process.env.MANAGER_OWNER,
          tokenRegistryOwner: process.env.TOKEN_REGISTRY_OWNER,
        }
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
