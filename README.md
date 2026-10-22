# uRWA Policy Interface

A draft ERC and its reference implementation. The ERC defines how an [ERC-7943](https://eips.ethereum.org/EIPS/eip-7943) (uRWA) token hands its compliance decisions to a separate policy contract:

- **Movements.** For every movement of its balances, the token builds a `TransferContext`, labelled with the authority under which the movement happens: `TRANSFER`, `EXECUTED`, `FORCED`, `MINT` or `BURN`.
- **Decisions.** The token asks the policy for a `bytes32` decision before any balance changes. `keccak256("TRANSFER_OK")` permits; every other value, zero included, rejects.
- **Pre-flight.** The same policy answers the token's ERC-7943 `canSend`, `canReceive` and `canTransfer`. `canTransfer` must give the same decision as the transfer, mint or burn it predicts.
- **State.** A policy that keeps state observes completed movements through an authenticated `afterTransfer`.

**Status:** draft, not yet submitted. Nothing here is audited.

## Layout

| Path | What it is |
|---|---|
| [`erc/eip-draft_urwa_policy.md`](erc/eip-draft_urwa_policy.md) | The ERC draft, in EIP-1 format |
| [`contracts/interfaces/`](contracts/interfaces) | `IERCXXXXPolicy` and `IERCXXXX` (normative); ERC-7943's fungible interface, copied verbatim; the examples' interfaces |
| [`contracts/example/`](contracts/example) | `ExampleToken` (ERC-20 + ERC-7943 through this ERC) and `ExamplePolicy` (allowlist + holder cap), each with its unit tests |
| [`contracts/test/`](contracts/test) | Conformance and integration tests, faulty policies used by them, and test helpers |
| [`scripts/check-erc.py`](scripts/check-erc.py) | Checks that the draft's Solidity blocks match `contracts/`, and that its links and header follow EIP-1 |
| [`scripts/build-erc-assets.sh`](scripts/build-erc-assets.sh) | Assembles `erc/assets/eip-XXXX/` for the pull request to ethereum/ERCs |

`XXXX` stands for the ERC number, which an editor assigns on submission.

## Commands

```bash
npm ci --ignore-scripts
```

```bash
npm test
```

| Command | What it does |
|---|---|
| `npm test` | All Solidity tests (unit, integration, fuzz) |
| `npm run test:isolated` | The same tests with a fresh EVM per call |
| `npm run lint:sol` | solhint, zero warnings allowed |
| `npm run fmt` / `npm run fmt:check` | `forge fmt` with the Wonderland profile in `foundry.toml` |
| `slither .` | Static analysis (configuration in `slither.config.json`) |
| `npm run check:erc` | Draft and code in sync; add `-- --online` to confirm every linked ERC exists |
| `npm run erc:assets` | Builds `erc/assets/eip-XXXX/` |

Tooling: Hardhat 3, Solidity 0.8.30 (EVM `cancun`), OpenZeppelin Contracts 5.6.1, forge-std. The ERC interfaces compile from Solidity 0.8.20. The example token needs 0.8.28, for transient storage.

## Licence

- **Code** (`contracts/`, `scripts/`, configuration): [MIT](LICENSE).
- **ERC draft** (`erc/`): [CC0 1.0](erc/LICENSE), as EIP-1 requires of every ERC.
- **The copy of ERC-7943's interface** (`contracts/interfaces/IERC7943Fungible.sol`) keeps the CC0 of the ERC it comes from.
