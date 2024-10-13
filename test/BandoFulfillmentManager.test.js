const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
const eth = require('ethers');
const { setupRegistry } = require('./utils/registryUtils');

describe('BandoFulfillmentManagerV1', () => {
    let owner;
    let escrow;
    let erc20_escrow;
    let fulfiller;
    let beneficiary;
    let router;
    let registry;
    let manager;

    const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A";

    before(async () => {
        [owner, validator, fulfiller, beneficiary, router] = await ethers.getSigners();
        /**
         * deploy registry
         */
        registry = await setupRegistry(await owner.getAddress());
        const registryAddress = await registry.getAddress();
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
        await escrow.setRouter(DUMMY_ADDRESS);
        await erc20_escrow.setManager(await manager.getAddress());
        await erc20_escrow.setFulfillableRegistry(registryAddress);
        await erc20_escrow.setRouter(DUMMY_ADDRESS);
        await registry.setManager(await manager.getAddress());
        await manager.setServiceRegistry(registryAddress);
        await manager.setEscrow(await escrow.getAddress());
        await manager.setERC20Escrow(await erc20_escrow.getAddress());
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

    describe('setService', () => {
        it('should set up a service', async () => {
            const serviceID = 1;
            const feeAmount = ethers.parseUnits('0.1', 'ether');

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

        // Add more test cases for different scenarios
        it('should add a service ref', async () => {
            const serviceID = 1;
            const serviceRef = "012345678912";
            const result = await manager.setServiceRef(serviceID, serviceRef);
        });
    });
});
