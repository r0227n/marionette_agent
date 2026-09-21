import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';

export function files(directory, suffix) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory()
      ? files(path, suffix)
      : suffix.test(entry.name)
        ? [path]
        : [];
  });
}

export function document(path) {
  const text = readFileSync(path, 'utf8');
  const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/.exec(text);
  if (!match) throw new Error(`${path}: missing frontmatter`);
  return { data: parse(match[1]), body: match[2] };
}

export function examples(body) {
  return [...body.matchAll(/^```([\w-]+)[^\n]*\n([\s\S]*?)^```/gm)].map(
    ([, language, code]) => ({ language, code: code.trim() }),
  );
}
