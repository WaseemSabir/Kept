// Copy in src/data is plain strings with a tiny Markdown subset, so the same
// strings can be rendered as HTML (Inline.astro), plain text (structured
// data) and Markdown (the Markdown twins and llms-full.txt):
//
//   `code`        a command, path or value     → <code>
//   **strong**    a button or setting's name   → <strong>
//   [text](url)   a link                       → <a>
//   {⌘P}          a shortcut                   → a key cap (<kbd>); Markdown `⌘P`
//
// No nesting and no escapes: none of the copy needs them.

export type Segment =
  | { type: 'text' | 'code' | 'strong' | 'key'; text: string }
  | { type: 'link'; text: string; href: string };

const pattern = /`([^`]+)`|\*\*([^*]+)\*\*|\[([^\]]+)\]\(([^)\s]+)\)|\{([^}]+)\}/g;

export function parseInline(source: string): Segment[] {
  const segments: Segment[] = [];
  let last = 0;
  for (const match of source.matchAll(pattern)) {
    const index = match.index ?? 0;
    if (index > last) segments.push({ type: 'text', text: source.slice(last, index) });
    const [, code, strong, linkText, href, key] = match;
    if (code !== undefined) segments.push({ type: 'code', text: code });
    else if (strong !== undefined) segments.push({ type: 'strong', text: strong });
    else if (linkText !== undefined && href !== undefined) segments.push({ type: 'link', text: linkText, href });
    else if (key !== undefined) segments.push({ type: 'key', text: key });
    last = index + match[0].length;
  }
  if (last < source.length) segments.push({ type: 'text', text: source.slice(last) });
  return segments;
}

/**
 * The copy joins key caps with no-break spaces so HTML wraps only where it
 * should (src/data/shortcuts.ts). Plain text and Markdown don't wrap that
 * way, so there they're ordinary spaces.
 */
const plainSpaces = (text: string): string => text.replaceAll(' ', ' ');

/** The words alone: "Press ⇧⌘V in any app." */
export function toPlainText(source: string): string {
  return plainSpaces(
    parseInline(source)
      .map((segment) => segment.text)
      .join(''),
  );
}

export interface MarkdownOptions {
  /** Resolves links like "/shortcuts" to absolute addresses on this origin, for text read out of context. */
  base?: string | URL;
}

/** Markdown: key caps become code spans, as in the README's tables. */
export function toMarkdown(source: string, options: MarkdownOptions = {}): string {
  return plainSpaces(
    parseInline(source)
      .map((segment) => {
        switch (segment.type) {
          case 'text':
            return escapeMarkdown(segment.text);
          case 'code':
          case 'key':
            return `\`${segment.text}\``;
          case 'strong':
            return `**${escapeMarkdown(segment.text)}**`;
          case 'link': {
            const relative = !/^[a-z][a-z\d+.-]*:/i.test(segment.href);
            const href = relative && options.base ? new URL(segment.href, options.base).href : segment.href;
            return `[${escapeMarkdown(segment.text)}](${href})`;
          }
        }
      })
      .join(''),
  );
}

/** Backslash-escapes the characters that would start emphasis, a link or HTML in running text. */
export function escapeMarkdown(text: string): string {
  return text.replace(/[\\*_[\]<`]/g, '\\$&');
}
