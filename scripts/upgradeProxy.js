//Hardhat script that upgrades a proxy contract

const { ethers, upgrades } = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");

async function main(contractName, upgradeContractName) {
  const provider = ethers.provider;
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Contract to upgrade:", contractName);
  console.log("Upgrade contract:", upgradeContractName);
  const contract = await ethers.getContractFactory(contractName);
  const upgradeContract = await ethers.getContractFactory(upgradeContractName);
  const upgrade = await upgrades.upgradeProxy(await contract.getAddress(), upgradeContract);
  await upgrade.waitForDeployment();
  console.log("Proxy upgraded to:", upgrade.target);
  console.log("Implementation address:", await getImplementationAddress(provider, upgrade.target));
}

main(process.argv[2], process.argv[3]).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
