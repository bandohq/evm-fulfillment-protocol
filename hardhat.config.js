require("@nomicfoundation/hardhat-toolbox");
require('@openzeppelin/hardhat-upgrades');
require("@nomicfoundation/hardhat-foundry");
require("dotenv").config();
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",

  networks: {
    arbitrum: {
      url: process.env.ETH_NODE_URI_ARBITRUM,
      accounts: [process.env.PRIVATE_KEY],
      protocolOwner: 'tbd',
      managerOwner: 'tbd',
      tokenRegistryOwner: 'tbd',
    }
  }
};
