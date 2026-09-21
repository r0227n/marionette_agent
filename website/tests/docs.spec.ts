import { test, expect } from '@playwright/test';

const base = '/marionette_agent';

for (const locale of ['ja', 'en']) {
  test(`${locale}: home, deep links, and language switch`, async ({
    page,
  }, testInfo) => {
    const failures: string[] = [];
    page.on('pageerror', (error) => failures.push(error.message));
    page.on('response', (response) => {
      if (
        response.url().startsWith('http://127.0.0.1:4321') &&
        response.status() >= 400
      )
        failures.push(`${response.status()} ${response.url()}`);
    });
    await page.goto(`${base}/${locale}/`);
    await expect(page.locator('h1')).toBeVisible();
    await page.screenshot({
      path: testInfo.outputPath(`home-${locale}.png`),
      fullPage: true,
    });
    await page.locator('.hero a').first().click();
    await expect(page).toHaveURL(
      `${base}/${locale}/getting-started/quick-start/`,
    );
    await page.reload();
    await expect(page.locator('h1')).toContainText(
      locale === 'ja' ? '最初の操作' : 'first interaction',
    );
    await page.screenshot({
      path: testInfo.outputPath(`guide-${locale}.png`),
    });
    const other = locale === 'ja' ? 'en' : 'ja';
    await page
      .locator('starlight-lang-select select:visible')
      .selectOption(`${base}/${other}/getting-started/quick-start/`);
    await expect(page).toHaveURL(
      `${base}/${other}/getting-started/quick-start/`,
    );
    await expect(page.locator('html')).toHaveAttribute('lang', other);
    expect(failures).toEqual([]);
  });

  test(`${locale}: static search finds text in the selected language`, async ({
    page,
  }, testInfo) => {
    await page.goto(`${base}/${locale}/`);
    await page.locator('site-search button[data-open-modal]').click();
    const input = page.getByRole('dialog').getByRole('textbox');
    await input.fill(locale === 'ja' ? '録画' : 'recording');
    const results = page.locator('.pagefind-ui__result-link');
    await expect(results.first()).toBeVisible();
    await expect(page.locator('.pagefind-ui__message')).toContainText(
      locale === 'ja' ? '件' : 'results for',
    );
    for (const href of await results.evaluateAll((links) =>
      links.map((link) => link.getAttribute('href')),
    )) {
      expect(href).toContain(`${base}/${locale}/`);
    }
    await page.screenshot({
      path: testInfo.outputPath(`search-${locale}.png`),
    });
    await input.fill('STALE_REF');
    await expect(
      results
        .filter({
          hasText:
            locale === 'ja' ? /トラブル|出力/ : /Troubleshooting|output/i,
        })
        .first(),
    ).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator('site-search dialog')).not.toBeVisible();
  });

  test(`${locale}: mobile navigation and long code stay within the viewport`, async ({
    page,
  }, testInfo) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${base}/${locale}/getting-started/installation/`);
    await expect(page.locator('h1')).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: testInfo.outputPath(`mobile-${locale}.png`),
      fullPage: true,
    });
    await page.locator('button[popovertarget="starlight__sidebar"]').click();
    const link = page.locator('#starlight__sidebar a').filter({
      hasText: locale === 'ja' ? 'コマンド一覧' : 'Command reference',
    });
    await link.click();
    await expect(page).toHaveURL(`${base}/${locale}/reference/commands/`);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
  });
}

test('root entry and downloadable workflow work under the Pages base', async ({
  page,
  request,
}) => {
  await page.goto(`${base}/`);
  await expect(page).toHaveURL(`${base}/ja/`);
  const download = await request.get(`${base}/examples/observe-edit.yaml`);
  expect(download.ok()).toBe(true);
  expect(await download.text()).toContain('name: observe-edit');
});

test('keyboard navigation and code copying work', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto(`${base}/en/getting-started/installation/`);
  await page.keyboard.press('Tab');
  await expect(
    page.getByRole('link', { name: 'Skip to content' }),
  ).toBeFocused();
  await page.keyboard.press('Enter');
  await page.locator('.expressive-code .copy button').first().click();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toContain(
    'git clone --branch develop',
  );
});

test('404 offers working entries for both languages', async ({ page }) => {
  const response = await page.goto(`${base}/missing-page/`);
  expect(response?.status()).toBe(404);
  await expect(page.locator('h1')).toContainText('ページが見つかりません');
  await page.getByRole('link', { name: 'English home' }).click();
  await expect(page).toHaveURL(`${base}/en/`);
});
