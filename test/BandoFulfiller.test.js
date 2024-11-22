const { expect, assert } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { v4: uuidv4 } = require('uuid');
const { setupRegistry } = require('./utils/registryUtils');

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A"

const DUMMY_FULFILLMENTREQUEST = {
  payer: DUMMY_ADDRESS,
  weiAmount: 101,
  fiatAmount: 10,
  feeAmount: 0,
  serviceRef: "01234XYZ"
}
 
const SUCCESS_FULFILLMENT_RESULT = {
  status: 1,
  weiAmount: 100,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
}

const INVALID_FULFILLMENT_RESULT = {
  status: 3,
  weiAmount: 100,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
}

const FAILED_FULFILLMENT_RESULT = {
  status: 0,
  weiAmount: 101,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
}

let escrow;
let fulfillableContract;
let owner;
let beneficiary;
let fulfiller;
let router;
let manager;

describe("BandoFulfillableV1", () => {
  
  before(async () => {
    [owner, beneficiary, fulfiller, router, managerEOA] = await ethers.getSigners();

    // deploy the service registry
    const registryInstance = await setupRegistry(await owner.getAddress());
    registryAddress = await registryInstance.getAddress();

    // deploy manager
    const Manager = await ethers.getContractFactory('BandoFulfillmentManagerV1');
    const m = await upgrades.deployProxy(Manager, []);
    await m.waitForDeployment();
    manager = await Manager.attach(await m.getAddress());

    // deploy the fulfillable escrow contract
    const FulfillableV1 = await ethers.getContractFactory('BandoFulfillableV1');
    fulfillableContract = await upgrades.deployProxy(
      FulfillableV1,
      []
    );
    await fulfillableContract.waitForDeployment();

    escrow = FulfillableV1.attach(await fulfillableContract.getAddress())
    await escrow.setManager(await manager.getAddress());
    await registryInstance.setManager(await manager.getAddress());
    await escrow.setFulfillableRegistry(registryAddress);
    await escrow.setRouter(router.address);
    await manager.setServiceRegistry(registryAddress);
    await manager.setEscrow(await escrow.getAddress());
    await manager.setERC20Escrow(DUMMY_ADDRESS);
    const service = await manager.setService(1, 100, fulfiller.address, beneficiary.address);
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
      expect(r).to.be.equal(await router.getAddress())
    });
  });

  describe("Deposit Specs", () => {
    it("should not allow a payable deposit coming from any random address.", async () => {
      await expect(
        escrow.deposit(1, DUMMY_FULFILLMENTREQUEST, 1)
      ).to.be.revertedWith('Caller is not the router');
    });

    it("should allow a payable deposit coming from the router.", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = DUMMY_ADDRESS;
      DUMMY_FULFILLMENTREQUEST.weiAmount = ethers.parseUnits("100", "wei");
      const fromRouter = await escrow.connect(router);
      const response = await fromRouter.deposit(1, DUMMY_FULFILLMENTREQUEST, 1, { value: ethers.parseUnits("101", "wei")});
      const postBalanace = await ethers.provider.getBalance(await escrow.getAddress());
      const tx = await ethers.provider.getTransaction(response.hash);
      const BNresponse = await fulfillableContract.getDepositsFor(DUMMY_ADDRESS, 1);
      assert.equal(BNresponse.toString(), "101");
      assert.equal(postBalanace, "101");
      assert.equal(tx.value, "101");
    });

    it("should emit a DepositReceived event", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = DUMMY_ADDRESS;
      DUMMY_FULFILLMENTREQUEST.weiAmount = ethers.parseUnits("100", "wei");
      const fromRouter = await escrow.connect(router);
      await expect(
        fromRouter.deposit(1, DUMMY_FULFILLMENTREQUEST, 1, { value: ethers.parseUnits("101", "wei")})
      ).to.emit(escrow, "DepositReceived")
    });

    it("should persist unique fulfillment records on the blockchain", async () => {
      const payerRecordIds = await escrow.recordsOf(DUMMY_ADDRESS);
      const record1 = await escrow.record(payerRecordIds[0]);
      expect(record1[0]).to.be.equal(1); //record ID
      expect(record1[2]).to.be.equal(await fulfiller.getAddress()); //fulfiller
      expect(record1[4]).to.be.equal(DUMMY_ADDRESS); //payer address
      expect(record1[10]).to.be.equal(2); //status. 2 = PENDING
    });
  });

  describe("Register Fulfillment Specs", () => {
    it("should only allow to register a fulfillment via the manager", async () => {
      const fromRouter = await escrow.connect(router);
      const payerRecordIds = await fromRouter.recordsOf(DUMMY_ADDRESS);
      SUCCESS_FULFILLMENT_RESULT.id = payerRecordIds[0];
      const fromManager = await escrow.connect(managerEOA);
      await escrow.setManager(managerEOA.address);
      await expect(
        fromRouter.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT)
      ).to.be.revertedWith('Caller is not the manager');
      await expect(
        fromManager.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT)
      ).not.to.be.reverted;
      const record = await escrow.record(payerRecordIds[0]);
      expect(record[10]).to.be.equal(1);
      await escrow.setManager(await manager.getAddress());
    });

    it("should not allow to register a fulfillment with an invalid status.", async () => {
      const payerRecordIds = await escrow.recordsOf(DUMMY_ADDRESS);
      INVALID_FULFILLMENT_RESULT.id = payerRecordIds[1];
      await expect(
        escrow.registerFulfillment(1, INVALID_FULFILLMENT_RESULT)
      ).to.be.reverted;
      const record = await escrow.record(payerRecordIds[1]);
      expect(record[10]).to.be.equal(2);
    });

    it("should authorize a refund after register a fulfillment with a failed status.", async () => {
      const payerRecordIds = await escrow.recordsOf(DUMMY_ADDRESS);
      FAILED_FULFILLMENT_RESULT.id = payerRecordIds[1];
      const fromManager = await escrow.connect(managerEOA);
      await escrow.setManager(managerEOA.address);
      const r = await fromManager.registerFulfillment(1, FAILED_FULFILLMENT_RESULT);
      expect(r).not.to.be.reverted;
      expect(r).to.emit(escrow, 'RefundAuthorized').withArgs(DUMMY_ADDRESS, ethers.parseUnits('101', 'wei'));
      const record = await escrow.record(payerRecordIds[1]);
      expect(record[10]).to.be.equal(0);
      await escrow.setManager(await manager.getAddress());
    });

    it("should allow manager to withdraw a refund.", async () => {
      const fromRouter = await escrow.connect(router);
      const refunds = await escrow.getRefundsFor(DUMMY_ADDRESS, 1);
      expect(refunds.toString()).to.be.equal("101");
      const r = await fromRouter.withdrawRefund(1, DUMMY_ADDRESS);
      await expect(r).not.to.be.reverted;
      await expect(r).to.emit(escrow, 'RefundWithdrawn').withArgs(DUMMY_ADDRESS, ethers.parseUnits('101', 'wei'));
      const postBalance = await ethers.provider.getBalance(await escrow.getAddress());
      expect(postBalance).to.be.equal(101);
    });

    it("should not allow router to withdraw a refund when there is none.", async () => {
      const fromRouter = await escrow.connect(router);
      await expect(
        fromRouter.withdrawRefund(1, DUMMY_ADDRESS)
      ).to.be.revertedWith('Address is not allowed any refunds');
    });

    it("should not allow to register a fulfillment when it already was registered.", async () => {
      const payerRecordIds = await escrow.recordsOf(DUMMY_ADDRESS);
      const record1 = await escrow.record(payerRecordIds[0]);
      const fromManager = await escrow.connect(managerEOA);
      await escrow.setManager(managerEOA.address);
      const extID = record1[3];
      SUCCESS_FULFILLMENT_RESULT.id = payerRecordIds[0];
      await expect(
        fromManager.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT)
      ).to.be.revertedWith('Fulfillment already registered');
      await escrow.setManager(await manager.getAddress());
    });
  });

  describe("Beneficiary Withdraw Specs", () => {

    it("should allow manager to payout a beneficiary", async () => {
      const fromManager = await escrow.connect(managerEOA);
      await escrow.setManager(managerEOA.address);
      const preBalance = await ethers.provider.getBalance(await escrow.getAddress());
      console.log(preBalance);
      const r = await fromManager.beneficiaryWithdraw(1);
      await expect(r).not.to.be.reverted;
      const postBalance = await ethers.provider.getBalance(await escrow.getAddress());
      console.log(postBalance);
      expect(postBalance).to.be.equal(preBalance - ethers.parseUnits('100', 'wei'));
      await escrow.setManager(await manager.getAddress());
    });

    it("should not allow to pay a beneficiary with no refunds", async () => {
      const fromManager = await escrow.connect(managerEOA);
      await escrow.setManager(managerEOA.address);
      await expect(
        fromManager.beneficiaryWithdraw(1)
      ).to.be.revertedWith("There is no balance to release.");
      await escrow.setManager(await manager.getAddress());
    });
  });

  describe("Withdraw Fees Specs", () => {
    it("should not allow non-manager to withdraw fees", async () => {
      await expect(
        escrow.connect(owner).withdrawAccumulatedFees(1)
      ).to.be.revertedWith("Caller is not the manager");
    });

    it("should allow manager to withdraw fees", async () => {
      const fromManager = await escrow.connect(managerEOA);
      console.log(managerEOA.address);
      const preBalance = await ethers.provider.getBalance(await escrow.getAddress());
      console.log(await escrow.getAddress());
      console.log(preBalance);
      await escrow.setManager(managerEOA.address);
      const fees = await escrow.getNativeFeesFor(1);
      expect(fees).to.be.equal(ethers.parseUnits("1", "wei"));
      const r = await fromManager.withdrawAccumulatedFees(1);
      await expect(r).not.to.be.reverted;
      await escrow.setManager(await manager.getAddress());
    });
  });
});
