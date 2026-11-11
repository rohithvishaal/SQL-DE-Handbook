import fs from 'node:fs';
import path from 'node:path';
import { createMarkdownRenderer, resolveConfig, type Header, type MarkdownEnv } from 'vitepress';
import { describe, expect, it } from 'vitest';

const REPO_ROOT = path.resolve(__dirname, '../..');

function collectMarkdownFiles(dir: string): string[] {
  const results: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.') || entry.name === 'node_modules' || entry.name === 'docs') continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...collectMarkdownFiles(fullPath));
    } else if (entry.name.endsWith('.md') && entry.name !== 'AGENTS.md' && entry.name !== 'GLOSSARY.md') {
      results.push(fullPath);
    }
  }
  return results;
}

function collectHeaderSlugs(headers: Header[] | undefined): string[] {
  if (!headers) return [];
  const slugs: string[] = [];
  for (const h of headers) {
    slugs.push(h.slug);
    slugs.push(...collectHeaderSlugs(h.children));
  }
  return slugs;
}

describe('Markdown in-page anchor links (Regression for broken #tag redirects)', () => {
  it('resolves every #hash link and outline header slug to a rendered heading id across all handbook files', async () => {
    const config = await resolveConfig(REPO_ROOT, 'build');
    const md = await createMarkdownRenderer(REPO_ROOT, config.markdown, config.site.base);
    const markdownFiles = collectMarkdownFiles(REPO_ROOT);

    const broken: Array<{ file: string; kind: 'hash-link' | 'outline-header'; target: string }> = [];

    for (const file of markdownFiles) {
      const rel = path.relative(REPO_ROOT, file);
      const raw = fs.readFileSync(file, 'utf8');
      const env: MarkdownEnv = { path: file, relativePath: rel, cleanUrls: false };
      const html = md.render(raw, env);
      const ids = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]));

      for (const match of html.matchAll(/href="#([^"]+)"/g)) {
        const target = decodeURIComponent(match[1]);
        if (!ids.has(target)) {
          broken.push({ file: rel, kind: 'hash-link', target });
        }
      }

      for (const slug of collectHeaderSlugs(env.headers)) {
        if (!ids.has(slug)) {
          broken.push({ file: rel, kind: 'outline-header', target: slug });
        }
      }
    }

    expect(markdownFiles.length).toBeGreaterThanOrEqual(39);
    expect(broken).toEqual([]);
  });
});
