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
let testSwapper;
let owner;
let beneficiary;
let fulfiller;
let router;
let manager;

describe("BandoFulfillableV1", () => {
  
  before(async () => {
    [owner, beneficiary, fulfiller, router, managerEOA] = await ethers.getSigners();
    stableToken = await ethers.deployContract('DemoStableToken');
    await stableToken.waitForDeployment();
    // deploy the service registry
    const registryInstance = await setupRegistry(await owner.getAddress());
    registryAddress = await registryInstance.getAddress();

    // deploy manager
    const Manager = await ethers.getContractFactory('BandoFulfillmentManagerV1_2');
    const m = await upgrades.deployProxy(Manager, [await owner.getAddress()]);
    await m.waitForDeployment();
    manager = await Manager.attach(await m.getAddress());

    // deploy the fulfillable escrow contract
    const FulfillableV1 = await ethers.getContractFactory('BandoFulfillableV1');
    fulfillableContract = await upgrades.deployProxy(
      FulfillableV1,
      [await owner.getAddress()]
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
    await manager.setService(1, 100, fulfiller.address, beneficiary.address);
    testSwapper = await ethers.deployContract('TestNativeSwapAggregator');
    await testSwapper.waitForDeployment();
    await escrow.setManager(managerEOA.address);
    await expect(manager.addAggregator(await testSwapper.getAddress()))
      .to.emit(manager, 'AggregatorAdded')
      .withArgs(await testSwapper.getAddress());
    await expect(await manager.isAggregator(await testSwapper.getAddress())).to.be.true;
    await escrow.setManager(await manager.getAddress());
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
      await expect(escrow.deposit(1, DUMMY_FULFILLMENTREQUEST, 1))
        .to.be.revertedWithCustomError(escrow, 'InvalidRouter')
        .withArgs(owner.address);
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
      await expect(fromRouter.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT))
        .to.be.revertedWithCustomError(escrow, 'InvalidManager')
        .withArgs(router.address);
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
      await expect(fromRouter.withdrawRefund(1, DUMMY_ADDRESS))
        .to.be.revertedWithCustomError(escrow, 'NoRefunds')
        .withArgs(DUMMY_ADDRESS, 1);
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
      ).to.be.revertedWithCustomError(escrow, 'FulfillmentAlreadyRegistered');
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
       ).to.be.revertedWithCustomError(escrow, 'NoBalanceToRelease');
      await escrow.setManager(await manager.getAddress());
    });
  });

  describe("Withdraw Fees Specs", () => {
    it("should not allow non-manager to withdraw fees", async () => {
      await expect(escrow.connect(owner).withdrawAccumulatedFees(1))
        .to.be.revertedWithCustomError(escrow, 'InvalidManager')
        .withArgs(owner.address);
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

  describe("Upgradeability", async () => {
    it("should be able to upgrade to v1.1", async () => {
      const FulfillableV1_1 = await ethers.getContractFactory('BandoFulfillableV1_1');
      const newFulfillable = await upgrades.upgradeProxy(await fulfillableContract.getAddress(), FulfillableV1_1);
      escrow = FulfillableV1_1.attach(await newFulfillable.getAddress());
      const b = await escrow._manager();
      expect(b).to.be.equal(await manager.getAddress());
    });

    it("should be able to upgrade to v1.2", async () => {
      const FulfillableV1_2 = await ethers.getContractFactory('BandoFulfillableV1_2');
      const newFulfillable = await upgrades.upgradeProxy(await fulfillableContract.getAddress(), FulfillableV1_2);
      escrow = FulfillableV1_2.attach(await newFulfillable.getAddress());
      const b = await escrow._manager();
      expect(b).to.be.equal(await manager.getAddress());
    });
  });

  describe("Swap to stablecoin specs", () => {
    it("should allow a payable deposit coming from the router", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = DUMMY_ADDRESS;
      DUMMY_FULFILLMENTREQUEST.weiAmount = ethers.parseUnits("100", "wei");
      const fromRouter = await escrow.connect(router);
      await expect(fromRouter.deposit(1, DUMMY_FULFILLMENTREQUEST, 1, { value: ethers.parseUnits("101", "wei")}))
        .to.emit(escrow, "DepositReceived")
    });

    it("should allow to swap to stablecoin", async () => {
      // Transfer tokens to the swapper to mock the swap
      await stableToken.transfer(await testSwapper.getAddress(), ethers.parseUnits('100000', 18));
      await escrow.setManager(managerEOA.address);
      const records = await escrow.recordsOf(DUMMY_ADDRESS);
      const recordId = records[records.length - 1];
      // Register successful fulfillment
      const SUCCESS_RESULT = {
        id: recordId,
        status: 1, // SUCCESS
        externalID: uuidv4(), 
        receiptURI: "https://example.com"
      };
      const fromManager = await escrow.connect(managerEOA);
      await fromManager.registerFulfillment(1, SUCCESS_RESULT);
      const CallData = testSwapper.interface.encodeFunctionData("swapNative", [
        await stableToken.getAddress(),
        ethers.parseUnits('101', 'wei')
      ]);
      const swapData = {
        callData: CallData,
        toToken: await stableToken.getAddress(),
        amount: ethers.parseUnits('101', 'wei'),
        feeAmount: ethers.parseUnits('1', 'wei'),
        callTo: await testSwapper.getAddress(),
      };
      await expect(escrow
        .connect(managerEOA)
        .swapPoolsToStable(1, swapData)
      ).to.emit(escrow, "PoolsSwappedToStable");
      expect(await escrow.getNativeFeesFor(1)).to.be.equal(0);
      expect(await escrow._stableAccumulatedFees(1, await stableToken.getAddress())).to.be.equal(2);
      await escrow.setManager(await manager.getAddress());
    });
  });

  describe("Beneficiary Withdraw Stable Specs", () => {
    it("should allow manager to withdraw the beneficiary's available balance to release (fulfilled with success)", async () => {
      const fromManager = await escrow.connect(managerEOA);
      await escrow.setManager(managerEOA.address);
      const preBalance = await stableToken.balanceOf(await escrow.getAddress());
      expect(preBalance).to.be.equal(202); // double the amount per the swap test contract
      await fromManager.beneficiaryWithdrawStable(1, await stableToken.getAddress());
      const stableBalance = await stableToken.balanceOf(await escrow.getAddress());
      expect(stableBalance).to.be.equal(2);
      await escrow.setManager(await manager.getAddress());
    });

    it("should revert if there is no balance to release", async () => {
      const fromManager = await escrow.connect(managerEOA);
      await escrow.setManager(managerEOA.address);
      await expect(fromManager.beneficiaryWithdrawStable(1, await stableToken.getAddress()))
        .to.be.revertedWithCustomError(escrow, 'NoBalanceToRelease');
      await escrow.setManager(await manager.getAddress());
    });

    it("should not allow to withdraw the beneficiary's available balance to release (fulfilled with success) if the fulfiller is not the manager", async () => {
      await expect(escrow.beneficiaryWithdrawStable(1, await stableToken.getAddress()))
        .to.be.revertedWithCustomError(escrow, 'InvalidCaller');
      await escrow.setManager(await manager.getAddress());
    });
  });

  describe("Withdraw Accumulated Fees Stable Specs", () => {
    it("should not allow non-manager to withdraw the accumulated fees", async () => {
      await expect(escrow.connect(owner).withdrawAccumulatedFeesStable(1, await stableToken.getAddress()))
        .to.be.revertedWithCustomError(escrow, 'InvalidCaller');
    });

    it("should allow manager to withdraw the accumulated fees", async () => {
      const fromManager = await escrow.connect(managerEOA);
      await escrow.setManager(managerEOA.address);
      const preBalance = await stableToken.balanceOf(await escrow.getAddress());
      expect(preBalance).to.be.equal(2);
      await fromManager.withdrawAccumulatedFeesStable(1, await stableToken.getAddress())
      const postBalance = await stableToken.balanceOf(await escrow.getAddress());
      expect(postBalance).to.be.equal(0);
      await escrow.setManager(await manager.getAddress());
    });
  });
});
