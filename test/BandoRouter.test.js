const { ethers, upgrades } = require('hardhat');
const { expect, assert } = require('chai');
const BN = require('bn.js')
const uuid = require('uuid');
const { setupRegistry } = require('./utils/registryUtils');

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A"
const REVERT_ERROR_PREFIX = "Returned error: VM Exception while processing transaction:";


const DUMMY_FULFILLMENTREQUEST = {
  payer: DUMMY_ADDRESS,
  weiAmount: 999,
  fiatAmount: 10,
  serviceRef: "01234XYZ" //invalid CFE 
}

/**
 * this should throw an "insufficient funds" error.
 */
const DUMMY_VALID_FULFILLMENTREQUEST = {
  payer: DUMMY_ADDRESS,
  weiAmount: ethers.parseUnits("11000", "ether"),
  fiatAmount: 101,
  serviceRef: "012345678912" //valid CFE
}

const DUMMY_ERC20_FULFILLMENTREQUEST = {
  payer: DUMMY_ADDRESS,
  tokenAmount: 100,
  fiatAmount: 10,
  serviceRef: "01234XYZ",
  token: '0x0',
}

const DUMMY_VALID_ERC20_FULFILLMENTREQUEST = {
  payer: DUMMY_ADDRESS,
  tokenAmount: 100,
  fiatAmount: 10,
  serviceRef: "012345678912", //valid CFE
  token: '0x0',
}

let routerContract;
let escrow;
let erc20_escrow
let v2;
let registry;
let manager;
let validRef = uuid.v4();

describe("BandoRouterV1", function () {

  before(async () => {
    [owner, beneficiary, fulfiller] = await ethers.getSigners();
    erc20Test = await ethers.deployContract('DemoToken');
    await erc20Test.waitForDeployment();
    DUMMY_ERC20_FULFILLMENTREQUEST.token = await erc20Test.getAddress();
    DUMMY_VALID_ERC20_FULFILLMENTREQUEST.token = await erc20Test.getAddress();
    /**
     * deploy registries
     */
    registry = await setupRegistry(await owner.getAddress());
    const registryAddress = await registry.getAddress();
    tokenRegistry = await ethers.getContractFactory('ERC20TokenRegistryV1');
    const tokenRegistryInstance = await upgrades.deployProxy(tokenRegistry, [await owner.getAddress()]);
    await tokenRegistryInstance.waitForDeployment();
    tokenRegistry = await tokenRegistry.attach(await tokenRegistryInstance.getAddress());
    /**
     * deploy router
     */
    const BandoRouterV1 = await ethers.getContractFactory('BandoRouterV1');
    routerContract = await upgrades.deployProxy(BandoRouterV1, [await owner.getAddress()]);
    await routerContract.waitForDeployment();
    v1 = BandoRouterV1.attach(await routerContract.getAddress());
    /**
     * deploy manager
     */
    const Manager = await ethers.getContractFactory('BandoFulfillmentManagerV1');
    const m = await upgrades.deployProxy(Manager, []);
    await m.waitForDeployment();
    manager = await Manager.attach(await m.getAddress());
    /**
     * deploy escrows
     */
    const Escrow = await ethers.getContractFactory('BandoFulfillableV1');
    const e = await upgrades.deployProxy(Escrow, []);
    await e.waitForDeployment();
    escrow = await Escrow.attach(await e.getAddress());
    const ERC20Escrow = await ethers.getContractFactory('BandoERC20FulfillableV1');
    const erc20 = await upgrades.deployProxy(ERC20Escrow, []);
    await erc20.waitForDeployment();
    erc20_escrow = await ERC20Escrow.attach(await erc20.getAddress());
    await erc20Test.approve(await routerContract.getAddress(), 10000000000);

    /**
     * configure protocol state vars.
     */
    const feeAmount = ethers.parseUnits('0.1', 'ether');
    await escrow.setManager(await manager.getAddress());
    await escrow.setFulfillableRegistry(registryAddress);
    await escrow.setRouter(await routerContract.getAddress());
    await erc20_escrow.setManager(await manager.getAddress());
    await erc20_escrow.setFulfillableRegistry(registryAddress);
    await erc20_escrow.setRouter(await routerContract.getAddress());
    await registry.setManager(await manager.getAddress());
    await manager.setServiceRegistry(registryAddress);
    await manager.setEscrow(await escrow.getAddress());
    await manager.setERC20Escrow(await erc20_escrow.getAddress());
    await v1.setFulfillableRegistry(registryAddress);
    await v1.setTokenRegistry(await tokenRegistry.getAddress());
    await v1.setEscrow(await escrow.getAddress());
    await v1.setERC20Escrow(await erc20_escrow.getAddress());

    /**
     * set dummy service
     */
    await manager.setService(
      1,
      feeAmount,
      await fulfiller.getAddress(),
      await beneficiary.getAddress(),
    );
    await manager.setServiceRef(1, validRef);
    /**
     * set dummy token
     */
    await tokenRegistry.addToken(
      await erc20Test.getAddress(),
    );
  });

  describe("Configuration Specs", async () => {
    it("should set the serviceRegistry correctly", async () => {
      const registryAddress = await registry.getAddress();
      assert.equal(await v1._fulfillableRegistry(), registryAddress);
    });

    it("should set the tokenRegistry correctly", async () => {
      assert.equal(await v1._tokenRegistry(), await tokenRegistry.getAddress());
    });

    it("should set the escrow correctly", async () => {
      assert.equal(await v1._escrow(), await escrow.getAddress());
    });

    it("should set the erc20Escrow correctly", async () => {
      assert.equal(await v1._erc20Escrow(), await erc20_escrow.getAddress());
    });
  });

  describe("Upgradeability", async () => {
    it("should have transferred ownership to sender", async () => {
      assert.equal(await routerContract.owner(), await owner.getAddress());
    });

    it("should have upgraded to new implementation", async () => {
        const UpgradeTester = await ethers.getContractFactory('RouterUpgradeTester')
        v2 = await upgrades.upgradeProxy(await routerContract.getAddress(), UpgradeTester);
        assert.equal(await v2.getAddress(), await routerContract.getAddress());
        v2 = UpgradeTester.attach(await routerContract.getAddress());
    });
  });

  describe("Pausability", async () => {
    it("should only allow an owner to pause the contract", async () => {
      try {
        assert.equal(await v2.owner(), await owner.getAddress());
        await v2.pause({from: await beneficiary.getAddress()});
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.include(
          err.message,
          'from address mismatch',
        );
      }
      await v2.pause();
      assert.equal(await v2.paused(), true);
    });

    it("should only allow an owner to unpause the contract", async () => {
      try {
        assert.equal(await v2.owner(), await owner.getAddress());
        await v2.unpause({from: await beneficiary.getAddress()});
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.include(
          err.message,
          'from address mismatch',
        );
      }
      await v2.unpause();
      assert.equal(await v2.paused(), false);
    });
  });

  describe("Ownability", async () => {
    it("should only allow an owner for test method", async () => {
      try {
        const invalidOwner = await beneficiary.getAddress();
        const validOwner = await owner.getAddress();
        assert.notEqual(await v2.owner(), invalidOwner);
        assert.equal(await v2.owner(), validOwner)
        const response = await v2.isUpgrade({ from: invalidOwner });
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.include(
          err.message,
          'transaction from mismatch',
        );
      }
      assert.equal(await v2.isUpgrade(), true);
    });

    it("should allow owner to transfer ownership", async () => {
        const newOwner = await beneficiary.getAddress();
        const oldOwner = await owner.getAddress();
        await v2.transferOwnership(newOwner);
        assert.equal(await v2.owner(), newOwner);
        const v2AsNewOwner = v2.connect(beneficiary)
        await v2AsNewOwner.transferOwnership(oldOwner);
        assert.equal(await v2.owner(), oldOwner);
    });
  });

  describe("Route to service", async () => {
    it("should fail when service id is not set in registry", async () => {
        const v2Signer1 = v2.connect(beneficiary)
        await expect(
          v2Signer1.requestService(2, DUMMY_FULFILLMENTREQUEST, {value: ethers.parseUnits("1000", "wei")})
        ).to.be.revertedWith('FulfillableRegistry: Service does not exist');
    });

    it("should fail for when amount is zero.", async () => {
        await expect(
          v2.requestService(1, DUMMY_VALID_FULFILLMENTREQUEST, {value: 0})
        ).to.be.revertedWithCustomError(v2, 'InsufficientAmount');
    });

    it("should fail with insufficient funds error", async () => {
        const service = await registry.getService(1);
        const feeAmount = new BN(service.feeAmount.toString());
        const weiAmount = new BN(DUMMY_VALID_FULFILLMENTREQUEST.weiAmount);
        total = weiAmount.add(feeAmount)
        try {
          await v2.requestService(1, DUMMY_VALID_FULFILLMENTREQUEST, { value: total.toString() })
        } catch (err) {
          assert.include(err.message, "sender doesn't have enough funds to send tx");
        };
    });

    it("should fail with invalid Ref", async () => {
      const invalidRef = "1234567890";
      const invalidRequest = DUMMY_VALID_FULFILLMENTREQUEST;
      invalidRequest.serviceRef = invalidRef;
      await expect(
        v2.requestService(1, invalidRequest, { value: ethers.parseUnits("1", "ether") })
      ).to.be.revertedWithCustomError(v2, 'InvalidRef');
    });

    it("should route to service escrow", async () => {
      const service = await registry.getService(1);
      DUMMY_VALID_FULFILLMENTREQUEST.weiAmount = ethers.parseUnits("1", "ether");
      DUMMY_VALID_FULFILLMENTREQUEST.serviceRef = validRef;
      const feeAmount = new BN(service.feeAmount.toString());
      const weiAmount = new BN(DUMMY_VALID_FULFILLMENTREQUEST.weiAmount);
      const tx = await v2.requestService(1, DUMMY_VALID_FULFILLMENTREQUEST, { value: weiAmount.add(feeAmount).toString() });
      const receipt = await tx.wait()
      expect(receipt).to.be.an('object').that.have.property('hash');
    });
  });

  describe("ERC20 Route to service", async () => {
    it("should fail when service id is not set in registry", async () => {
        const v2Signer1 = v2.connect(beneficiary);
        await expect(
          v2Signer1.requestERC20Service(2, DUMMY_ERC20_FULFILLMENTREQUEST)
        ).to.be.revertedWith('FulfillableRegistry: Service does not exist');
    });

    it("should fail for when amount is zero.", async () => {
      DUMMY_VALID_ERC20_FULFILLMENTREQUEST.tokenAmount = 0;
        await expect(
          v2.requestERC20Service(1, DUMMY_VALID_ERC20_FULFILLMENTREQUEST)
        ).to.be.revertedWithCustomError(v2, 'InsufficientAmount');
    });

    it("should fail when payer has not enough token balance", async () => {
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.payer = await fulfiller.getAddress();
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.serviceRef = validRef;
        const v2Fulfiller = v2.connect(fulfiller);
        const ercFulfiller = erc20Test.connect(fulfiller);
        await ercFulfiller.approve(await routerContract.getAddress(), 100);
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.tokenAmount = 100;
        await expect(v2Fulfiller.requestERC20Service(1, DUMMY_VALID_ERC20_FULFILLMENTREQUEST))
          .to.have.revertedWith('BandoRouterV1: Insufficient balance')
    });

    it("should fail when payer has not enough token allowance", async () => {
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.payer = await fulfiller.getAddress();
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.serviceRef = validRef;
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.tokenAmount = 1000;
        const v2Fulfiller = v2.connect(fulfiller);
        await erc20Test.transfer(await fulfiller.getAddress(), 1000);
        await expect(v2Fulfiller.requestERC20Service(1, DUMMY_VALID_ERC20_FULFILLMENTREQUEST))
          .to.have.revertedWithCustomError(erc20Test, 'ERC20InsufficientAllowance')
          .withArgs(await routerContract.getAddress(), 100, 1000);
    });

    it("should fail with invalid Ref", async () => {
      const invalidRef = "1234567890";
      const invalidRequest = DUMMY_ERC20_FULFILLMENTREQUEST;
      invalidRequest.serviceRef = invalidRef;
      await expect(
        v2.requestERC20Service(1, invalidRequest)
      ).to.be.revertedWithCustomError(v2, 'InvalidRef');
    });

    it("should route to service escrow", async () => {
      DUMMY_VALID_ERC20_FULFILLMENTREQUEST.payer = await owner.getAddress();
      DUMMY_VALID_ERC20_FULFILLMENTREQUEST.tokenAmount = 10000;
      DUMMY_VALID_ERC20_FULFILLMENTREQUEST.token = await erc20Test.getAddress();
      DUMMY_VALID_ERC20_FULFILLMENTREQUEST.serviceRef = validRef;
      const tx = await v2.requestERC20Service(1, DUMMY_VALID_ERC20_FULFILLMENTREQUEST);
      const receipt = await tx.wait()
      expect(receipt).to.be.an('object').that.have.property('hash');
      expect(receipt).to.be.an('object').that.have.property('status');
      expect(receipt.status).to.be.equal(1);
      expect(tx).to.emit(v2, 'ERC20ServiceRequested');
    });
  });
});
