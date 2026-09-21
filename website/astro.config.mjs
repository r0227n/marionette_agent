import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { site, base } from './site.config.mjs';

const section = (label, en, items) => ({
  label,
  translations: { en },
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
      defaultLocale: 'ja',
      locales: {
        ja: { label: '日本語', lang: 'ja' },
        en: { label: 'English', lang: 'en' },
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
        section('はじめに', 'Start here', [
          'getting-started/overview',
          'getting-started/installation',
          'getting-started/quick-start',
          'getting-started/app-integration',
        ]),
        section('基本を理解する', 'Core concepts', [
          'concepts/observation-loop',
          'concepts/targets',
          'concepts/sessions',
        ]),
        section('目的から探す', 'Guides', [
          'guides/agents',
          'guides/workflows',
          'guides/capture',
          'guides/headless',
        ]),
        section('リファレンス', 'Reference', [
          'reference/commands',
          'reference/configuration',
          'reference/output',
          'reference/troubleshooting',
        ]),
      ],
    }),
  ],
});
