const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
const { setupRegistry } = require('./utils/registryUtils');

describe('BandoFulfillmentManagerV1_2', () => {
    let owner;
    let escrow;
    let erc20_escrow;
    let fulfiller;
    let beneficiary;
    let router;
    let registry;
    let manager;
    let erc20Test;
    let testAggregator;
    let testNativeAggregator;
    let stableToken;
    const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A";

    before(async () => {
        [owner, mng, fulfiller, validator, beneficiary] = await ethers.getSigners();
        erc20Test = await ethers.deployContract('DemoToken');
        await erc20Test.waitForDeployment();
        /**
         * deploy registry
         */
        registry = await setupRegistry(await owner.getAddress());
        const registryAddress = await registry.getAddress();
        tokenRegistry = await ethers.getContractFactory('ERC20TokenRegistryV1');
        const tokenRegistryInstance = await upgrades.deployProxy(tokenRegistry, [await owner.getAddress()]);
        await tokenRegistryInstance.waitForDeployment();
        tokenRegistry = await tokenRegistry.attach(await tokenRegistryInstance.getAddress());
        /**
         * deploy manager
         */
        const Manager = await ethers.getContractFactory('BandoFulfillmentManagerV1');
        const m = await upgrades.deployProxy(Manager, [await owner.getAddress()]);
        await m.waitForDeployment();
        manager = await Manager.attach(await m.getAddress());
        /**
         * deploy escrows
         */
        const Escrow = await ethers.getContractFactory('BandoFulfillableV1_2');
        const e = await upgrades.deployProxy(Escrow, [await owner.getAddress()]);
        await e.waitForDeployment();
        escrow = await Escrow.attach(await e.getAddress());
        const ERC20Escrow = await ethers.getContractFactory('BandoERC20FulfillableV1_2');
        const erc20 = await upgrades.deployProxy(ERC20Escrow, [await owner.getAddress()]);
        await erc20.waitForDeployment();
        erc20_escrow = await ERC20Escrow.attach(await erc20.getAddress());

        /**
         * deploy router
         */
        const BandoRouterV1 = await ethers.getContractFactory('BandoRouterV1');
        routerContract = await upgrades.deployProxy(BandoRouterV1, [await owner.getAddress()]);
        await routerContract.waitForDeployment();
        router = BandoRouterV1.attach(await routerContract.getAddress());

        /**
         * deploy stable token
         */
        const StableToken = await ethers.getContractFactory('DemoStableToken');
        stableToken = await StableToken.deploy();
        await stableToken.waitForDeployment();

        /**
         * configure protocol state vars.
         */
        await escrow.setManager(await manager.getAddress());
        await escrow.setFulfillableRegistry(registryAddress);
        await escrow.setRouter(await router.getAddress());
        await erc20_escrow.setManager(await manager.getAddress());
        await erc20_escrow.setFulfillableRegistry(registryAddress);
        await erc20_escrow.setRouter(await router.getAddress());
        await registry.setManager(await manager.getAddress());
        await manager.setServiceRegistry(registryAddress);
        await manager.setEscrow(await escrow.getAddress());
        await manager.setERC20Escrow(await erc20_escrow.getAddress());
        await router.setFulfillableRegistry(registryAddress);
        await router.setTokenRegistry(await tokenRegistry.getAddress());
        await router.setEscrow(await escrow.getAddress());
        await router.setERC20Escrow(await erc20_escrow.getAddress());
        await erc20Test.approve(await router.getAddress(), 10000000000);
        await tokenRegistry.addToken(await erc20Test.getAddress(), 0);
        await tokenRegistry.addToken(await stableToken.getAddress(), 0);
        await stableToken.approve(await router.getAddress(), 10000000000);
        await registry.addFulfiller(await fulfiller.getAddress(), 1);
    });

    describe('configuration', () => {
        it('should set up the manager', async () => {
            expect(await manager._escrow()).to.equal(await escrow.getAddress());
            expect(await manager._erc20_escrow()).to.equal(await erc20_escrow.getAddress());
            expect(await manager._serviceRegistry()).to.equal(await registry.getAddress());
        });
    });

    describe('Upgradeability', () => {
        it('should upgrade to v1.1', async () => {
            const Manager = await ethers.getContractFactory('BandoFulfillmentManagerV1_1');
            const m = await upgrades.upgradeProxy(await manager.getAddress(), Manager);
            manager = await Manager.attach(await m.getAddress());
            expect(await manager._escrow()).to.equal(await escrow.getAddress());
            expect(await manager._erc20_escrow()).to.equal(await erc20_escrow.getAddress());
            expect(await manager._serviceRegistry()).to.equal(await registry.getAddress());
        });
    });

    describe('Ownability', () => {
        it('should be ownable', async () => {
            expect(await manager.owner()).to.equal(owner.address);
        });
        
        it('should allow the owner to transfer ownership', async () => {
            await manager.transferOwnership(validator.address);
            expect(await manager.owner()).to.equal(validator.address);
            asNewOwner = manager.connect(validator);
            await asNewOwner.transferOwnership(owner.address);
            expect(await manager.owner()).to.equal(owner.address);
        });

        it('should revert if a non-owner attempts to transfer ownership', async () => {
            const asUnauth = manager.connect(beneficiary);
            await expect(
                asUnauth.transferOwnership(owner.address)
            ).to.be.revertedWithCustomError(manager, 'OwnableUnauthorizedAccount');
        });
    });

    describe('Set Service', () => {
        it('should set up a service', async () => {
            const serviceID = 1;
            const feeAmountBasisPoints = 100;

            // Set up the service
            const result = await manager.setService(
                serviceID,
                feeAmountBasisPoints,
                await fulfiller.getAddress(),
                await beneficiary.getAddress(),
            );

            // Retrieve the service details from the registry
            const [service, _] = await registry.getService(serviceID);

            // Verify the service details
            expect(service.serviceId).to.equal(serviceID);
            expect(service.fulfiller).to.equal(fulfiller.address);

            // Verify the ServiceAdded event
            expect(result).to.emit(manager, 'ServiceAdded').withArgs(serviceID, result[0], validator.address, fulfiller.address);
        });

        it('should revert if the service ID is invalid', async () => {
            const serviceID = 0;
            const feeAmountBasisPoints = 10

            // Ensure the transaction reverts with an appropriate error message
            await expect(manager.setService(
                serviceID,
                feeAmountBasisPoints,
                fulfiller.getAddress(), //Fulfiller
                beneficiary.getAddress(), //beneficiary
            )).to.be.revertedWithCustomError(manager, 'InvalidServiceId')
            .withArgs(serviceID);
        });

        it('should revert if the service already exists.', async () => {
            const serviceID = 1;
            const feeAmountBasisPoints = 100;

            // Ensure the transaction reverts with an appropriate error message
            await expect(
                manager.setService(
                    serviceID,
                    feeAmountBasisPoints,
                    fulfiller.getAddress(), //Fulfiller
                    beneficiary.getAddress(), //beneficiary
                )
            )
            .to.be.revertedWithCustomError(registry, 'ServiceAlreadyExists')
            .withArgs(serviceID);
        });

        // TODO: Add more test cases for different scenarios
        it('should add a service ref', async () => {
            const serviceID = 1;
            const serviceRef = "012345678912";
            const result = await manager.setServiceRef(serviceID, serviceRef);
        });
    });

    describe("Register Fulfillments", () => {
        it("should only allow to register a fulfillment via the manager", async () => {
            const serviceID = 1;
            // Set up the fulfillment request

            const fulfillmentRequest = {
                payer: await owner.getAddress(),
                fiatAmount: "1000",
                serviceRef: "012345678912",
                weiAmount: ethers.parseUnits('1000', 'wei'),
            };
            // 1000 wei + 10.9999 service fee wei = 1011 wei
            const total_amount = ethers.parseUnits('1011', 'wei');
            // Request the service through the router
            await router.requestService(serviceID, fulfillmentRequest, { value: total_amount });
            const payerRecordIds = await escrow.recordsOf(await owner.getAddress());
            const SUCCESS_FULFILLMENT_RESULT = {
                id: payerRecordIds[0],
                status: 1,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            await expect(escrow.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT))
                .to.be.revertedWithCustomError(escrow, 'InvalidManager')
                .withArgs(owner.address);
            await expect(
                manager.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT)
            ).not.to.be.reverted;
            record = await escrow.record(payerRecordIds[0]);
            expect(record[10]).to.be.equal(1);
        });

        it("should not allow to register a fulfillment with an invalid status.", async () => {
            // Set up the fulfillment request
            const fulfillmentRequest = {
                payer: await owner.getAddress(),
                fiatAmount: "1000",
                serviceRef: "012345678912",
                weiAmount: ethers.parseUnits('1000', 'wei'),
            };
            // Request the service through the router
            await router.requestService(1, fulfillmentRequest, { value: "1011" });
            const payerRecordIds = await escrow.recordsOf(await owner.getAddress());
            const INVALID_FULFILLMENT_RESULT = {
                id: payerRecordIds[1],
                status: 3,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            await expect(
                manager.registerFulfillment(1, INVALID_FULFILLMENT_RESULT)
            ).to.be.reverted;
        });

        it("should authorize a refund after register a fulfillment with a failed status.", async () => {
            const payerRecordIds = await escrow.recordsOf(await owner.getAddress());
            const FAILED_FULFILLMENT_RESULT = {
                id: payerRecordIds[1],
                status: 0,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            const r = await manager.registerFulfillment(1, FAILED_FULFILLMENT_RESULT);
            await expect(r).not.to.be.reverted;
            await expect(r).to.emit(escrow, 'RefundAuthorized')
                .withArgs(await owner.getAddress(), ethers.parseUnits('1011', 'wei'));
            const record = await escrow.record(payerRecordIds[1]);
            expect(record[10]).to.be.equal(0);
        });
    });

    describe('Register ERC20 Fulfillments', () => {
        it('should only allow to register a fulfillment via the manager', async () => {
            const serviceID = 1;
            // Set up the fulfillment request
            const fulfillmentRequest = {
                payer: await owner.getAddress(),
                fiatAmount: "1000",
                serviceRef: "012345678912",
                tokenAmount: "10000",
                token: await erc20Test.getAddress(),
                feeAmount: 100,
            };
            // Request the service through the router
            await router.requestERC20Service(serviceID, fulfillmentRequest);
            const payerRecordIds = await erc20_escrow.recordsOf(await owner.getAddress());
            const SUCCESS_FULFILLMENT_RESULT = {
                id: payerRecordIds[0],
                status: 1,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            await expect(erc20_escrow.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT))
                .to.be.revertedWithCustomError(erc20_escrow, 'InvalidAddress')
                .withArgs(owner.address);
            await expect(
                manager.registerERC20Fulfillment(1, SUCCESS_FULFILLMENT_RESULT)
            ).not.to.be.reverted;
            const record = await erc20_escrow.record(payerRecordIds[0]);
            expect(record[11]).to.be.equal(1);
        });

        it("should not allow to register a fulfillment with an invalid status.", async () => {
            // Set up the fulfillment request
            const fulfillmentRequest = {
                payer: await owner.getAddress(),
                fiatAmount: "1000",
                serviceRef: "012345678912",
                tokenAmount: "10000",
                token: await erc20Test.getAddress(),
            };
            // Request the service through the router
            await router.requestERC20Service(1, fulfillmentRequest);
            const payerRecordIds = await erc20_escrow.recordsOf(await owner.getAddress());
            const INVALID_FULFILLMENT_RESULT = {
                id: payerRecordIds[1],
                status: 3,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            await expect(
                manager.registerERC20Fulfillment(1, INVALID_FULFILLMENT_RESULT)
            ).to.be.reverted;
        });

        it("should authorize a refund after register a fulfillment with a failed status.", async () => {
            const payerRecordIds = await erc20_escrow.recordsOf(await owner.getAddress());
            const FAILED_FULFILLMENT_RESULT = {
                id: payerRecordIds[1],
                status: 0,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            const r = await manager.registerERC20Fulfillment(1, FAILED_FULFILLMENT_RESULT);
            await expect(r).not.to.be.reverted;
            await expect(r).to.emit(erc20_escrow, 'ERC20RefundAuthorized')
                .withArgs(await owner.getAddress(), "10100");
            const record = await erc20_escrow.record(payerRecordIds[1]);
            expect(record[11]).to.be.equal(0);
        });
    });

    describe('Beneficiary Withdraws', () => {
        it('should only allow the fulfiller to withdraw', async () => {
            await expect(manager.beneficiaryWithdraw(1))
                .to.be.revertedWithCustomError(manager, 'InvalidFulfiller')
                .withArgs(owner.address);
        });

        it('should allow the beneficiary to withdraw', async () => {
            const asFulfiller = manager.connect(fulfiller);
            const r = await asFulfiller.beneficiaryWithdraw(1);
            await expect(r).not.to.be.reverted;
        });

        it('should not allow a non-fulfiller to withdraw ERC20', async () => {
            await expect(manager.beneficiaryWithdrawERC20(1, await erc20Test.getAddress()))
                .to.be.revertedWithCustomError(manager, 'InvalidFulfiller')
                .withArgs(owner.address);
        });

        it('should allow the fulfiller to withdraw ERC20', async () => {
            const asFulfiller = manager.connect(fulfiller);
            const r = await asFulfiller.beneficiaryWithdrawERC20(1, await erc20Test.getAddress());
            await expect(r).not.to.be.reverted;
        });
    });

    describe('Withdraw ERC20 Fees', () => {
        it('should only allow the fulfiller to withdraw ERC20 fees', async () => {
            await expect(manager.withdrawERC20Fees(1, await erc20Test.getAddress()))
                .to.be.revertedWithCustomError(manager, 'InvalidFulfiller')
                .withArgs(owner.address);
        });

        it('should allow the fulfiller to withdraw ERC20 fees', async () => {
            const asFulfiller = manager.connect(fulfiller);
            const r = await asFulfiller.withdrawERC20Fees(1, await erc20Test.getAddress());
            await expect(r).not.to.be.reverted;
        });
    });

    describe('Withdraw Native Fees', () => {
        it('should only allow the fulfiller to withdraw native fees', async () => {
            await expect(manager.withdrawNativeFees(1))
                .to.be.revertedWithCustomError(manager, 'InvalidFulfiller')
                .withArgs(owner.address);
        });

        it('should allow the fulfiller to withdraw native fees', async () => {
            const asFulfiller = manager.connect(fulfiller);
            const r = await asFulfiller.withdrawNativeFees(1);
            await expect(r).not.to.be.reverted;
        });
    });

    describe('Upgrade to v1.2', () => {
        it('should upgrade to v1.2', async () => {
            const Manager = await ethers.getContractFactory('BandoFulfillmentManagerV1_2');
            const m = await upgrades.upgradeProxy(await manager.getAddress(), Manager);
            manager = await Manager.attach(await m.getAddress());
        });
    });

    describe('Add Aggregators', () => {
        it('should add an aggregator', async () => {
            testAggregator = await ethers.deployContract('TestSwapAggregator');
            await testAggregator.waitForDeployment();
            await manager.addAggregator(await testAggregator.getAddress());
            expect(await manager.isAggregator(await testAggregator.getAddress())).to.equal(true);
        });

        it('should add a native aggregator', async () => {
            testNativeAggregator = await ethers.deployContract('TestNativeSwapAggregator');
            await testNativeAggregator.waitForDeployment();
            await manager.addAggregator(await testNativeAggregator.getAddress());
            expect(await manager.isAggregator(await testNativeAggregator.getAddress())).to.equal(true);
        });

        it('should not allow a non-owner to add an aggregator', async () => {
            const a = await ethers.deployContract('TestSwapAggregator');
            await a.waitForDeployment();
            const asNonOwner = manager.connect(beneficiary);
            await expect(asNonOwner.addAggregator(await a.getAddress()))
                .to.be.revertedWithCustomError(manager, 'OwnableUnauthorizedAccount');
        });
    });

    describe('Fulfill ERC20 and Swap', () => {
        it('should fulfill and swap as fulfiller', async () => {
            await stableToken.transfer(await testAggregator.getAddress(), ethers.parseUnits('100000', 18));
            const serviceID = 1;
            const fulfillmentRequest = {
                payer: await owner.getAddress(),
                fiatAmount: "1000",
                serviceRef: "012345678912",
                tokenAmount: "10000",
                token: await erc20Test.getAddress(),
            };
            await router.requestERC20Service(serviceID, fulfillmentRequest);
            const payerRecordIds = await erc20_escrow.recordsOf(await owner.getAddress());
            const SUCCESS_FULFILLMENT_RESULT = {
                id: payerRecordIds[payerRecordIds.length - 1],
                status: 1,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            const swapCallData = testAggregator.interface.encodeFunctionData('swapTokens', [
                await erc20Test.getAddress(),
                await stableToken.getAddress(),
                "10100",
            ]);
            const swapData = {
                callTo: await testAggregator.getAddress(),
                toToken: await stableToken.getAddress(),
                amount: "10100",
                callData: swapCallData
            };
            const asFulfiller = manager.connect(fulfiller);
            await expect(asFulfiller.fulfillERC20AndSwap(1, SUCCESS_FULFILLMENT_RESULT, swapData, true))
            .to.emit(erc20_escrow, 'PoolsSwappedToStable')
            .and.emit(erc20_escrow, 'PoolsAndFeesSubtracted')
            .withArgs(1, await stableToken.getAddress(), "20000", "200");
            console.log("myPool", await asFulfiller.myPool(await stableToken.getAddress()));
            console.log("myFees", await asFulfiller.myFees(await stableToken.getAddress()));
            await expect(await stableToken.balanceOf(await erc20_escrow.getAddress())).to.equal(ethers.parseUnits('20200', 'wei'));
        });

        it('should not swap if swap is false', async () => {
            const serviceID = 1;
            const fulfillmentRequest = {
                payer: await owner.getAddress(),
                fiatAmount: "1000",
                serviceRef: "012345678912",
                tokenAmount: "10000",
                token: await stableToken.getAddress(),
            };
            await router.requestERC20Service(serviceID, fulfillmentRequest);
            const payerRecordIds = await erc20_escrow.recordsOf(await owner.getAddress());
            const SUCCESS_FULFILLMENT_RESULT = {
                id: payerRecordIds[payerRecordIds.length - 1],
                status: 1,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            const swapCallData = testAggregator.interface.encodeFunctionData('swapTokens', [
                await erc20Test.getAddress(),
                await stableToken.getAddress(),
                "10100",
            ]);
            const swapData = {
                callTo: await testAggregator.getAddress(),
                toToken: await stableToken.getAddress(),
                amount: "10100",
                callData: swapCallData
            };
            const asFulfiller = manager.connect(fulfiller);
            await expect(asFulfiller.fulfillERC20AndSwap(1, SUCCESS_FULFILLMENT_RESULT, swapData, false))
                .to.emit(erc20_escrow, 'PoolsAndFeesSubtracted')
                .withArgs(1, await stableToken.getAddress(), "10000", "100")
                .and.not.to.emit(erc20_escrow, 'PoolsSwappedToStable');
        });

        it('should not allow a non-fulfiller to fulfill and swap', async () => {
            const asNonFulfiller = manager.connect(beneficiary);
            const SUCCESS_FULFILLMENT_RESULT = {
                id: 1,
                status: 1,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            const swapCallData = testAggregator.interface.encodeFunctionData('swapTokens', [
                await erc20Test.getAddress(),
                await stableToken.getAddress(),
                "10000",
            ]);
            const swapData = {
                callTo: await testAggregator.getAddress(),
                toToken: await stableToken.getAddress(),
                amount: "10000",
                callData: swapCallData
            };
            await expect(asNonFulfiller.fulfillAndSwap(1, SUCCESS_FULFILLMENT_RESULT, swapData))
                .to.be.revertedWithCustomError(manager, 'InvalidFulfiller')
                .withArgs(beneficiary.address);
        });
    });

    describe('Fulfill Native and Swap', () => {
        it('should fulfill and swap as fulfiller', async () => {
            await stableToken.transfer(await testNativeAggregator.getAddress(), ethers.parseUnits('100000', 18));
            const serviceID = 1;
            const fulfillmentRequest = {
                payer: await owner.getAddress(),
                fiatAmount: "1000",
                serviceRef: "012345678912",
                weiAmount: ethers.parseUnits('1000', 'wei'),
            };
            await router.requestService(serviceID, fulfillmentRequest, { value: ethers.parseUnits('1011', 'wei') });
            const payerRecordIds = await escrow.recordsOf(await owner.getAddress());
            const record = await escrow.record(payerRecordIds[payerRecordIds.length - 1]);
            console.log(record);
            const deposits = await escrow.getDepositsFor(await owner.getAddress(), 1);
            console.log(deposits);
            const SUCCESS_FULFILLMENT_RESULT = {
                id: payerRecordIds[payerRecordIds.length - 1],
                status: 1,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            const swapCallData = testNativeAggregator.interface.encodeFunctionData('swapNative', [
                await stableToken.getAddress(),
                ethers.parseUnits('1011', 'wei'),
            ]);
            const swapData = {
                callTo: await testNativeAggregator.getAddress(),
                toToken: await stableToken.getAddress(),
                amount: ethers.parseUnits('1011', 'wei'),
                callData: swapCallData
            };
            const asFulfiller = manager.connect(fulfiller);
            await expect(
                await asFulfiller.fulfillAndSwap(1, SUCCESS_FULFILLMENT_RESULT, swapData)
            ).to.emit(escrow, 'PoolsSwappedToStable')
            .and.emit(escrow, 'PoolsAndFeesSubtracted')
            .withArgs(1, await stableToken.getAddress(), "2000", "22");
        });

        it('should only allow a fulfiller to fulfill and swap', async () => {
            const asNonOwner = manager.connect(beneficiary);
            const SUCCESS_FULFILLMENT_RESULT = {
                id: 1,
                status: 1,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            const swapCallData = testNativeAggregator.interface.encodeFunctionData('swapNative', [
                await stableToken.getAddress(),
                ethers.parseUnits('1011', 'wei'),
            ]);
            const swapData = {
                callTo: await testNativeAggregator.getAddress(),
                toToken: await stableToken.getAddress(),
                amount: ethers.parseUnits('1011', 'wei'),
                callData: swapCallData
            };
            await expect(asNonOwner.fulfillAndSwap(1, SUCCESS_FULFILLMENT_RESULT, swapData))
                .to.be.revertedWithCustomError(manager, 'InvalidFulfiller')
                .withArgs(beneficiary.address);
        });
    });

    describe('Withdraw ERC20 Fulfiller Pool and Fees', () => {

        it('should allow to check my pools and fees as fulfiller', async () => {
            const asFulfiller = manager.connect(fulfiller);
            const pool = await asFulfiller.myPool(await stableToken.getAddress());
            const fees = await asFulfiller.myFees(await stableToken.getAddress());
            expect(pool).to.equal('30000');
            expect(fees).to.equal('300');
        });

        it('should allow the fulfiller to withdraw ERC20 fulfiller pool and fees', async () => {
            const asFulfiller = manager.connect(fulfiller);
            const r = await asFulfiller.withdrawERC20FulfillerPoolAndFees(
                await stableToken.getAddress(),
                '30000',
                '300',
                await beneficiary.getAddress(),
                await owner.getAddress()
            );
            await expect(r).to.emit(erc20_escrow, 'FulfillerPoolAndFeesWithdrawn')
                .withArgs(await stableToken.getAddress(), '30000', '300', await beneficiary.getAddress(), await owner.getAddress())
                .and.emit(stableToken, 'Transfer')
                .withArgs(await erc20_escrow.getAddress(), await beneficiary.getAddress(), '30000')
                .and.emit(stableToken, 'Transfer')
                .withArgs(await erc20_escrow.getAddress(), await owner.getAddress(), '300');
        });

        it('should not allow a non-fulfiller to withdraw ERC20 fulfiller pool and fees', async () => {
            const asNonFulfiller = manager.connect(beneficiary);
            await expect(asNonFulfiller.withdrawERC20FulfillerPoolAndFees(await erc20Test.getAddress(), '20000', '200', await owner.getAddress(), await owner.getAddress()))
                .to.be.revertedWithCustomError(manager, 'InvalidFulfiller')
                .withArgs(beneficiary.address);
        });
        
    });

    describe('Withdraw Native Fulfiller Pool and Fees', () => {
        it('should allow to check my pools and fees as fulfiller', async () => {
            const asFulfiller = manager.connect(fulfiller);
            const pool = await asFulfiller.myPoolNative(await stableToken.getAddress());
            const fees = await asFulfiller.myFeesNative(await stableToken.getAddress());
            expect(pool).to.equal('2000');
            expect(fees).to.equal('22');
        });

        it('should allow the fulfiller to withdraw native fulfiller pool and fees', async () => {
            const asFulfiller = manager.connect(fulfiller);
            const r = await asFulfiller.withdrawFulfillerStablePoolAndFees(await stableToken.getAddress(), '2000', '22', await beneficiary.getAddress(), await owner.getAddress());
            await expect(r).to.emit(escrow, 'FulfillerPoolAndFeesWithdrawn')
                .withArgs(await stableToken.getAddress(), '2000', '22', await beneficiary.getAddress(), await owner.getAddress())
                .and.emit(stableToken, 'Transfer')
                .withArgs(await escrow.getAddress(), await beneficiary.getAddress(), '2000')
                .and.emit(stableToken, 'Transfer')
                .withArgs(await escrow.getAddress(), await owner.getAddress(), '22');
        });

        it('should not allow a non-fulfiller to withdraw native fulfiller pool and fees', async () => {
            const asNonFulfiller = manager.connect(beneficiary);
            await expect(asNonFulfiller.withdrawFulfillerStablePoolAndFees(await stableToken.getAddress(), '2000', '22', await owner.getAddress(), await owner.getAddress()))
                .to.be.revertedWithCustomError(manager, 'InvalidFulfiller')
                .withArgs(beneficiary.address);
        });
    });
});
