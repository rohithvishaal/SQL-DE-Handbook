import { defineConfig } from 'vitepress';
import { githubSlugify } from './handbook/markdownConfig';

export default defineConfig({
  srcDir: '.',
  srcExclude: ['AGENTS.md', 'docs/**/*.md', 'exercises/*/solutions.md'],
  title: 'SQL DE Handbook',
  description:
    'Data Engineering SQL Handbook with spaced-repetition active recall, interactive quizzes, and cloud dialect references',
  cleanUrls: false,
  ignoreDeadLinks: [/\.sql$/],
  markdown: {
    anchor: {
      slugify: githubSlugify,
    },
    headers: {
      slugify: githubSlugify,
    },
    toc: {
      slugify: githubSlugify,
    },
  },
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    ['meta', { name: 'color-scheme', content: 'light dark' }],
  ],
  themeConfig: {
    outline: false,
    nav: [
      { text: 'Today Hub', link: '/' },
      { text: 'Cheatsheets', link: '/cheatsheets/01-foundations-syntax' },
      { text: 'Exercises', link: '/exercises/README' },
      { text: 'Interviews', link: '/interviews/README' },
      { text: 'Projects', link: '/projects/README' },
    ],
    sidebar: [
      {
        text: 'Cheatsheets',
        items: [
          { text: '01 · Foundations & NULLs', link: '/cheatsheets/01-foundations-syntax' },
          { text: '02 · Window Functions', link: '/cheatsheets/02-window-functions' },
          { text: '03 · DE Patterns & SCD2', link: '/cheatsheets/03-de-patterns' },
          { text: '04 · Cloud DW Matrix', link: '/cheatsheets/04-cloud-dw-matrix' },
          { text: '05 · Query Performance', link: '/cheatsheets/05-performance-tuning' },
        ],
      },
      {
        text: 'Exercises',
        collapsed: true,
        items: [
          { text: 'Overview', link: '/exercises/README' },
          { text: '01 · Foundations Quiz', link: '/exercises/01-foundations/quiz' },
          { text: '02 · Window Functions Quiz', link: '/exercises/02-window-functions/quiz' },
          { text: '03 · DE Patterns Quiz', link: '/exercises/03-de-patterns/quiz' },
          { text: '04 · Cloud DW Quiz', link: '/exercises/04-cloud-dw/quiz' },
          { text: '05 · Performance Quiz', link: '/exercises/05-performance/quiz' },
        ],
      },
      {
        text: 'Interviews (01–15)',
        collapsed: true,
        items: [
          { text: 'Masterclass Index', link: '/interviews/README' },
          { text: '01 · Cohort Retention', link: '/interviews/01-cohort-retention' },
          { text: '02 · Consecutive Streaks', link: '/interviews/02-consecutive-streaks' },
          { text: '03 · Top N per Category', link: '/interviews/03-top-n-per-category' },
          { text: '04 · Overlapping Intervals', link: '/interviews/04-overlapping-intervals' },
          { text: '05 · Attribution Modeling', link: '/interviews/05-attribution-modeling' },
          { text: '06 · Circular Transactions', link: '/interviews/06-circular-transactions' },
          { text: '07 · Unmatched Records', link: '/interviews/07-unmatched-records' },
          { text: '08 · Running Totals Budget', link: '/interviews/08-running-totals-budget' },
          { text: '09 · Pivot & Unpivot', link: '/interviews/09-pivot-unpivot' },
          { text: '10 · Event Funnel', link: '/interviews/10-event-funnel' },
          { text: '11 · Median & Percentile', link: '/interviews/11-median-percentile' },
          { text: '12 · Hierarchical Rollup', link: '/interviews/12-hierarchical-rollup' },
          { text: '13 · Dedup & MERGE', link: '/interviews/13-dedup-merge' },
          { text: '14 · Time-Weighted Avg', link: '/interviews/14-time-weighted-avg' },
          { text: '15 · Slowly Changing Join', link: '/interviews/15-slowly-changing-join' },
        ],
      },
      {
        text: 'Capstone Projects',
        collapsed: true,
        items: [
          { text: 'Projects Index', link: '/projects/README' },
          { text: '01 · Clickstream Sessionization', link: '/projects/01-clickstream-sessionization/requirements' },
          { text: '02 · FinTech SCD2 Ledger', link: '/projects/02-fintech-scd2-ledger/requirements' },
          { text: '03 · SaaS MRR Waterfall', link: '/projects/03-saas-mrr-waterfall/requirements' },
          { text: '04 · IoT Telemetry Anomaly', link: '/projects/04-iot-telemetry-anomaly/requirements' },
        ],
      },
    ],
    search: {
      provider: 'local',
    },
  },
});
