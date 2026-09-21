import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import GithubSlugger from 'github-slugger';
import { fromMarkdown } from 'mdast-util-from-markdown';
import { files, document, examples } from './content.mjs';
import { base, site } from '../site.config.mjs';

const root = resolve('..');
// Current contracts are paired; historical research and agent workflows are separate.
const pairs = [
  ['README.md', 'README.md'],
  ['SPEC.md', 'SPEC.ja.md'],
  ['ARCHITECTURE.md', 'ARCHITECTURE.ja.md'],
  ['cli-reference.md', 'cli-reference.ja.md'],
  ['cli-parity.md', 'cli-parity.ja.md'],
  ['workflow-file-spec.md', 'workflow-file-spec.ja.md'],
  ['headless.md', 'headless.ja.md'],
  ['command-contract.md', 'command-contract.ja.md'],
  ['documentation.md', 'documentation.ja.md'],
];
const paired = new Set();
const explicitIds = (text) =>
  [...text.matchAll(/<a id="([^"]+)"/g)].map((match) => match[1]).sort();
assert.deepEqual(
  readdirSync('../docs/ja')
    .filter((name) => name.endsWith('.md'))
    .sort(),
  pairs.map(([, ja]) => ja).sort(),
  'Every Japanese supplement must have a registered English counterpart',
);
for (const [en, ja] of pairs) {
  const paths = [resolve(root, 'docs', en), resolve(root, 'docs/ja', ja)];
  const texts = paths.map((path) => readFileSync(path, 'utf8'));
  paths.forEach((path) => paired.add(path));
  assert.deepEqual(
    examples(texts[0]),
    examples(texts[1]),
    `${en}: examples differ`,
  );
  assert.deepEqual(
    explicitIds(texts[0]),
    explicitIds(texts[1]),
    `${en}: anchors differ`,
  );
  assert(
    texts[0].includes(`](ja/${ja})`),
    `${en}: missing Japanese counterpart link`,
  );
  assert(
    texts[1].includes(`](../${en})`),
    `${ja}: missing English counterpart link`,
  );
}

function* walk(node) {
  yield node;
  for (const child of node.children ?? []) yield* walk(child);
}
const inlineText = (node) =>
  node.value ?? node.alt ?? (node.children ?? []).map(inlineText).join('');
const parsed = new Map();
function markdown(path) {
  if (parsed.has(path)) return parsed.get(path);
  let body = readFileSync(path, 'utf8');
  let title;
  if (path.includes('/website/src/content/docs/')) {
    const page = document(path);
    body = page.body;
    title = page.data.title;
  }
  const nodes = [...walk(fromMarkdown(body))];
  const slugger = new GithubSlugger();
  const anchors = new Set(explicitIds(body));
  if (title) anchors.add(slugger.slug(title));
  for (const node of nodes) {
    if (node.type === 'heading') anchors.add(slugger.slug(inlineText(node)));
  }
  const result = { nodes, anchors };
  parsed.set(path, result);
  return result;
}

// Include tracked incoming links without walking dependency/build directories.
const tracked = execFileSync('git', ['ls-files', '-z', '--', '*.md'], {
  cwd: root,
  encoding: 'utf8',
})
  .split('\0')
  .filter(Boolean)
  .map((path) => resolve(root, path));
const publicPages = files('src/content/docs', /\.mdx?$/).map((path) =>
  resolve(path),
);
const owned = new Set([
  ...paired,
  ...publicPages,
  resolve(root, 'README.md'),
  resolve(root, 'AGENTS.md'),
  resolve('README.md'),
]);
const sources = new Set([...tracked, ...owned]);
const repoUrl = 'https://github.com/r0227n/marionette_agent/blob/develop/';
let checked = 0;
const failures = [];
for (const source of sources) {
  if (!existsSync(source)) continue;
  for (const node of markdown(source).nodes) {
    if (!['link', 'image', 'definition'].includes(node.type)) continue;
    let url = node.url;
    if (url.startsWith(repoUrl)) url = resolve(root, url.slice(repoUrl.length));
    else if (url.startsWith(`${site}${base}/`)) url = url.slice(site.length);
    if (/^[a-z][a-z\d+.-]*:/i.test(url)) continue;
    let [path, fragment] = url.split('#');
    path = decodeURIComponent(path.split('?')[0]);
    if (path === base || path.startsWith(`${base}/`)) {
      const route = path.slice(base.length).replace(/^\/|\/$/g, '');
      if (!route) continue; // Root redirect is covered by the browser test.
      const candidates = [
        `website/src/content/docs/${route}.md`,
        `website/src/content/docs/${route}.mdx`,
        `website/src/content/docs/${route}/index.mdx`,
        `website/public/${route}`,
      ].map((value) => resolve(root, value));
      path = candidates.find(existsSync) ?? candidates[0];
    }
    const target = path ? resolve(dirname(source), path) : source;
    // Enforce all links owned here and every incoming link to paired docs.
    if (!owned.has(source) && !paired.has(target)) continue;
    const label = `${relative(root, source)}:${node.position.start.line} -> ${node.url}`;
    if (!existsSync(target)) failures.push(`Missing file: ${label}`);
    else if (fragment && /\.mdx?$/.test(target) && statSync(target).isFile()) {
      if (!markdown(target).anchors.has(decodeURIComponent(fragment))) {
        failures.push(`Missing anchor: ${label}`);
      }
    }
    checked++;
  }
}
assert.equal(failures.length, 0, failures.join('\n'));
console.log(
  `Repository docs checked: ${pairs.length} bilingual pairs and ${checked} local links (including incoming references).`,
);
