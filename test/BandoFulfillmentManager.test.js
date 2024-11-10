const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
const eth = require('ethers');
const { setupRegistry } = require('./utils/registryUtils');
const BN = require('bn.js')

describe('BandoFulfillmentManagerV1', () => {
    let owner;
    let escrow;
    let erc20_escrow;
    let fulfiller;
    let beneficiary;
    let router;
    let registry;
    let manager;
    let erc20Test;

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
         * deploy router
         */
        const BandoRouterV1 = await ethers.getContractFactory('BandoRouterV1');
        routerContract = await upgrades.deployProxy(BandoRouterV1, [await owner.getAddress()]);
        await routerContract.waitForDeployment();
        router = BandoRouterV1.attach(await routerContract.getAddress());

        /**
         * configure protocol state vars.
         */
        const feeAmount = ethers.parseUnits('0.1', 'ether');
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
        await tokenRegistry.addToken(await erc20Test.getAddress());
    });

    describe('configuration', () => {
        it('should set up the manager', async () => {
            expect(await manager._escrow()).to.equal(await escrow.getAddress());
            expect(await manager._erc20_escrow()).to.equal(await erc20_escrow.getAddress());
            expect(await manager._serviceRegistry()).to.equal(await registry.getAddress());
        });
    });

    describe('Upgradeability', () => {
        it('should be upgradeable', async () => {
            const Manager = await ethers.getContractFactory('ManagerUpgradeTest');
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
            const feeAmount = ethers.parseUnits('0', 'ether');

            // Set up the service
            const result = await manager.setService(
                serviceID,
                feeAmount,
                await fulfiller.getAddress(),
                await beneficiary.getAddress(),
            );

            // Retrieve the service details from the registry
            const service = await registry.getService(serviceID);

            // Verify the service details
            expect(service.serviceId).to.equal(serviceID);
            expect(service.fulfiller).to.equal(fulfiller.address);
            expect(service.feeAmount).to.equal(feeAmount);

            // Verify the ServiceAdded event
            expect(result).to.emit(manager, 'ServiceAdded').withArgs(serviceID, result[0], validator.address, fulfiller.address);
        });

        it('should revert if the service ID is invalid', async () => {
            const serviceID = 0;
            const feeAmount = ethers.parseUnits('0.1', 'ether');

            // Ensure the transaction reverts with an appropriate error message
            await expect(manager.setService(
                serviceID,
                feeAmount,
                fulfiller.getAddress(), //Fulfiller
                beneficiary.getAddress(), //beneficiary
            )).to.be.revertedWith('Service ID is invalid');
        });

        it('should revert if the service already exists.', async () => {
            const serviceID = 1;
            const feeAmount = ethers.parseUnits('0.1', 'ether');

            // Ensure the transaction reverts with an appropriate error message
            await expect(
                manager.setService(
                    serviceID,
                    feeAmount,
                    fulfiller.getAddress(), //Fulfiller
                    beneficiary.getAddress(), //beneficiary
            )).to.be.revertedWith('FulfillableRegistry: Service already exists');
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
            const weiAmount = new BN(fulfillmentRequest.weiAmount);
            // Request the service through the router
            await router.requestService(serviceID, fulfillmentRequest, { value: weiAmount.toString() });
            const payerRecordIds = await escrow.recordsOf(await owner.getAddress());
            const SUCCESS_FULFILLMENT_RESULT = {
                id: payerRecordIds[0],
                status: 1,
                externalID: "012345678912",
                receiptURI: "https://example.com/receipt",
            };
            await expect(
                escrow.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT)
            ).to.be.revertedWith('Caller is not the manager');
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
            const weiAmount = new BN(fulfillmentRequest.weiAmount);
            // Request the service through the router
            await router.requestService(1, fulfillmentRequest, { value: weiAmount.toString() });
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
            await expect(r).to.emit(escrow, 'RefundAuthorized').withArgs(await owner.getAddress(), ethers.parseUnits('1000', 'wei'));
            const record = await escrow.record(payerRecordIds[1]);
            expect(record[10]).to.be.equal(0);
        });
    });

    describe('Withdraw Refunds', () => {
        it('should not allow an address with no refunds', async () => {
            await expect(manager.withdrawRefund(1, await beneficiary.getAddress()))
                .to.be.revertedWith("Address is not allowed any refunds");
        });

        it('should allow manager to withdraw a refund', async () => {
            const refunds = await escrow.getRefundsFor(await owner.getAddress(), 1);
            expect(refunds.toString()).to.be.equal("1000");
            const r = await manager.withdrawRefund(1, await owner.getAddress());
            await expect(r).not.to.be.reverted;
            await expect(r).to.emit(escrow, 'RefundWithdrawn').withArgs(await owner.getAddress(), ethers.parseUnits('1000', 'wei'));
            const postBalance = await ethers.provider.getBalance(await escrow.getAddress());
            expect(postBalance).to.be.equal(1000);
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
            await expect(
                erc20_escrow.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT)
            ).to.be.revertedWith('Caller is not the manager');
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
            const weiAmount = new BN(fulfillmentRequest.weiAmount);
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
            await expect(r).to.emit(erc20_escrow, 'ERC20RefundAuthorized').withArgs(await owner.getAddress(), "10000");
            const record = await erc20_escrow.record(payerRecordIds[1]);
            expect(record[11]).to.be.equal(0);
        });
    });

    describe('Withdraw ERC20 Refunds', () => {
        it('should not allow an address with no ERC20 refunds', async () => {
            await expect(manager.withdrawERC20Refund(1, await erc20Test.getAddress(), await beneficiary.getAddress()))
                .to.be.revertedWith("Address is not allowed any refunds");
        });

        it('should allow manager to withdraw an ERC20 refund', async () => {
            const refunds = await erc20_escrow.getERC20RefundsFor(await erc20Test.getAddress(), await owner.getAddress(), 1);
            expect(refunds.toString()).to.be.equal("10000");
            const r = await manager.withdrawERC20Refund(1, await erc20Test.getAddress(), await owner.getAddress());
            await expect(r).not.to.be.reverted;
            await expect(r).to.emit(erc20_escrow, 'ERC20RefundWithdrawn').withArgs(await erc20Test.getAddress(), await owner.getAddress(), "10000");
        });
    });
});
