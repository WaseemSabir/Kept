// Copy in src/data is plain strings with a tiny Markdown subset, so the same
// strings can be rendered as HTML here and, later, as plain text (structured
// data) or Markdown (llms.txt):
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

/** The words alone: "Press ⇧⌘V in any app." */
export function toPlainText(source: string): string {
  return parseInline(source)
    .map((segment) => segment.text)
    .join('');
}

/** Markdown: key caps become code spans. */
export function toMarkdown(source: string): string {
  return parseInline(source)
    .map((segment) => {
      switch (segment.type) {
        case 'text':
          return segment.text;
        case 'code':
        case 'key':
          return `\`${segment.text}\``;
        case 'strong':
          return `**${segment.text}**`;
        case 'link':
          return `[${segment.text}](${segment.href})`;
      }
    })
    .join('');
}
