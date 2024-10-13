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
    /**
     * deploy registry
     */
    registry = await setupRegistry(await owner.getAddress());
    const registryAddress = await registry.getAddress();
    /**
     * deploy router
     */
    const BandoRouterV1 = await ethers.getContractFactory('BandoRouterV1');
    routerContract = await upgrades.deployProxy(BandoRouterV1, []);
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
    await v1.setTokenRegistry(DUMMY_ADDRESS);
    await v1.setEscrow(await escrow.getAddress());
    await v1.setERC20Escrow(await erc20_escrow.getAddress());
    /**
     * set dummy service
     */
    const serviceResponse = await manager.setService(
      1,
      feeAmount,
      await fulfiller.getAddress(),
      await beneficiary.getAddress(),
    );
    const response = await manager.setServiceRef(1, validRef);
  });

  describe("Configuration Specs", async () => {
    it("should set the serviceRegistry correctly", async () => {
      const registryAddress = await registry.getAddress();
      assert.equal(await v1._fulfillableRegistry(), registryAddress);
    });

    it("should set the tokenRegistry correctly", async () => {
      assert.equal(await v1._tokenRegistry(), DUMMY_ADDRESS);
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
});
