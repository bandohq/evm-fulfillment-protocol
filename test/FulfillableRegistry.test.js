const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
const eth = require('ethers');
const { setupRegistry } = require('./utils/registryUtils');

describe('FulfillableRegistryV1', () => {
    let owner;
    let registry;
    let manager;
    const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A";
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    before(async () => {
        [owner] = await ethers.getSigners();
        // Deploy the BandoFulfillmentManagerV1 contract
        // deploy registry
        const registryInstance = await setupRegistry(await owner.getAddress());
        const registryAddress = await registryInstance.getAddress();
        registry = registryInstance;
        const BandoFulfillmentManager = await ethers.getContractFactory('BandoFulfillmentManagerV1');
        const bandoFulfillmentManager = await upgrades.deployProxy(BandoFulfillmentManager, []);
        await bandoFulfillmentManager.waitForDeployment();
        manager = await BandoFulfillmentManager.attach(await bandoFulfillmentManager.getAddress());
        await registry.setManager(await manager.getAddress());
        await manager.setServiceRegistry(registryAddress);
        await manager.setEscrow(DUMMY_ADDRESS);
        await manager.setERC20Escrow(DUMMY_ADDRESS);
    });

    describe('setService', () => {
        it('should set up a service', async () => {
            const serviceID = 1;
            // Verify no services exist in counter
            expect(await registry._serviceCount()).to.equal(0);
            // Set up the service
            await expect(manager.setService(
              serviceID,
              10, //fulfillmentFeePercentage
              DUMMY_ADDRESS, //Fulfiller
              DUMMY_ADDRESS, //beneficiary
            )).to.emit(registry, 'ServiceAdded');

            // Retrieve the service details from the registry
            const [service, ] = await registry.getService(serviceID);

            // Verify the service details
            expect(service.serviceId).to.equal(serviceID);
            expect(service.fulfiller).to.equal(DUMMY_ADDRESS);

            // Verify the service count
            expect(await registry._serviceCount()).to.equal(1);

        });

        it('should revert if the service ID is invalid', async () => {
            const serviceID = 0;
            const feeAmount = ethers.parseUnits('0.1', 'ether');
            await expect(manager.setService(
              serviceID,
              10, //fulfillmentFeePercentage
              DUMMY_ADDRESS, //Fulfiller
              DUMMY_ADDRESS, //beneficiary
            )).to.be.revertedWith('Service ID is invalid');
        });

        it('should revert if the service already exists', async () => {
            const serviceID = 1;
            const feeAmount = ethers.parseUnits('0.1', 'ether');
            await expect(manager.setService(
              serviceID,
              10, //fulfillmentFeePercentage
              DUMMY_ADDRESS, //Fulfiller
              DUMMY_ADDRESS, //beneficiary
            )).to.be.revertedWith('FulfillableRegistry: Service already exists');
        });

        it('should revert if the beneficiary address is invalid', async () => {
            const serviceID = 2;
            const feeAmount = ethers.parseUnits('0.1', 'ether');
            await expect(manager.setService(
              serviceID,
              10, //fulfillmentFeePercentage
              DUMMY_ADDRESS, //Fulfiller
              ZERO_ADDRESS, //beneficiary
            )).to.be.revertedWith("Beneficiary address is invalid");
        });

        it('should revert if the fulfiller address is invalid', async () => {
            const serviceID = 3;
            const feeAmount = ethers.parseUnits('0.1', 'ether');
            await expect(manager.setService(
              serviceID,
              10, //fulfillmentFeePercentage
              ZERO_ADDRESS, //Fulfiller
              DUMMY_ADDRESS, //beneficiary
            )).to.be.revertedWith("Fulfiller address is invalid");
        });

        it('should revert if the fee amount is invalid', async () => {
          //TODO
        });
    });

    describe('setServiceRef', () => {
        it('should set a service reference', async () => {
            const serviceID = 1;
            const serviceRef = '0123456789';
            await expect(manager.setServiceRef(serviceID, serviceRef)).not.to.be.reverted;
        });

        it('should revert if the service ID is invalid', async () => {
            const serviceID = 0;
            const serviceRef = '0123456789';
            await expect(manager.setServiceRef(serviceID, serviceRef)).to.be.revertedWith('Service does not exist');
        });

        it('should mark the ref as valid', async () => {
          const serviceID = 1;
          const serviceRef = '0123456789';
          expect(await registry.isRefValid(serviceID, serviceRef)).to.equal(true);
        });
    });

    describe("update services", () => {
      it("should allow an owner to update service properties", async () => {
        const serviceID = 1;
        const newFeeAmount = ethers.parseUnits('0.2', 'ether');
        const newBeneficiary = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A";
        const newFulfiller = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A";
        await registry.updateServiceBeneficiary(serviceID, newBeneficiary);
        await registry.updateServiceFulfiller(serviceID, newFulfiller);
        const [service, ] = await registry.getService(serviceID);
        expect(service.fulfiller).to.equal(newFulfiller);
        expect(service.beneficiary).to.equal(newBeneficiary);
      });

      it('should revert if the fulfiller address is invalid', async () => {
        const serviceID = 4;
        const newFulfiller = ZERO_ADDRESS;
        await expect(registry.updateServiceFulfiller(serviceID, newFulfiller))
          .to.be.revertedWithCustomError(registry, 'InvalidAddress')
          .withArgs(ZERO_ADDRESS);
      });
    });
});
