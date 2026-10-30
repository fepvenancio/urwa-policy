"""Checks that erc/eip-draft_urwa_policy.md stays in sync with contracts/ and follows EIP-1's mechanical rules.

Usage: python3 -I scripts/check-erc.py [--online]
  --online  also confirm, through `gh api`, that every ERC or EIP the draft links exists in ethereum/ERCs or ethereum/EIPs
"""

import re
import subprocess
import sys
import textwrap
from pathlib import Path

root = Path(__file__).resolve().parent.parent
doc = (root / "erc" / "eip-draft_urwa_policy.md").read_text()
problems = []

front, body = doc.split("\n---\n", 1)
header = dict(line.split(": ", 1) for line in front.strip("-\n").splitlines())
for field in ("eip", "title", "description", "author", "discussions-to", "status", "type", "category", "created", "requires"):
    if field not in header:
        problems.append(f"header lacks {field}")
if len(header.get("title", "")) > 44:
    problems.append("title longer than 44 characters")
if len(header.get("description", "")) > 140:
    problems.append("description longer than 140 characters")
for field in ("title", "description"):
    if re.search(r"(?i)standar", header.get(field, "")):
        problems.append(f"{field} uses the word standard")


def interface_body(path):
    lines = (root / path).read_text().splitlines()
    while lines and (
        (lines[0].startswith("//") and not lines[0].startswith("///"))
        or lines[0].startswith(("pragma", "import"))
        or not lines[0].strip()
    ):
        lines.pop(0)
    return "\n".join(lines).strip()


def function_source(path, name):
    lines = (root / path).read_text().splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith(f"  function {name}("))
    end = next(i for i in range(start, len(lines)) if lines[i] == "  }")
    return textwrap.dedent("\n".join(lines[start : end + 1]))


blocks = [b.strip() for b in re.findall(r"```solidity\n(.*?)```", body, re.S)]
expected = [
    interface_body("contracts/interfaces/IERC8473Policy.sol") + "\n\n" + interface_body("contracts/interfaces/IERC8473.sol"),
    function_source("contracts/example/ExampleToken.sol", "_update") + "\n\n" + function_source("contracts/example/ExampleToken.sol", "_move"),
    function_source("contracts/example/ExampleToken.sol", "_permits"),
]
if len(blocks) != len(expected):
    problems.append(f"expected {len(expected)} Solidity blocks, found {len(blocks)}")
for i, (found, want) in enumerate(zip(blocks, expected)):
    if found != want:
        problems.append(f"Solidity block {i + 1} differs from its source in contracts/")

prose = re.sub(r"```.*?```", "", body, flags=re.S)
prose = re.sub(r"`[^`]*`", "", prose)
mentioned = []
for m in re.finditer(r"(\[)?\b(ERC|EIP)-(\d+)\b(\]\(\./eip-(\d+)\.md\))?", prose):
    number, linked = m.group(3), bool(m.group(4))
    if linked and m.group(5) != number:
        problems.append(f"link text {m.group(2)}-{number} points to eip-{m.group(5)}")
    if number not in mentioned:
        mentioned.append(number)
        if not linked:
            problems.append(f"first mention of {m.group(2)}-{number} is not a link")

# The ERC links its assets as ../assets/eip-8473/<path>; here they live at <path>.
for target in re.findall(r"\]\(\.\./assets/eip-8473/([^)]+)\)", body):
    if not (root / target).exists():
        problems.append(f"asset link points to a missing file: {target}")
for target in re.findall(r"\]\((https?://[^)]+)\)", body):
    if "rfc-editor.org" not in target:
        problems.append(f"external link: {target}")

for section in ("Abstract", "Specification", "Rationale", "Security Considerations", "Copyright"):
    if f"\n## {section}\n" not in body:
        problems.append(f"missing section: {section}")

if "--online" in sys.argv:
    for number in mentioned:
        found = any(
            subprocess.run(["gh", "api", path, "--silent"], capture_output=True).returncode == 0
            for path in (f"repos/ethereum/ERCs/contents/ERCS/erc-{number}.md", f"repos/ethereum/EIPs/contents/EIPS/eip-{number}.md")
        )
        if not found:
            problems.append(f"ERC/EIP-{number} exists in neither ethereum/ERCs nor ethereum/EIPs")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print(f"check-erc: ok ({len(blocks)} code blocks in sync; ERCs mentioned: {', '.join(sorted(mentioned, key=int))})")
