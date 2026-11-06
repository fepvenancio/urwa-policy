#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Builds the documentation site into _site/ and fails on a broken internal link.

Each page in PAGES is made of parts. An .html part is a hand-written fragment from site/, inserted as it is. A .md part
is rendered by pandoc, which is pinned in tools.lock (scripts/fetch-tool.sh pandoc). Every page is wrapped in
site/layout.html.

The build fails when pandoc warns, when a rewritten link points to a file the repository does not have, when an id is
used twice on a page, or when an internal link points to a missing page or anchor. Links to other sites are not checked.

Usage: python3 scripts/build-site.py
"""

import html
import os
import re
import shutil
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / 'site'
OUT = ROOT / '_site'
REPO = 'https://github.com/fepvenancio/urwa-policy'
DRAFT = 'erc/eip-draft_urwa_policy.md'

# (output file, <title>, parts)
PAGES = [
  ('index.html', 'uRWA Policy · ERC-8473', ['site/index.html']),
  ('how-it-works.html', 'How it works · ERC-8473', ['site/how-it-works.html']),
  ('stories.html', 'User stories · ERC-8473', ['site/stories.html']),
  ('implementing.html', 'Implementing · ERC-8473', ['site/implementing.html']),
  ('spec.html', 'Specification · ERC-8473', [DRAFT]),
  ('contributing.html', 'Contributing · ERC-8473', ['site/contributing.html', 'README.md', 'erc/README.md']),
]

SPDX = '<!-- SPDX-License-Identifier: MIT -->\n'

errors = []


def fail(message):
  errors.append(message)


def pandoc_path():
  pinned = ROOT / '.tools' / 'bin' / 'pandoc'
  found = str(pinned) if pinned.exists() else shutil.which('pandoc')
  if not found:
    sys.exit('build-site: pandoc not found. Run scripts/fetch-tool.sh pandoc first.')
  return found


def commit():
  sha = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
  dirty = subprocess.run(['git', 'status', '--porcelain'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
  return sha, bool(dirty.strip())


def split_header(text):
  """Splits an EIP-1 header (between two '---' lines) from the body. Returns ([(key, value)], body)."""
  if not text.startswith('---\n'):
    return [], text
  end = text.index('\n---\n', 4)
  pairs = [line.split(': ', 1) for line in text[4:end].splitlines()]
  return [(key, value) for key, value in pairs], text[end + 5:]


def render_markdown(text, shift):
  args = [pandoc_path(), '-f', 'gfm', '-t', 'html5', '--syntax-highlighting=none', f'--shift-heading-level-by={shift}']
  result = subprocess.run(args, input=text, capture_output=True, text=True)
  if result.returncode != 0 or result.stderr.strip():
    fail(f'pandoc: {result.stderr.strip()}')
  return result.stdout


def rewrite_link(source, target):
  """Maps a link in a rendered markdown file to its address on the site."""
  if re.match(r'(https?:|mailto:|#)', target):
    return target
  path, _, fragment = target.partition('#')
  fragment = f'#{fragment}' if fragment else ''
  eip = re.fullmatch(r'\./eip-(\d+)\.md', path)
  if eip:
    return f'https://eips.ethereum.org/EIPS/eip-{eip.group(1)}{fragment}'
  asset = re.fullmatch(r'\.\./assets/eip-8473/(.+)', path)
  if source == DRAFT and path == '../LICENSE.md':
    repo_path = 'erc/LICENSE'  # ethereum/ERCs keeps the CC0 text at its root; this repository keeps it beside the draft
  elif asset:
    repo_path = asset.group(1)
  else:
    repo_path = os.path.normpath(os.path.join(os.path.dirname(source), path))
  if repo_path == DRAFT:
    return f'spec.html{fragment}'
  full = ROOT / repo_path
  if not full.exists():
    fail(f'{source}: link {target} points to {repo_path}, which the repository does not have')
    return target
  return f'{REPO}/{"tree" if full.is_dir() else "blob"}/main/{repo_path}{fragment}'


def markdown_part(source, sha):
  header, body = split_header((ROOT / source).read_text())
  rendered = render_markdown(body, 0 if header else 1)
  rendered = re.sub(r'href="([^"]*)"', lambda m: f'href="{html.escape(rewrite_link(source, html.unescape(m.group(1))))}"', rendered)
  if not header:
    return f'<section class="md">\n{rendered}</section>\n'
  return spec_header(dict(header), sha) + toc(rendered) + f'<article class="md spec-body">\n{rendered}</article>\n'


def spec_header(meta, sha):
  def cell(key, value):
    if key == 'discussions-to':
      return f'<a href="{html.escape(value)}">{html.escape(value)}</a>'
    if key == 'requires':
      return ', '.join(f'<a href="https://eips.ethereum.org/EIPS/eip-{n.strip()}">ERC-{n.strip()}</a>' for n in value.split(','))
    return html.escape(value)

  shown = [(k, v) for k, v in meta.items() if k not in ('eip', 'title', 'description')]  # those three head the page
  rows = '\n'.join(f'<tr><th scope="row">{html.escape(k)}</th><td>{cell(k, v)}</td></tr>' for k, v in shown)
  return f'''<header class="spec-head">
<p class="eyebrow">Specification · generated from <a href="{REPO}/blob/{sha}/{DRAFT}"><code>{DRAFT}</code></a></p>
<h1>ERC-{html.escape(meta['eip'])}: {html.escape(meta['title'])}</h1>
<p class="lede">{html.escape(meta['description'])}</p>
<p class="note">This is the draft in this repository, rendered at the commit in the footer. The copy under review is in
<a href="https://github.com/ethereum/ERCs/pull/2128">ethereum/ERCs#2128</a>. Once that pull request merges, the canonical
copy will be at eips.ethereum.org/EIPS/eip-{html.escape(meta['eip'])}.</p>
<div class="table-wrap"><table class="eip-header">
{rows}
</table></div>
</header>
'''


def toc(rendered):
  items, open_sub = [], False
  for level, ident, inner in re.findall(r'<h([23]) id="([^"]+)">(.*?)</h\1>', rendered, re.S):
    if level == '2':
      items.append(('</ul></li>' if open_sub else '</li>') if items else '')
      items.append(f'<li><a href="#{ident}">{inner}</a>')
      open_sub = False
    else:
      items.append('' if open_sub else '<ul>')
      items.append(f'<li><a href="#{ident}">{inner}</a></li>')
      open_sub = True
  items.append('</ul></li>' if open_sub else '</li>')
  return f'<nav class="toc" aria-label="Contents">\n<p class="toc-title">Contents</p>\n<ul>{"".join(items)}</ul>\n</nav>\n'


def page(out, title, parts, layout, sha, dirty):
  body = ''
  for part in parts:
    if part.endswith('.md'):
      body += markdown_part(part, sha)
    else:
      body += (ROOT / part).read_text().removeprefix(SPDX)
  built = f'<a href="{REPO}/commit/{sha}"><code>{sha[:7]}</code></a>' + (' with local changes' if dirty else '')
  text = layout.removeprefix(SPDX)
  text = text.replace('{{title}}', html.escape(title)).replace('{{page}}', out.removesuffix('.html'))
  text = text.replace(f'<a href="{out}">', f'<a href="{out}" aria-current="page">')
  text = text.replace('{{commit}}', built).replace('{{content}}', body)
  return text


class Anchors(HTMLParser):
  """Collects the ids a page defines and the internal links it makes."""

  def __init__(self):
    super().__init__()
    self.ids, self.duplicates, self.links = set(), set(), []

  def handle_starttag(self, tag, attrs):
    for name, value in attrs:
      if name == 'id':
        (self.duplicates if value in self.ids else self.ids).add(value)
      if name in ('href', 'src') and value and not re.match(r'(https?:|mailto:|data:)', value):
        self.links.append(value)


def check_links():
  pages = {}
  for path in OUT.glob('*.html'):
    parser = Anchors()
    parser.feed(path.read_text())
    pages[path.name] = parser
    for ident in sorted(parser.duplicates):
      fail(f'{path.name}: id "{ident}" is used more than once')
  for name, parser in sorted(pages.items()):
    for link in parser.links:
      target, _, fragment = link.partition('#')
      target = target or name
      if not (OUT / target).exists():
        fail(f'{name}: link {link} points to {target}, which the site does not have')
      elif fragment and target in pages and fragment not in pages[target].ids:
        fail(f'{name}: link {link} points to #{fragment}, which {target} does not have')


def main():
  sha, dirty = commit()
  layout = (SITE / 'layout.html').read_text()
  if OUT.exists():
    shutil.rmtree(OUT)
  OUT.mkdir()
  shutil.copy(SITE / 'style.css', OUT / 'style.css')
  for out, title, parts in PAGES:
    (OUT / out).write_text(page(out, title, parts, layout, sha, dirty))
  check_links()
  if errors:
    print('\n'.join(f'build-site: {e}' for e in errors), file=sys.stderr)
    sys.exit(1)
  print(f'build-site: {len(PAGES)} pages in _site/, links checked, built from {sha[:7]}{" with local changes" if dirty else ""}')


if __name__ == '__main__':
  main()
