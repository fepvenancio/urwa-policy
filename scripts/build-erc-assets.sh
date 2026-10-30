#!/usr/bin/env bash
# Assembles erc/assets/eip-8473/ from contracts/, in the layout the draft's asset links expect.
# Run before opening the pull request to ethereum/ERCs, then copy erc/assets/eip-8473/ next to the ERC file.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/erc/assets/eip-8473"

rm -rf "$out"
mkdir -p "$out/contracts"
for dir in interfaces example test; do
  cp -R "$root/contracts/$dir" "$out/contracts/$dir"
done
# The 0.8.20 probe is build tooling for this repository, not part of the reference implementation.
rm -f "$out/contracts/test/InterfacesAt0820.sol"

echo "build-erc-assets: wrote $(find "$out" -type f | wc -l | tr -d ' ') files to erc/assets/eip-8473"
