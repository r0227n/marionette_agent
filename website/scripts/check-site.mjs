import assert from 'node:assert/strict';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { resolve, relative } from 'node:path';
import { load } from 'cheerio';
import { files } from './content.mjs';
import { site, base, locales } from '../site.config.mjs';

const root = resolve('dist');
const htmlFiles = files(root, /\.html$/);
const pages = new Map(
  htmlFiles.map((path) => [path, load(readFileSync(path, 'utf8'))]),
);
let checkedLinks = 0;
let translatedPages = 0;

function targetFile(pathname) {
  assert(
    pathname === base || pathname.startsWith(`${base}/`),
    `URL escapes Pages base: ${pathname}`,
  );
  const path = resolve(
    root,
    `.${decodeURIComponent(pathname.slice(base.length) || '/')}`,
  );
  assert(
    path.startsWith(`${root}/`) || path === root,
    `URL escapes output directory: ${pathname}`,
  );
  if (existsSync(path) && statSync(path).isDirectory())
    return resolve(path, 'index.html');
  return path;
}

for (const [path, $] of pages) {
  const relativePath = relative(root, path).replaceAll('\\', '/');
  const pathname = `${base}/${relativePath.replace(/index\.html$/, '')}`;
  const pageURL = new URL(pathname, site);
  const locale = relativePath.split('/')[0];
  if (locales.includes(locale)) {
    translatedPages++;
    assert.equal($('html').attr('lang'), locale, `${pathname}: wrong lang`);
    assert.equal($('h1').length, 1, `${pathname}: expected one h1`);
    assert($('title').text().trim(), `${pathname}: missing title`);
    assert(
      $('meta[name="description"]').attr('content')?.trim(),
      `${pathname}: missing description`,
    );
    assert.equal(
      $('link[rel="canonical"]').attr('href'),
      pageURL.href,
      `${pathname}: wrong canonical`,
    );
    for (const translation of locales) {
      const expected = pageURL.href.replace(
        `${base}/${locale}/`,
        `${base}/${translation}/`,
      );
      assert.equal(
        $(`link[rel="alternate"][hreflang="${translation}"]`).attr('href'),
        expected,
        `${pathname}: missing or incorrect alternate ${translation}`,
      );
    }
    assert(
      $('starlight-lang-select select').length > 0,
      `${pathname}: missing language switch`,
    );
    $('starlight-lang-select select').each((_, select) => {
      assert.equal(
        $(select).find('option').length,
        locales.length,
        `${pathname}: missing language option`,
      );
    });
  }

  $('[href], [src]').each((_, element) => {
    const value = $(element).attr('href') ?? $(element).attr('src');
    if (!value || /^(?:mailto:|tel:|data:|javascript:)/.test(value)) return;
    const url = new URL(value, pageURL);
    if (url.origin !== site) return;
    const target = targetFile(url.pathname);
    assert(existsSync(target), `${pathname}: broken link or asset ${value}`);
    if (url.hash && pages.has(target)) {
      const id = decodeURIComponent(url.hash.slice(1));
      const targetPage = pages.get(target);
      assert(
        targetPage('[id]')
          .toArray()
          .some((node) => targetPage(node).attr('id') === id),
        `${pathname}: missing anchor ${value}`,
      );
    }
    checkedLinks++;
  });
}

const sourcePages = files('src/content/docs', /\.mdx?$/).length;
assert.equal(
  translatedPages,
  sourcePages,
  'Every published source page must have a localized output',
);
assert(
  existsSync(resolve(root, 'pagefind/pagefind.js')),
  'Missing static search bundle',
);
assert(existsSync(resolve(root, 'sitemap-index.xml')), 'Missing sitemap');
console.log(
  `Built site checked: ${translatedPages} localized pages and ${checkedLinks} internal links/assets, including fragments and SEO metadata.`,
);
