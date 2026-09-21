import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { relative } from 'node:path';
import { parse } from 'yaml';
import { files, document, examples } from './content.mjs';
import { base, locales } from '../site.config.mjs';

const root = 'src/content/docs';
const pages = locales.map(
  (locale) =>
    new Map(
      files(`${root}/${locale}`, /\.mdx?$/).map((path) => [
        relative(`${root}/${locale}`, path),
        document(path),
      ]),
    ),
);
assert(pages[0].size > 0, 'No published pages');
assert.deepEqual(
  [...pages[0].keys()].sort(),
  [...pages[1].keys()].sort(),
  'Japanese and English page paths must match',
);

for (const [index, locale] of locales.entries()) {
  for (const [path, { data, body }] of pages[index]) {
    assert(
      data.title?.trim() && data.description?.trim(),
      `${locale}/${path}: title and description are required`,
    );
    assert(!/^# /m.test(body), `${locale}/${path}: Starlight owns the h1`);
    assert(
      !/\b(?:TODO|TBD|Lorem ipsum)\b/.test(body),
      `${locale}/${path}: unfinished content`,
    );
    const other = locales.find((value) => value !== locale);
    assert(
      !body.includes(`${base}/${other}/`),
      `${locale}/${path}: content links should stay in the selected language`,
    );
    for (const { language, code } of examples(body)) {
      if (language === 'json') JSON.parse(code);
      if (language === 'yaml') parse(code);
    }
  }
}

for (const [path, { body }] of pages[0]) {
  assert.deepEqual(
    examples(body),
    examples(pages[1].get(path).body),
    `${path}: code examples must match in both languages`,
  );
}

const workflow = parse(
  readFileSync('public/examples/observe-edit.yaml', 'utf8'),
);
const documented = examples(pages[0].get('guides/workflows.md').body).find(
  ({ language }) => language === 'yaml',
);
assert.deepEqual(
  parse(documented.code),
  workflow,
  'The downloadable workflow must match the guide',
);
console.log(
  `Content checked: ${pages[0].size} pages per language, matching examples, valid JSON/YAML, and matching download.`,
);
