const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("ERC20TokenRegistry", function () {
  let ERC20TokenRegistry;
  let registry;
  let owner;
  let addr1;
  let addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    ERC20TokenRegistry = await ethers.getContractFactory("ERC20TokenRegistryV1");
    registry = await upgrades.deployProxy(ERC20TokenRegistry, [await owner.getAddress()]);
    await registry.waitForDeployment();
  });

  describe("Configuration Specs", function () {
    it("Should set the right owner", async function () {
      expect(await registry.owner()).to.equal(owner.address);
    });
  });

  describe("Access Control", function () {
    it("Should not allow non-owner to add token", async function () {
      await expect(registry.connect(addr1).addToken(addr2.address))
        .to.be.revertedWithCustomError(registry, 'OwnableUnauthorizedAccount');
    });

    it("Should not allow non-owner to remove token", async function () {
      await registry.addToken(addr2.address);
      await expect(registry.connect(addr1).removeToken(addr2.address))
        .to.be.revertedWithCustomError(registry, 'OwnableUnauthorizedAccount');
    });
  });

  describe("Upgradeability", function () {
    it("Should allow owner to upgrade", async function () {
      const ERC20TokenRegistryV2 = await ethers.getContractFactory("ERC20TokenRegistryV1");
      await expect(upgrades.upgradeProxy(await registry.getAddress(), ERC20TokenRegistryV2))
        .to.not.be.reverted;
    });

    it("Should not allow non-owner to upgrade", async function () {
      const ERC20TokenRegistryV2 = await ethers.getContractFactory("ERC20TokenRegistryV1", addr1);
      await expect(upgrades.upgradeProxy(await registry.getAddress(), ERC20TokenRegistryV2))
        .to.be.revertedWithCustomError(registry, 'OwnableUnauthorizedAccount');
    });
  });

  describe("Token Management", function () {
    it("Should add a token to the whitelist", async function () {
      await expect(registry.addToken(addr1.address))
        .to.emit(registry, "TokenAdded");
      expect(await registry.isTokenWhitelisted(addr1.address)).to.be.true;
    });

    it("Should emit TokenAdded event when adding a token", async function () {
      await expect(registry.addToken(addr1.address))
        .to.emit(registry, "TokenAdded")
        .withArgs(addr1.address);
    });

    it("Should remove a token from the whitelist", async function () {
      await registry.addToken(addr1.address);
      await registry.removeToken(addr1.address);
      expect(await registry.isTokenWhitelisted(addr1.address)).to.be.false;
    });

    it("Should emit TokenRemoved event when removing a token", async function () {
      await registry.addToken(addr1.address);
      await expect(registry.removeToken(addr1.address))
        .to.emit(registry, "TokenRemoved")
        .withArgs(addr1.address);
    });

    it("Should not allow adding zero address", async function () {
      await expect(registry.addToken(ethers.ZeroAddress))
        .to.be.revertedWith("ERC20TokenRegistry: Token address cannot be zero");
    });

    it("Should not allow adding already whitelisted token", async function () {
      await registry.addToken(addr1.address);
      await expect(registry.addToken(addr1.address))
        .to.be.revertedWith("ERC20TokenRegistry: Token already whitelisted");
    });

    it("Should not allow removing non-whitelisted token", async function () {
      await expect(registry.removeToken(addr1.address))
        .to.be.revertedWith("ERC20TokenRegistry: Token not whitelisted");
    });
  });
});
