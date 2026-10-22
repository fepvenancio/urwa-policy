# The ERC draft

[`eip-draft_urwa_policy.md`](eip-draft_urwa_policy.md) is the draft as it will be submitted to ethereum/ERCs. Its asset links (`../assets/eip-XXXX/...`) resolve once `npm run erc:assets` has built `erc/assets/eip-XXXX/`.

## Keeping it in sync

- The Solidity blocks in the draft are copies of `contracts/interfaces/IERCXXXXPolicy.sol`, `contracts/interfaces/IERCXXXX.sol`, and the `_update` and `_permits` functions of `contracts/example/ExampleToken.sol`.
- `npm run check:erc` fails when any of them drifts. CI runs it on every push.
- When an interface changes, update the draft in the same change. Selectors, interface identifiers and test cases are pinned in `contracts/test/ERCXXXX.t.sol`.

## Before posting to Ethereum Magicians

- Fill in `discussions-to` with the thread URL.
- Ask ERC-7943's authors to confirm two readings this draft relies on:
  - `canTransfer` predicts only `TRANSFER`, `MINT` and `BURN` movements;
  - a zero `from` or `to` makes `canTransfer` the pre-flight for a mint or a burn.

  If they disagree, the "What `canTransfer` predicts" rationale and check rule 3 need rework.
- The Universal Policy Engine proposal (an open pull request, not merged) is mentioned by name only. EIP linting rejects links to unmerged ERCs.

## Before opening the pull request

1. Run `npm run check:erc -- --online`.
2. Run `npm run erc:assets`, and copy `erc/assets/eip-XXXX/` into the ERCs repository as `assets/eip-<number>/`.
3. Replace `XXXX` with the assigned number in the draft and the sources.
4. Remove `author` placeholders and template comments, if any remain.

The draft carries EIP-1's CC0 waiver, and [`LICENSE`](LICENSE) in this folder holds the CC0 text. The assets are MIT, as ERC-7943's own reference implementation is.
