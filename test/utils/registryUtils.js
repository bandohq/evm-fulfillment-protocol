const { ethers, upgrades } = require("hardhat");

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A";

const DUMMY_SERVICE = {
  serviceId: 1,
  beneficiary: DUMMY_ADDRESS,
  feeAmount: 100,
  fulfiller: DUMMY_ADDRESS
};

const DUMMY_SERVICE_2 = {
  serviceId: 2,
  beneficiary: DUMMY_ADDRESS,
  feeAmount: 200,
  fulfiller: DUMMY_ADDRESS
};

const DUMMY_SERVICE_3 = {
  serviceId: 3,
  beneficiary: DUMMY_ADDRESS,
  feeAmount: 300,
  fulfiller: DUMMY_ADDRESS
};

const dummy_services = [DUMMY_SERVICE, DUMMY_SERVICE_2, DUMMY_SERVICE_3];

module.exports = {
  setupRegistry: async (owner) => {
    const registryFactory = await ethers.getContractFactory("FulfillableRegistry");
    const registry = await upgrades.deployProxy(registryFactory, []);
    await registry.waitForDeployment();
    const registryInstance = await registryFactory.attach(await registry.getAddress());
    return registryInstance;
  },
  setDummyServices: async (registry, manager) => {
    await registry.connect(manager);
    const p = [];
    for (const service of dummy_services) {
      // function addService(uint256 serviceId, Service memory service)
      p.push(registry.addService(service.serviceId, service));
    }
    await Promise.all(p);
  }
};
