import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { site, base, defaultLocale } from './site.config.mjs';

const section = (label, ja, items) => ({
  label,
  translations: { ja },
  items: items.map((slug) => ({ slug })),
});

export default defineConfig({
  site,
  base,
  output: 'static',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'marionette-agent',
      description: 'Observe, operate, and verify Flutter apps from your agent.',
      logo: { src: './src/assets/mark.svg' },
      favicon: '/favicon.svg',
      disable404Route: true,
      defaultLocale,
      locales: {
        en: { label: 'English', lang: 'en' },
        ja: { label: '日本語', lang: 'ja' },
      },
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/r0227n/marionette_agent',
        },
      ],
      editLink: {
        baseUrl:
          'https://github.com/r0227n/marionette_agent/edit/develop/website/',
      },
      customCss: ['./src/styles/custom.css'],
      components: { Banner: './src/components/VersionBanner.astro' },
      sidebar: [
        section('Start here', 'はじめに', [
          'getting-started/overview',
          'getting-started/installation',
          'getting-started/quick-start',
          'getting-started/app-integration',
        ]),
        section('Core concepts', '基本を理解する', [
          'concepts/observation-loop',
          'concepts/targets',
          'concepts/sessions',
        ]),
        section('Guides', '目的から探す', [
          'guides/agents',
          'guides/workflows',
          'guides/capture',
          'guides/headless',
          'guides/manual-headless',
        ]),
        section('Reference', 'リファレンス', [
          'reference/commands',
          'reference/configuration',
          'reference/output',
          'reference/troubleshooting',
        ]),
      ],
    }),
  ],
});
