// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const fs = require("fs/promises");
/**
 * Confgure the BFP contract
 * 
 * 1. Upgrade Contracts
 * 2. Configure necessary state variables on Registry
 * 3. Configure necessary state variables on ERC20Registry
 * 4. Configure necessary state variables on Escrows
 * 5. Configure necessary state variables on Router
 * 6. Configure necessary state variables on Manager
 */
async function main() {
  const accounts = await hre.ethers.getSigners();
  console.log("Configuring BFP Contracts...");
  console.log("Account: ", accounts[0].address);
  // get current network data
  const network = await hre.network.name;
  const protocolOwner = hre.network.config.protocolOwner;
  /**
   * Setup Contracts from Json file
   */
  const deploymentPath = process.env.HH_ENVIRONMENT != 'prod' ? 
    `./deployments/${network}.${process.env.HH_ENVIRONMENT}.json` :
    `./deployments/${network}.json`;

  const data = await fs.readFile(deploymentPath, 'utf-8');
  const contracts = JSON.parse(data);

  /**
   * Upgrade Contracts
   */
  await upgradeAllContracts(contracts);
  /**
   * Setup Registry
   */
  const registry = await configureRegistry(contracts);
  /**
   * Setup ERC20Registry
   */
  await configureERC20Registry(contracts);
  /**
   * Setup ERC20Escrow
   */
  const erc20Escrow = await configureERC20Escrow(contracts);
  /**
   * Setup Escrow
   */
  const escrow = await configureEscrow(contracts);
  /**
   * Setup Router
   */
  const router = await configureRouter(contracts);
  /**
   * Setup Manager
   */
  const manager = await configureManager(contracts);

  /**
   * Transfer Ownership to Protocol Owner
   */
  await registry.transferOwnership(protocolOwner); //multisig
  console.log("Registry Ownership Transferred");
  await erc20Escrow.transferOwnership(protocolOwner); //multisig
  console.log("ERC20Escrow Ownership Transferred");
  await escrow.transferOwnership(protocolOwner); //multisig
  console.log("Escrow Ownership Transferred");
  await router.transferOwnership(protocolOwner); //multisig
  console.log("Router Ownership Transferred");
  await manager.transferOwnership(hre.network.config.managerOwner); //mpc
  console.log("Manager Ownership Transferred");
  console.log("Configuration Complete");
}

const upgradeContract = async (contracts, contractName, proxyName, implementationName) => {
  try {
    const implementationAddress = contracts[implementationName];
    if (!implementationAddress) {
      console.log(`Implementation address for ${implementationName} not found in contracts`);
      return null;
    }
    
    const Contract = await hre.ethers.getContractFactory(contractName);
    const proxyAddress = contracts[proxyName];
    if (!proxyAddress) {
      console.log(`Proxy address for ${proxyName} not found in contracts`);
      return null;
    }
    
    const contract = Contract.attach(proxyAddress);
    console.log(`Upgrading ${contractName} at ${proxyAddress} to ${implementationAddress}`);
    
    const txn = await contract.upgradeToAndCall(implementationAddress, "0x", { gasLimit: 1000000 });
    await txn.wait();
    console.log(`${contractName} Upgraded: ${txn.hash}`);
    return contract;
  } catch (error) {
    console.error(`Error upgrading ${contractName}:`, error.message);
    throw error;
  }
}

const upgradeAllContracts = async (contracts) => {
  await upgradeContract(contracts, "FulfillableRegistryV1", "FulfillableRegistryProxy", "FulfillableRegistryV1_1");
  await upgradeContract(contracts, "BandoERC20FulfillableV1", "BandoERC20FulfillableProxy", "BandoERC20FulfillableV1_2");
  await upgradeContract(contracts, "BandoFulfillableV1", "BandoFulfillableProxy", "BandoFulfillableV1_2");
  await upgradeContract(contracts, "BandoRouterV1", "BandoRouterProxy", "BandoRouterV1_1");
  await upgradeContract(contracts, "BandoFulfillmentManagerV1", "BandoFulfillmentManagerProxy", "BandoFulfillmentManagerV1_2");
}

const configureRegistry = async (contracts) => {
  const Registry = await hre.ethers.getContractFactory("FulfillableRegistryV1");
  const registryContract = Registry.attach(contracts["FulfillableRegistryProxy"]);
  // 1. Set Manager Proxy
  const txn = await registryContract.setManager(contracts["BandoFulfillmentManagerProxy"]);
  console.log(`Registry - Set Manager: ${txn.hash}`);
  return registryContract;
}

const configureERC20Registry = async (contracts) => {
  const ERC20Registry = await hre.ethers.getContractFactory("ERC20TokenRegistryV1");
  const erc20RegistryContract = ERC20Registry.attach(contracts["ERC20TokenRegistryProxy"]);
  // 1. Transfer Ownership to ManagerOwner Signer
  const txn = await erc20RegistryContract.transferOwnership(hre.network.config.tokenRegistryOwner);
}

const configureERC20Escrow = async (contracts) => {
  const ERC20Escrow = await hre.ethers.getContractFactory("BandoERC20FulfillableV1");
  const erc20EscrowContract = ERC20Escrow.attach(contracts["BandoERC20FulfillableProxy"]);
  // 1. Set Fulfillable Registry
  const txn = await erc20EscrowContract.setFulfillableRegistry(contracts["FulfillableRegistryProxy"]);
  console.log(`ERC20Escrow - Set Fulfillable Registry: ${txn.hash}`);
  // 2. Set Manager
  const mtxn = await erc20EscrowContract.setManager(contracts["BandoFulfillmentManagerProxy"]);
  console.log(`ERC20Escrow - Set Manager: ${mtxn.hash}`);
  // 3. Set Router
  const rtxn = await erc20EscrowContract.setRouter(contracts["BandoRouterProxy"]);
  console.log(`ERC20Escrow - Set Router: ${rtxn.hash}`);
  return erc20EscrowContract;
}

const configureEscrow = async (contracts) => {
  const Escrow = await hre.ethers.getContractFactory("BandoFulfillableV1");
  const EscrowContract = Escrow.attach(contracts["BandoFulfillableProxy"]);
  // 1. Set Fulfillable Registry
  const txn = await EscrowContract.setFulfillableRegistry(contracts["FulfillableRegistryProxy"]);
  console.log(`ERC20Escrow - Set Fulfillable Registry: ${txn.hash}`);
  // 2. Set Manager
  const mtxn = await EscrowContract.setManager(contracts["BandoFulfillmentManagerProxy"]);
  console.log(`ERC20Escrow - Set Manager: ${mtxn.hash}`);
  // 3. Set Router
  const rtxn = await EscrowContract.setRouter(contracts["BandoRouterProxy"]);
  console.log(`ERC20Escrow - Set Router: ${rtxn.hash}`);
  return EscrowContract;
}

const configureRouter = async (contracts) => {
  const Router = await hre.ethers.getContractFactory("BandoRouterV1");
  const routerContract = Router.attach(contracts["BandoRouterProxy"]);
  // 1. Set ERC20 Escrow
  const txn = await routerContract.setERC20Escrow(contracts["BandoERC20FulfillableProxy"]);
  console.log(`Router - Set erc20 escrow: ${txn.hash}`);
  // 2. Set escrow
  const etxn = await routerContract.setEscrow(contracts["BandoFulfillableProxy"]);
  console.log(`Router - Set escrow: ${etxn.hash}`);
  // 3. Set Fulfillable Registry
  const ftxn = await routerContract.setFulfillableRegistry(contracts["FulfillableRegistryProxy"]);
  console.log(`Router - Set Fulfillable Registry: ${ftxn.hash}`);
  // 4. Set token registry
  const ttxn = await routerContract.setTokenRegistry(contracts["ERC20TokenRegistryProxy"]);
  console.log(`Router - Set Token Registry: ${ttxn.hash}`);
  return routerContract;
}

const configureManager = async (contracts) => {
  const Manager = await hre.ethers.getContractFactory("BandoFulfillmentManagerV1");
  const managerContract = Manager.attach(contracts["BandoFulfillmentManagerProxy"]);
  // 1. Set Service Registry
  const txn = await managerContract.setServiceRegistry(contracts["FulfillableRegistryProxy"]);
  console.log(`Manager - Set Service Registry: ${txn.hash}`);
  // 2. Set Escrow
  const etxn = await managerContract.setEscrow(contracts["BandoFulfillableProxy"]);
  console.log(`Manager - Set Escrow: ${etxn.hash}`);
  // 3. Set ERC20 Escrow
  const ertxn = await managerContract.setERC20Escrow(contracts["BandoERC20FulfillableProxy"]);
  console.log(`Manager - Set ERC20 Escrow: ${ertxn.hash}`);
  return managerContract;
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
