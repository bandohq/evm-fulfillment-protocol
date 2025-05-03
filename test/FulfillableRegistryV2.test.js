const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
const eth = require('ethers');
const { setupRegistry } = require('./utils/registryUtils');

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A";
const DUMMY_SERVICE = {
  serviceId: 1,
  beneficiary: DUMMY_ADDRESS,
  feeAmount: 100,
  fulfiller: DUMMY_ADDRESS
};

describe('FulfillableRegistryV1_2', () => {
    let owner;
    let registry;
    let manager;
    before(async () => {
        [owner] = await ethers.getSigners();
        // Deploy the BandoFulfillmentManagerV1 contract
        // deploy registry
        const registryInstance = await setupRegistry(await owner.getAddress());
        const registryAddress = await registryInstance.getAddress();
        registry = registryInstance;
        const BandoFulfillmentManager = await ethers.getContractFactory('BandoFulfillmentManagerV1');
        const bandoFulfillmentManager = await upgrades.deployProxy(BandoFulfillmentManager, [await owner.getAddress()]);
        await bandoFulfillmentManager.waitForDeployment();
        manager = await BandoFulfillmentManager.attach(await bandoFulfillmentManager.getAddress());
        await registry.setManager(await manager.getAddress());
        await manager.setServiceRegistry(registryAddress);
        await manager.setEscrow(DUMMY_ADDRESS);
        await manager.setERC20Escrow(DUMMY_ADDRESS);
    });

    describe('upgrade to V1_2', () => {
        it('should upgrade to V1_2', async () => {
            const FulfillableRegistryV2 = await ethers.getContractFactory('FulfillableRegistryV1_2');
            const fulfillableRegistryV2 = await upgrades.upgradeProxy(await registry.getAddress(), FulfillableRegistryV2);
            registry = await FulfillableRegistryV2.attach(await fulfillableRegistryV2.getAddress());
            expect(await registry.owner()).to.equal(await owner.getAddress());
        });
    });

    describe('addServiceRefV2', () => {
        it('should add a service reference with no previous service added.', async () => {
            const serviceRef = '0123456789';
            await expect(registry.addServiceRefV2(DUMMY_SERVICE, serviceRef, DUMMY_SERVICE.feeAmount))
              .to.emit(registry, 'ServiceAdded')
              .withArgs(DUMMY_SERVICE.serviceId, DUMMY_SERVICE.fulfiller)
              .and.to.emit(registry, 'ServiceRefAdded')
              .withArgs(DUMMY_SERVICE.serviceId, serviceRef);
        });

        it('should add a service reference with a previous service added.', async () => {
            const serviceRef = '0123456789';
            await expect(registry.addServiceRefV2(DUMMY_SERVICE, serviceRef, DUMMY_SERVICE.feeAmount))
              .to.emit(registry, 'ServiceRefAdded')
              .withArgs(DUMMY_SERVICE.serviceId, serviceRef)
              .and.not.to.emit(registry, 'ServiceAdded');
        });

        it('should fail to add a service reference with invalid service.', async () => {
            const serviceRef = '0123456789';
            DUMMY_SERVICE.fulfiller = "0x0000000000000000000000000000000000000000";
            await expect(registry.addServiceRefV2(DUMMY_SERVICE, serviceRef, DUMMY_SERVICE.feeAmount))
              .to.be.revertedWithCustomError(registry, 'InvalidService');
        });

        it('should fail to add a service reference with invalid fee amount.', async () => {
            const serviceRef = '0123456789';
            DUMMY_SERVICE.fulfiller = DUMMY_ADDRESS;
            await expect(registry.addServiceRefV2(DUMMY_SERVICE, serviceRef, 10001))
              .to.be.revertedWithCustomError(registry, 'InvalidfeeAmountBasisPoints');
        });
    });
});
