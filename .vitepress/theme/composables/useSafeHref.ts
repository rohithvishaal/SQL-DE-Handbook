import * as vitepress from 'vitepress';

export function safeHref(path?: string): string {
  const safePath = path && path.length > 0 ? path : '/';
  const normalized =
    safePath.endsWith('/') || safePath.endsWith('.html') ? safePath : `${safePath}.html`;
  return typeof vitepress.withBase === 'function' ? vitepress.withBase(normalized) : normalized;
}
