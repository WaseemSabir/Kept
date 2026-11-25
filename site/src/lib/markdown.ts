// Small builders for the Markdown the site serves to assistants (the
// Markdown twins, llms.txt, llms-full.txt). Strings come from src/data in
// the inline convention and go through toMarkdown; these only arrange them.

import { escapeMarkdown, toMarkdown, type MarkdownOptions } from './inline.ts';

type Block = string | false | undefined;

/** Blocks separated by one blank line. Empty blocks are dropped. */
export function blocks(...items: Block[]): string {
  return items.filter((item): item is string => Boolean(item)).join('\n\n');
}

/** A whole document: blocks, ending in a newline. */
export function document(...items: Block[]): string {
  return `${blocks(...items)}\n`;
}

export function heading(level: 1 | 2 | 3, text: string): string {
  return `${'#'.repeat(level)} ${escapeMarkdown(text)}`;
}

export function paragraphs(sources: readonly string[], options?: MarkdownOptions): string {
  return sources.map((source) => toMarkdown(source, options)).join('\n\n');
}

/** A label / value list (the site's fact lists): "- **Keeps**: What you copy…". */
export function factList(items: readonly { label: string; value: string }[], options?: MarkdownOptions): string {
  return items.map(({ label, value }) => `- **${escapeMarkdown(label)}**: ${toMarkdown(value, options)}`).join('\n');
}

/** A numbered list, for steps. */
export function numberedList(sources: readonly string[], options?: MarkdownOptions): string {
  return sources.map((source, index) => `${index + 1}. ${toMarkdown(source, options)}`).join('\n');
}

/** A bulleted list of links with a note each, as llms.txt has them: "- [Name](url): note". */
export function linkList(links: readonly { name: string; url: string; note: string }[]): string {
  return links.map(({ name, url, note }) => `- [${escapeMarkdown(name)}](${url}): ${escapeMarkdown(note)}`).join('\n');
}

/** A table. Cells are Markdown already; a "|" in one is escaped so it can't split the row. */
export function table(head: readonly string[], rows: readonly (readonly string[])[]): string {
  const row = (cells: readonly string[]) => `| ${cells.map((cell) => cell.replaceAll('|', '\\|')).join(' | ')} |`;
  return [row(head), row(head.map(() => '---')), ...rows.map(row)].join('\n');
}

/** An image with its alt text, and the caption under it as a paragraph. */
export function figure(url: string, alt: string, caption: string): string {
  return `![${escapeMarkdown(alt)}](${url})\n\n${escapeMarkdown(caption)}`;
}
