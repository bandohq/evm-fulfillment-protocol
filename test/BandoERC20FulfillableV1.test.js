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
let stableToken;
let testSwapper;


describe("BandoERC20FulfillableV1", () => {
  
  before(async () => {
    [owner, beneficiary, fulfiller, router, managerEOA] = await ethers.getSigners();
    erc20Test = await ethers.deployContract('DemoToken');
    await erc20Test.waitForDeployment();
    stableToken = await ethers.deployContract('DemoStableToken');
    await stableToken.waitForDeployment();
    /**
    * deploy registries
    */
    const registryInstance = await setupRegistry(await owner.getAddress());
    registryAddress = await registryInstance.getAddress();
    registry = registryInstance;
    tokenRegistry = await ethers.getContractFactory('ERC20TokenRegistryV1');
    const tokenRegistryInstance = await upgrades.deployProxy(tokenRegistry, [await owner.getAddress()]);
    await tokenRegistryInstance.waitForDeployment();
    tokenRegistry = await tokenRegistry.attach(await tokenRegistryInstance.getAddress());

    // deploy manager
    const Manager = await ethers.getContractFactory('BandoFulfillmentManagerV1_2');
    const m = await upgrades.deployProxy(Manager, [await owner.getAddress()]);
    await m.waitForDeployment();
    manager = await Manager.attach(await m.getAddress());

    // deploy the fulfillable escrow contract
    const FulfillableV1 = await ethers.getContractFactory('BandoERC20FulfillableV1');
    fulfillableContract = await upgrades.deployProxy(
      FulfillableV1,
      [await owner.getAddress()]
    );
    await fulfillableContract.waitForDeployment();
    /**
     * deploy router
     */
    const BandoRouterV1 = await ethers.getContractFactory('BandoRouterV1');
    routerContract = await upgrades.deployProxy(BandoRouterV1, [await owner.getAddress()]);
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
    await manager.setService(1, 100, fulfiller.address, beneficiary.address);
    await manager.setServiceRef(1, DUMMY_FULFILLMENTREQUEST.serviceRef);
    await tokenRegistry.addToken(taddr, 10);
  });


  describe("Upgradeability Specs", async () => {
    it("should be able to upgrade to v1.1", async () => {
      const FulfillableV1_1 = await ethers.getContractFactory('BandoERC20FulfillableV1_1');
      const upgraded = await upgrades.upgradeProxy(await escrow.getAddress(), FulfillableV1_1);
      escrow = FulfillableV1_1.attach(await upgraded.getAddress());
      expect(await escrow.getAddress()).to.be.a.properAddress;
      expect(await escrow._manager()).to.equal(await manager.getAddress());
    });
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
      await expect(escrow.depositERC20(1, DUMMY_FULFILLMENTREQUEST, 1))
        .to.be.revertedWithCustomError(escrow, 'InvalidAddress')
        .withArgs(owner.address);
    });

    it("should not allow a payable deposit from an unexistent service", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = await owner.getAddress();
      DUMMY_FULFILLMENTREQUEST.tokenAmount = ethers.parseUnits('1000', 18);
      DUMMY_FULFILLMENTREQUEST.token = await erc20Test.getAddress();
      await expect(routerContract.requestERC20Service(2, DUMMY_FULFILLMENTREQUEST))
        .to.be.revertedWithCustomError(registry, 'ServiceDoesNotExist')
        .withArgs(2);
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
      assert.equal(BNresponse.toString(), "1011000000000000000000");
      const erc20PostBalance = await erc20Test.balanceOf(await escrow.getAddress());
      expect(erc20PostBalance).to.be.equal("1011000000000000000000");

      const response2 = await routerContract.requestERC20Service(1, DUMMY_FULFILLMENTREQUEST);
      const BNresponse2 = await escrow.getERC20DepositsFor(DUMMY_FULFILLMENTREQUEST.token, DUMMY_FULFILLMENTREQUEST.payer, 1);
      assert.equal(BNresponse2.toString(), "2022000000000000000000");
      const erc20PostBalance2 = await erc20Test.balanceOf(await escrow.getAddress());
      expect(erc20PostBalance2).to.be.equal("2022000000000000000000");
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
      await expect(fromRouter.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT))
        .to.be.revertedWithCustomError(escrow, 'InvalidAddress')
        .withArgs(router.address);
      await expect(
        fromManager.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT)
      ).not.to.be.reverted;
      let fees = await escrow.getERC20FeesFor(erc20Test, 1);
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
      await expect(r).to.emit(escrow, 'ERC20RefundAuthorized').withArgs(owner, ethers.parseUnits('1011', 18));
      const record = await escrow.record(payerRecordIds[1]);
      await escrow.setManager(await manager.getAddress());
      expect(record[11]).to.be.equal(0);
    });

    it("should allow router to withdraw a refund.", async () => {
      await escrow.setRouter(router.address);
      const fromRouter = await escrow.connect(router);
      const r = fromRouter.withdrawERC20Refund(1, erc20Test, owner);
      await expect(r).not.to.be.reverted;
      await expect(r).to.emit(escrow, 'ERC20RefundWithdrawn').withArgs(erc20Test, owner, ethers.parseUnits('1011', 18));
      await escrow.setRouter(await routerContract.getAddress());
    });

    it("should not allow manager to withdraw a refund when there is none.", async () => {
      await escrow.setRouter(router.address);
      const fromRouter = await escrow.connect(router);
      await expect(fromRouter.withdrawERC20Refund(1, erc20Test, owner))
        .to.be.revertedWithCustomError(escrow, 'NoRefunds')
        .withArgs(owner.address);
      await escrow.setRouter(await routerContract.getAddress());
      // check balances post withdraw
    });

    it("should not allow to register a fulfillment when it already was registered.", async () => {
      await escrow.setManager(managerEOA.address);
      const fromManager = await escrow.connect(managerEOA);
      const payerRecordIds = await escrow.recordsOf(owner);
      const record1 = await escrow.record(payerRecordIds[0]);
      const extID = record1[3];
      SUCCESS_FULFILLMENT_RESULT.id = payerRecordIds[0];
      await expect(
        fromManager.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT))
        .to.be.revertedWithCustomError(escrow, 'FulfillmentAlreadyRegistered');
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
        fromRouter.beneficiaryWithdraw(1, erc20Test))
          .to.be.revertedWithCustomError(escrow, 'InvalidAddress')
          .withArgs(router.address);
    });

    it("should not allow the beneficiary to withdraw the funds when there is none", async () => {
      const fromManager = await escrow.connect(managerEOA);
      await expect(
        fromManager.beneficiaryWithdraw(1, erc20Test))
        .to.be.revertedWithCustomError(escrow, 'NoBalanceToRelease');
    });
  });

  describe("withdrawAccumulatedFees", function() {
      it("should not allow non-manager to withdraw fees", async function() {
          await expect(escrow.connect(owner).withdrawAccumulatedFees(1, erc20Test))
            .to.be.revertedWithCustomError(escrow, 'InvalidAddress')
            .withArgs(owner.address);
      });

      it("should not allow withdrawal when no fees are accumulated", async function() {
          await escrow.setManager(managerEOA.address);
          await expect(escrow.connect(managerEOA).withdrawAccumulatedFees(1, ethers.ZeroAddress))
            .to.be.revertedWithCustomError(escrow, 'NoFeesToWithdraw');
          await escrow.setManager(await manager.getAddress());
      });

      it("should accumulate fees after successful fulfillment", async function() {
          const records = await escrow.recordsOf(await owner.getAddress());
          const recordId = records[2];
          // Register successful fulfillment
          const SUCCESS_RESULT = {
              id: recordId,
              status: 1, // SUCCESS
              externalID: uuidv4(),
              receiptURI: "https://example.com"
          };
          
          await manager.registerERC20Fulfillment(1, SUCCESS_RESULT);
          /* 
          * fees:
          * success record1 fee = 11 (1000 tokens)
          * success record2 fee = 1.1 (100 tokens)
          * total fees = 12.1 (1210000000000000000)
          */
          const accumulatedFees = await escrow.getERC20FeesFor(erc20Test, 1);
          const formattedFees = ethers.formatUnits(accumulatedFees, await erc20Test.decimals());
          expect(formattedFees).to.equal("12.1");
      });

      it("should not accumulate fees for failed fulfillment", async function() {
        DUMMY_FULFILLMENTREQUEST.payer = owner;
        DUMMY_FULFILLMENTREQUEST.tokenAmount = ethers.parseUnits("1000", 18);
        await expect(
          routerContract.requestERC20Service(1, DUMMY_FULFILLMENTREQUEST)
        ).to.emit(escrow, "ERC20DepositReceived")
        const records = await escrow.recordsOf(await owner.getAddress());
        const recordId = records[records.length - 1];
        // Register failed fulfillment
        const FAILED_RESULT = {
              id: recordId,
              status: 0, // FAILED
              externalID: uuidv4(),
              receiptURI: "https://example.com"
          };
          
          await manager.registerERC20Fulfillment(1, FAILED_RESULT);
          // Fees should not be accumulated. 
          // They should be the amount accumulated on other successful fulfillments
          const accumulatedFees = await escrow.getERC20FeesFor(erc20Test, 1);
          const formattedFees = ethers.formatUnits(accumulatedFees, await erc20Test.decimals());
          expect(formattedFees).to.equal("12.1");
      });

      it("should successfully withdraw accumulated fees", async function() {          
          // Get beneficiary's initial balance
          const [service, ] = await registry.getService(1);
          const beneficiary = service.beneficiary;
          const initialBalance = await erc20Test.balanceOf(beneficiary);
          // Withdraw fees
          const tx = await manager.withdrawERC20Fees(1, erc20Test);
          
          // Verify event emission
          await expect(tx)
              .to.emit(escrow, 'ERC20FeesWithdrawn')
              .withArgs(1, await erc20Test.getAddress(), beneficiary, "12100000000000000000");
          
          // Verify beneficiary received the fees
          const finalBalance = await erc20Test.balanceOf(beneficiary);
          const BNfeeAmount = ethers.parseUnits("12.1", 18);
          expect(finalBalance - initialBalance).to.equal(BNfeeAmount);
          
          // Verify fees were reset
          const postWithdrawFees = await escrow.getERC20FeesFor(erc20Test, 1);
          expect(postWithdrawFees).to.equal(0);
      });

      it("should handle zero service fees correctly", async function() {
          // Setup a service with zero fees
          await manager.setService(2, 0, fulfiller.address, beneficiary.address);
          await manager.setServiceRef(2, DUMMY_FULFILLMENTREQUEST.serviceRef);
          DUMMY_FULFILLMENTREQUEST.payer = owner;
          DUMMY_FULFILLMENTREQUEST.tokenAmount = ethers.parseUnits("1000", 18);
          await expect(
            routerContract.requestERC20Service(2, DUMMY_FULFILLMENTREQUEST)
          ).to.emit(escrow, "ERC20DepositReceived")
          const records = await escrow.recordsOf(await owner.getAddress());
          const recordId = records[records.length - 1];
          const SUCCESS_RESULT = {
              id: recordId,
              status: 1,
              externalID: DUMMY_FULFILLMENTREQUEST.serviceRef,
              receiptURI: "https://example.com"
          };
          
          await manager.registerERC20Fulfillment(2, SUCCESS_RESULT);
          // Fee should be the swap fee for the token (10 basis points)
          const calculatedFee = (DUMMY_FULFILLMENTREQUEST.tokenAmount * BigInt(10)) / BigInt(10000);
          const accumulatedFees = await escrow.getERC20FeesFor(erc20Test, 2);
          expect(accumulatedFees).to.equal(calculatedFee);
      });
  });

  describe("Upgradeability to V1.2 Specs", async () => {
    it("should be able to upgrade to v1.2", async () => {
      const FulfillableV1_2 = await ethers.getContractFactory('BandoERC20FulfillableV1_2');
      const upgraded = await upgrades.upgradeProxy(await escrow.getAddress(), FulfillableV1_2);
      escrow = FulfillableV1_2.attach(await upgraded.getAddress());
      expect(await escrow.getAddress()).to.be.a.properAddress;
      expect(await escrow._manager()).to.equal(await manager.getAddress());
    });
  });


  describe("Swap Pools Specs", () => {
    it("should allow a payable deposit coming from the router.", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = await owner.getAddress();
      DUMMY_FULFILLMENTREQUEST.tokenAmount = ethers.parseUnits('1000', 18);
      DUMMY_FULFILLMENTREQUEST.token = await erc20Test.getAddress();
      const response = await routerContract.requestERC20Service(1, DUMMY_FULFILLMENTREQUEST);
      const BNresponse = await escrow.getERC20DepositsFor(DUMMY_FULFILLMENTREQUEST.token, DUMMY_FULFILLMENTREQUEST.payer, 1);
      assert.equal(BNresponse.toString(), "1011000000000000000000");
      const erc20PostBalance = await erc20Test.balanceOf(await escrow.getAddress());
      expect(erc20PostBalance).to.be.equal("3123000000000000000000");
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
      const record1 = await escrow.record(payerRecordIds[payerRecordIds.length - 1]);
      expect(record1[0]).to.be.equal(payerRecordIds.length); //record ID
      expect(record1[2]).to.be.equal(await fulfiller.getAddress()); //fulfiller
      expect(record1[3]).to.be.equal(await erc20Test.getAddress()); //token
      expect(record1[5]).to.be.equal(owner); //payer address
      expect(record1[11]).to.be.equal(2); //status. 2 = PENDING
    });

    it("should not allow to whitelist the zero address as an aggregator", async () => {
      await escrow.setManager(managerEOA.address);
      await expect(manager.addAggregator(ethers.ZeroAddress))
        .to.be.revertedWithCustomError(escrow, 'InvalidAddress')
        .withArgs(ethers.ZeroAddress);
      await escrow.setManager(await manager.getAddress());
    });

    it("should allow to whitelist an aggregator", async () => {
      testSwapper = await ethers.deployContract('TestSwapAggregator');
      await testSwapper.waitForDeployment();
      await escrow.setManager(managerEOA.address);
      await expect(manager.addAggregator(await testSwapper.getAddress()))
        .to.emit(manager, 'AggregatorAdded')
        .withArgs(await testSwapper.getAddress());
      await expect(await manager.isAggregator(await testSwapper.getAddress())).to.be.true;
      await escrow.setManager(await manager.getAddress());
    });

    it("should be able to swap token pools for stable tokens", async () => {
      const tokenFrom = await erc20Test.getAddress();
      const tokenTo = await stableToken.getAddress();
      const records = await escrow.recordsOf(await owner.getAddress());
      const recordId = records[records.length - 1];
      // Transfer tokens to the swapper to mock the swap
      await stableToken.transfer(await testSwapper.getAddress(), ethers.parseUnits('100000', 18));
      // Register successful fulfillment
      const SUCCESS_RESULT = {
          id: recordId,
          status: 1, // SUCCESS
          externalID: uuidv4(),
          receiptURI: "https://example.com"
      };
      await manager.registerERC20Fulfillment(1, SUCCESS_RESULT);
      // Setup the call data for the swap
      const CallData = testSwapper.interface.encodeFunctionData("swapTokens", [
        tokenFrom,
        tokenTo,
        ethers.parseUnits('100', 18)
      ]);
      const swapData = {
        callData: CallData,
        fromToken: tokenFrom,
        toToken: tokenTo,
        amount: ethers.parseUnits('100', 18),
        callTo: await testSwapper.getAddress(),
      };
      await escrow.setManager(managerEOA.address);
      await expect(
        escrow
          .connect(managerEOA)
          .swapPoolsToStable(
            1,
            swapData
          )
      ).to.emit(escrow, "PoolsSwappedToStable");
      await escrow.setManager(await manager.getAddress());
      expect(await stableToken.balanceOf(
        await escrow.getAddress())).to.be.equal(ethers.parseUnits('200', 18)
      );
    });
      
  });

});
