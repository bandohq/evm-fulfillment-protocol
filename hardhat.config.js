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
      networks: {
        arbitrum: {
          url: process.env.ETH_NODE_URI_ARBITRUM,
          accounts: [privateKey],
          protocolOwner: 'tbd',
          managerOwner: 'tbd',
          tokenRegistryOwner: 'tbd',
        }
        // Add more networks here
      }
    }
  } else {
    return {
      solidity: "0.8.28",
      networks: {
        hardhat: {
          chainId: 1337
        }
      }
    }
  }
}

module.exports = createConfig(process.env.ENVIRONMENT);
