# The ERC draft

[`eip-draft_urwa_policy.md`](eip-draft_urwa_policy.md) is the draft as it will be submitted to ethereum/ERCs. It carries EIP-1's CC0 waiver, and [`LICENSE`](LICENSE) in this folder holds the CC0 text.

## Keeping it in sync

- The Solidity blocks in the draft are copies of `contracts/interfaces/IERCXXXXPolicy.sol`, `contracts/interfaces/IERCXXXX.sol`, and the `_update` and `_permits` functions of `contracts/example/ExampleToken.sol`.
- `npm run check:erc` fails when any of them drifts. CI runs it on every push.
- When an interface changes, update the draft in the same change. Selectors, interface identifiers and test cases are pinned in `contracts/test/ERCXXXX.t.sol`.

## Building the assets

- `npm run erc:assets` copies `contracts/interfaces/`, `contracts/example/` and `contracts/test/` into `erc/assets/eip-XXXX/contracts/`, leaving out the 0.8.20 build probe.
- That is where the draft's asset links (`../assets/eip-XXXX/...`) point. The folder is gitignored.
- The assets are MIT, as ERC-7943's own reference implementation is.
