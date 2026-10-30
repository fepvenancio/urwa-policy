# The ERC draft

[`eip-draft_urwa_policy.md`](eip-draft_urwa_policy.md) is the draft submitted to ethereum/ERCs in [pull request 2128](https://github.com/ethereum/ERCs/pull/2128). That pull request carries a copy, as `ERCS/erc-9999.md` with assets in `assets/erc-9999/`, until an editor assigns a number. A change here has to be made there too. It carries EIP-1's CC0 waiver, and [`LICENSE`](LICENSE) in this folder holds the CC0 text.

## Keeping it in sync

- The Solidity blocks in the draft are copies of `contracts/interfaces/IERCXXXXPolicy.sol`, `contracts/interfaces/IERCXXXX.sol`, and the `_update` and `_permits` functions of `contracts/example/ExampleToken.sol`.
- `npm run check:erc` fails when any of them drifts. CI runs it on every push to `main` and on every pull request.
- When an interface changes, update the draft in the same change. Selectors, interface identifiers and test cases are pinned in `contracts/test/ERCXXXX.t.sol` and the unit tests beside the examples.

## Building the assets

- `npm run erc:assets` copies `contracts/interfaces/`, `contracts/example/` and `contracts/test/` into `erc/assets/eip-XXXX/contracts/`, leaving out the 0.8.20 build probe.
- The draft's asset links (`../assets/eip-XXXX/...`) point at this folder's contents once it is copied into ethereum/ERCs, and do not resolve in this repository. The folder is gitignored.
- The assets are MIT, as ERC-7943's own reference implementation is, except the copy of ERC-7943's interface, which keeps its CC0.
