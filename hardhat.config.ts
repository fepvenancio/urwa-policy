import { defineConfig } from "hardhat/config";

// One compiler setting for every source: tests run on exactly the bytecode an implementer would deploy.
// No metadata hash, so the same source always compiles to the same bytecode.
const compiler = {
  version: "0.8.30",
  settings: {
    evmVersion: "cancun",
    optimizer: {
      enabled: true,
      runs: 200,
    },
    metadata: {
      bytecodeHash: "none" as const,
    },
  },
};

export default defineConfig({
  solidity: {
    profiles: {
      default: {
        compilers: [compiler],
        // The ERC interfaces declare `^0.8.20`: compile them once with the oldest compiler they allow.
        overrides: {
          "contracts/test/InterfacesAt0820.sol": { version: "0.8.20", settings: { evmVersion: "shanghai" } },
        },
      },
    },
  },
  test: {
    solidity: {
      profiles: {
        default: { fuzz: { runs: 1024 } },
        // A fresh EVM per call: fixtures must not depend on the deployer's nonce.
        isolated: { fuzz: { runs: 256 }, isolate: true },
      },
    },
  },
});
