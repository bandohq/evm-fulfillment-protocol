const { expect, assert } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { v4: uuidv4 } = require('uuid');
const { setupRegistry } = require('./utils/registryUtils');

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A"

const DUMMY_FULFILLMENTREQUEST = {
  payer: DUMMY_ADDRESS,
  tokenAmount: 100,
  fiatAmount: 10,
  serviceRef: uuidv4(),
  token: ''
}
 
const SUCCESS_FULFILLMENT_RESULT = {
  status: 1,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
}

const INVALID_FULFILLMENT_RESULT = {
  status: 3,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
}

const FAILED_FULFILLMENT_RESULT = {
  status: 0,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
}

let escrow;
let fulfillableContract;
let owner;
let router;
let erc20Test;
let registryAddress;
let manager;
let routerContract;

describe("BandoERC20FulfillableV1", () => {
  
  before(async () => {
    [owner, beneficiary, fulfiller, router, managerEOA] = await ethers.getSigners();
    erc20Test = await ethers.deployContract('DemoToken');
    await erc20Test.waitForDeployment();

    /**
    * deploy registries
    */
    const registryInstance = await setupRegistry(await owner.getAddress());
    registryAddress = await registryInstance.getAddress();
    registry = registryInstance;
    tokenRegistry = await ethers.getContractFactory('ERC20TokenRegistry');
    const tokenRegistryInstance = await upgrades.deployProxy(tokenRegistry, []);
    await tokenRegistryInstance.waitForDeployment();
    tokenRegistry = await tokenRegistry.attach(await tokenRegistryInstance.getAddress());

    // deploy manager
    const Manager = await ethers.getContractFactory('BandoFulfillmentManagerV1');
    const m = await upgrades.deployProxy(Manager, []);
    await m.waitForDeployment();
    manager = await Manager.attach(await m.getAddress());

    // deploy the fulfillable escrow contract
    const FulfillableV1 = await ethers.getContractFactory('BandoERC20FulfillableV1');
    fulfillableContract = await upgrades.deployProxy(
      FulfillableV1,
      []
    );
    await fulfillableContract.waitForDeployment();
    /**
     * deploy router
     */
    const BandoRouterV1 = await ethers.getContractFactory('BandoRouterV1');
    routerContract = await upgrades.deployProxy(BandoRouterV1, []);
    await routerContract.waitForDeployment();
    routerContract = BandoRouterV1.attach(await routerContract.getAddress());

    await erc20Test.approve(await routerContract.getAddress(), ethers.parseUnits('1000000', 18));
    escrow = FulfillableV1.attach(await fulfillableContract.getAddress())
    taddr = await erc20Test.getAddress();
    DUMMY_FULFILLMENTREQUEST.token = taddr;
    SUCCESS_FULFILLMENT_RESULT.token = taddr;
    await escrow.setManager(await manager.getAddress());
    await registryInstance.setManager(await manager.getAddress());
    await escrow.setFulfillableRegistry(registryAddress);
    await escrow.setRouter(await routerContract.getAddress());
    await manager.setServiceRegistry(registryAddress);
    await manager.setEscrow(DUMMY_ADDRESS);
    await manager.setERC20Escrow(await escrow.getAddress());
    await routerContract.setFulfillableRegistry(registryAddress);
    await routerContract.setTokenRegistry(await tokenRegistry.getAddress());
    await routerContract.setEscrow(DUMMY_ADDRESS);
    await routerContract.setERC20Escrow(await escrow.getAddress());
    await manager.setService(1, 0, fulfiller.address, beneficiary.address);
    await manager.setServiceRef(1, DUMMY_FULFILLMENTREQUEST.serviceRef);
    await tokenRegistry.addToken(taddr);
  });

  describe("Configuration Specs", async () => {
    it("should set the serviceRegistry correctly", async () => {
      const b = await escrow._fulfillableRegistry();
      expect(b).to.be.a.properAddress;
      expect(b).to.be.equal(registryAddress);
    });

    it("should set the manager and router correctly", async () => {
      const m = await escrow._manager();
      const r = await escrow._router();
      expect(m).to.be.a.properAddress
      expect(r).to.be.a.properAddress
      expect(m).to.be.equal(await manager.getAddress())
      expect(r).to.be.equal(await routerContract.getAddress())
    });
  });

  describe("Deposit Specs", () => {
    it("should not allow a payable deposit coming from any random address.", async () => {
      await expect(
        escrow.depositERC20(1, DUMMY_FULFILLMENTREQUEST)
      ).to.be.revertedWith('Caller is not the router');
    });

    it("should not allow a payable deposit from an unexistent service", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = await owner.getAddress();
      DUMMY_FULFILLMENTREQUEST.tokenAmount = ethers.parseUnits('1000', 18);
      DUMMY_FULFILLMENTREQUEST.token = await erc20Test.getAddress();
      await expect(
        routerContract.requestERC20Service(2, DUMMY_FULFILLMENTREQUEST)
      ).to.be.revertedWith('FulfillableRegistry: Service does not exist');
    });

    it("should not allow a payable deposit from an unexistent token", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = await owner.getAddress();
      DUMMY_FULFILLMENTREQUEST.tokenAmount = ethers.parseUnits('1000', 18);
      DUMMY_FULFILLMENTREQUEST.token = DUMMY_ADDRESS;
      await expect(
        routerContract.requestERC20Service(1, DUMMY_FULFILLMENTREQUEST)
      ).to.have.revertedWithCustomError(routerContract, 'UnsupportedToken')
        .withArgs(DUMMY_ADDRESS);
    });

    it("should allow a payable deposit coming from the router.", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = await owner.getAddress();
      DUMMY_FULFILLMENTREQUEST.tokenAmount = ethers.parseUnits('1000', 18);
      DUMMY_FULFILLMENTREQUEST.token = await erc20Test.getAddress();
      const response = await routerContract.requestERC20Service(1, DUMMY_FULFILLMENTREQUEST);
      const BNresponse = await escrow.getERC20DepositsFor(DUMMY_FULFILLMENTREQUEST.token, DUMMY_FULFILLMENTREQUEST.payer, 1);
      assert.equal(BNresponse.toString(), "1000000000000000000000");
      const erc20PostBalance = await erc20Test.balanceOf(await escrow.getAddress());
      expect(erc20PostBalance).to.be.equal("1000000000000000000000");

      const response2 = await routerContract.requestERC20Service(1, DUMMY_FULFILLMENTREQUEST);
      const BNresponse2 = await escrow.getERC20DepositsFor(DUMMY_FULFILLMENTREQUEST.token, DUMMY_FULFILLMENTREQUEST.payer, 1);
      assert.equal(BNresponse2.toString(), "2000000000000000000000");
      const erc20PostBalance2 = await erc20Test.balanceOf(await escrow.getAddress());
      expect(erc20PostBalance2).to.be.equal("2000000000000000000000");
    });

    it("should emit a ERC2ODepositReceived event", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = owner;
      DUMMY_FULFILLMENTREQUEST.tokenAmount = ethers.parseUnits("100", 18);
      const fromRouter = await escrow.connect(router);
      await expect(
        routerContract.requestERC20Service(1, DUMMY_FULFILLMENTREQUEST)
      ).to.emit(escrow, "ERC20DepositReceived")
    });

    it("should persist unique fulfillment records on the blockchain", async () => {
      const payerRecordIds = await escrow.recordsOf(owner);
      const record1 = await escrow.record(payerRecordIds[0]);
      expect(record1[0]).to.be.equal(1); //record ID
      expect(record1[2]).to.be.equal(await fulfiller.getAddress()); //fulfiller
      expect(record1[3]).to.be.equal(await erc20Test.getAddress()); //token
      expect(record1[5]).to.be.equal(owner); //payer address
      expect(record1[11]).to.be.equal(2); //status. 2 = PENDING
    });
  });

  describe("Register Fulfillment Specs", () => {
    it("should only allow to register a fulfillment via the manager", async () => {
      const fromRouter = await escrow.connect(router);
      const payerRecordIds = await fromRouter.recordsOf(owner);
      SUCCESS_FULFILLMENT_RESULT.id = payerRecordIds[0];
      await escrow.setManager(managerEOA.address);
      const fromManager = await escrow.connect(managerEOA);
      await expect(
        fromRouter.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT)
      ).to.be.revertedWith('Caller is not the manager');
      await expect(
        fromManager.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT)
      ).not.to.be.reverted;
      await escrow.setManager(await manager.getAddress());
      const record = await escrow.record(payerRecordIds[0]);
      expect(record[11]).to.be.equal(1);
    });

    it("should not allow to register a fulfillment with an invalid status.", async () => {
      const payerRecordIds = await escrow.recordsOf(owner);
      INVALID_FULFILLMENT_RESULT.id = payerRecordIds[1];
      await expect(
        escrow.registerFulfillment(1, INVALID_FULFILLMENT_RESULT)
      ).to.be.reverted;
      const record = await escrow.record(payerRecordIds[1]);
      expect(record[11]).to.be.equal(2);
    });

    it("should authorize a refund after register a fulfillment with a failed status.", async () => {
      const payerRecordIds = await escrow.recordsOf(owner);
      FAILED_FULFILLMENT_RESULT.id = payerRecordIds[1];
      await escrow.setManager(managerEOA.address);
      const fromManager = await escrow.connect(managerEOA);
      const r = fromManager.registerFulfillment(1, FAILED_FULFILLMENT_RESULT);
      await expect(r).not.to.be.reverted;
      await expect(r).to.emit(escrow, 'ERC20RefundAuthorized').withArgs(owner, ethers.parseUnits('1000', 18));
      const record = await escrow.record(payerRecordIds[1]);
      await escrow.setManager(await manager.getAddress());
      expect(record[11]).to.be.equal(0);
    });

    it("should allow manager to withdraw a refund.", async () => {
      await escrow.setManager(managerEOA.address);
      const fromManager = await escrow.connect(managerEOA);
      const r = fromManager.withdrawERC20Refund(1, erc20Test, owner);
      await expect(r).not.to.be.reverted;
      await expect(r).to.emit(escrow, 'ERC20RefundWithdrawn').withArgs(erc20Test, owner, ethers.parseUnits('1000', 18));
      await escrow.setManager(await manager.getAddress());
    });

    it("should not allow manager to withdraw a refund when there is none.", async () => {
      await escrow.setManager(managerEOA.address);
      const fromManager = await escrow.connect(managerEOA);
      await expect(
       fromManager.withdrawERC20Refund(1, erc20Test, owner)
      ).to.be.revertedWith('Address is not allowed any refunds');
      await escrow.setManager(await manager.getAddress());
      // check balances post withdraw
      const erc20PostBalance = await erc20Test.balanceOf(await escrow.getAddress());
    });

    it("should not allow to register a fulfillment when it already was registered.", async () => {
      await escrow.setManager(managerEOA.address);
      const fromManager = await escrow.connect(managerEOA);
      const payerRecordIds = await escrow.recordsOf(owner);
      const record1 = await escrow.record(payerRecordIds[0]);
      const extID = record1[3];
      SUCCESS_FULFILLMENT_RESULT.id = payerRecordIds[0];
      await expect(
        fromManager.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT)
      ).to.be.revertedWith('Fulfillment already registered');
    });
  });

  describe("Beneficiary Withdrawal Specs", () => {
    it("should allow the beneficiary to withdraw the funds", async () => {
      const fromManager = await escrow.connect(managerEOA);
      const preBalance = await erc20Test.balanceOf(await beneficiary.getAddress());
      const r = await fromManager.beneficiaryWithdraw(1, erc20Test);
      await expect(r).not.to.be.reverted;
      await expect(r).to.emit(erc20Test, 'Transfer')
        .withArgs(await escrow.getAddress(), await beneficiary.getAddress(), ethers.parseUnits('1000', 18));
      const postBalance = await erc20Test.balanceOf(await beneficiary.getAddress());
      expect(postBalance).to.be.equal(preBalance + ethers.parseUnits('1000', 18));
    });

    it("should only be allowed by the manager", async () => {
      const fromRouter = await escrow.connect(router);
      await expect(
        fromRouter.beneficiaryWithdraw(1, erc20Test)
      ).to.be.revertedWith('Caller is not the manager');
    });

    it("should not allow the beneficiary to withdraw the funds when there is none", async () => {
      const fromManager = await escrow.connect(managerEOA);
      await expect(
        fromManager.beneficiaryWithdraw(1, erc20Test)
      ).to.be.revertedWith('There is no balance to release.');
    });
  });
});
