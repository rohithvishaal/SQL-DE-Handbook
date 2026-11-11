export interface HandbookModuleMeta {
  moduleId: string;
  title: string;
  link: string;
}

export const HANDBOOK_MODULES: readonly HandbookModuleMeta[] = [
  { moduleId: 'm1', title: '01 · Foundations & NULLs', link: '/cheatsheets/01-foundations-syntax' },
  { moduleId: 'm2', title: '02 · Window Functions', link: '/cheatsheets/02-window-functions' },
  { moduleId: 'm3', title: '03 · DE Patterns & SCD2', link: '/cheatsheets/03-de-patterns' },
  { moduleId: 'm4', title: '04 · Cloud DW Dialects', link: '/cheatsheets/04-cloud-dw-matrix' },
  { moduleId: 'm5', title: '05 · Query Performance', link: '/cheatsheets/05-performance-tuning' },
  { moduleId: 'm6', title: '06 · Interviews & Capstones', link: '/interviews/README' },
];
