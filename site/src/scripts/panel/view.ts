// The panel's DOM: finds the server-rendered parts and brings them in line
// with the state. Rows and previews are the ones the page was built with,
// moved, refilled and shown or hidden; nothing here parses HTML, and what
// the visitor types only ever reaches the page as text nodes.
import { accessibleLabel, type Clip, type FilterId } from '../../data/clips.ts';
import { rowRuns, type Run } from './highlight.ts';
import type { EmptyState, FooterHints } from './wording.ts';

export interface PanelElements {
  panel: HTMLElement;
  field: HTMLInputElement;
  list: HTMLElement;
  /** Every row the page was built with, by clip id. */
  rows: Map<string, HTMLElement>;
  previews: Map<string, HTMLElement>;
  filters: HTMLButtonElement[];
  hints: Map<string, HTMLButtonElement>;
  emptyTitle: HTMLElement;
  emptyHint: HTMLElement;
}

/** What the panel shows. */
export interface PanelState {
  list: readonly Clip[];
  selectedIndex: number | undefined;
  tokens: readonly string[];
  filter: FilterId;
  sectionBreak: number | undefined;
  empty: EmptyState | undefined;
  footer: FooterHints;
}

function byData<T extends HTMLElement>(root: ParentNode, selector: string, attribute: string, type: new () => T) {
  const found = new Map<string, T>();
  for (const element of root.querySelectorAll(selector)) {
    const key = element.getAttribute(attribute);
    if (element instanceof type && key) found.set(key, element);
  }
  return found;
}

export function findElements(root: ParentNode): PanelElements | undefined {
  const panel = root.querySelector('[data-panel]');
  const field = root.querySelector('[data-panel-search]');
  const list = root.querySelector('#panel-list');
  const emptyTitle = root.querySelector('[data-empty-title]');
  const emptyHint = root.querySelector('[data-empty-hint]');
  if (
    !(panel instanceof HTMLElement) ||
    !(field instanceof HTMLInputElement) ||
    !(list instanceof HTMLElement) ||
    !(emptyTitle instanceof HTMLElement) ||
    !(emptyHint instanceof HTMLElement)
  ) {
    return undefined;
  }
  return {
    panel,
    field,
    list,
    rows: byData(list, '[role="option"][data-clip]', 'data-clip', HTMLElement),
    previews: byData(panel, '[data-preview]', 'data-preview', HTMLElement),
    filters: [...panel.querySelectorAll('[data-filter]')].filter((item) => item instanceof HTMLButtonElement),
    hints: byData(panel, '[data-hint]', 'data-hint', HTMLButtonElement),
    emptyTitle,
    emptyHint,
  };
}

function setText(element: Element | null, text: string): void {
  if (element && element.textContent !== text) element.textContent = text;
}

function setAttribute(element: Element, name: string, value: string | undefined): void {
  if (value === undefined) element.removeAttribute(name);
  else if (element.getAttribute(name) !== value) element.setAttribute(name, value);
}

/** Runs as text, the matching ones in <b>. */
function runNodes(runs: readonly Run[]): Node[] {
  return runs.map((run) => {
    if (!run.match) return document.createTextNode(run.text);
    const bold = document.createElement('b');
    bold.textContent = run.text;
    return bold;
  });
}

/** What each row's text was last filled from, so it's only rebuilt when that changes. */
const filledFrom = new WeakMap<Element, string>();

function fillRowText(row: HTMLElement, clip: Clip, tokens: readonly string[]): void {
  const text = row.querySelector('.text');
  if (!text) return;
  const key = [clip.name ?? '', clip.title, ...tokens].join('\u0000');
  if (filledFrom.get(text) === key) return;
  const { primary, secondary } = rowRuns(clip, tokens);
  const nodes = runNodes(primary);
  if (secondary.length > 0) {
    const muted = document.createElement('span');
    muted.className = 'secondary';
    muted.append(...runNodes(secondary));
    nodes.push(muted);
  }
  text.replaceChildren(...nodes);
  filledFrom.set(text, key);
}

function renderRow(row: HTMLElement, clip: Clip, index: number, state: PanelState): void {
  setAttribute(row, 'aria-selected', String(index === state.selectedIndex));
  setAttribute(row, 'aria-label', accessibleLabel(clip));
  setAttribute(row, 'data-pinned', clip.pinned ? '' : undefined);
  setAttribute(row, 'data-section-start', index === state.sectionBreak ? '' : undefined);
  setText(row.querySelector('.number'), index < 9 ? String(index + 1) : '');
  setText(row.querySelector('.age'), clip.age);
  fillRowText(row, clip, state.tokens);
}

/** Scrolls the list, and only the list, so the selected row shows, with the list's 4 px inset. */
function revealSelection(elements: PanelElements, row: HTMLElement | undefined): void {
  const { list } = elements;
  if (!row) return;
  const inset = 4;
  const top = row.offsetTop - inset;
  const bottom = row.offsetTop + row.offsetHeight + inset;
  if (top < list.scrollTop) list.scrollTop = top;
  else if (bottom > list.scrollTop + list.clientHeight) list.scrollTop = bottom - list.clientHeight;
}

function renderFooter(hints: Map<string, HTMLButtonElement>, footer: FooterHints): void {
  for (const name of ['paste', 'paste-plain', 'copy', 'pin']) {
    const hint = hints.get(name);
    if (hint) hint.hidden = !footer.actions;
  }
  const pin = hints.get('pin');
  if (pin) setText(pin.querySelector('[data-hint-label]'), footer.pin);
  const remove = hints.get('delete');
  if (remove) remove.hidden = !footer.delete;
  const escape = hints.get('esc');
  if (escape) {
    escape.hidden = footer.esc === undefined;
    if (footer.esc) setText(escape.querySelector('[data-hint-label]'), footer.esc);
  }
}

export function render(elements: PanelElements, state: PanelState): void {
  const { panel, field, list, rows, previews } = elements;
  const selected = state.selectedIndex === undefined ? undefined : state.list[state.selectedIndex];

  // The rows, in the list's order; the ones not listed leave the listbox.
  const shown = state.list.flatMap((clip) => rows.get(clip.id) ?? []);
  const inOrder = shown.length === list.children.length && shown.every((row, index) => list.children[index] === row);
  if (!inOrder) list.replaceChildren(...shown);
  state.list.forEach((clip, index) => {
    const row = rows.get(clip.id);
    if (row) renderRow(row, clip, index, state);
  });

  // The selection: the combobox names it, the preview shows it.
  setAttribute(field, 'aria-activedescendant', selected ? `clip-${selected.id}` : undefined);
  setAttribute(panel, 'data-selected', selected?.id);
  for (const [id, preview] of previews) {
    preview.hidden = id !== selected?.id;
    if (id === selected?.id) {
      const copied = selected.facts.find((fact) => fact.label === 'Copied');
      if (copied) setText(preview.querySelector('[data-fact="Copied"]'), copied.value);
    }
  }

  // Nothing to list: the app's words, in the list's column or across the panel.
  // Set before scrolling, since a hidden list has no rows to measure.
  setAttribute(panel, 'data-empty', state.empty ? (state.empty.spansPanel ? 'panel' : 'list') : undefined);
  setText(elements.emptyTitle, state.empty?.title ?? '');
  setText(elements.emptyHint, state.empty?.hint ?? '');
  elements.emptyHint.hidden = !state.empty?.hint;
  // The combobox's list is collapsed while the empty state stands in for it.
  setAttribute(field, 'aria-expanded', String(!state.empty));
  revealSelection(elements, selected && rows.get(selected.id));

  setAttribute(panel, 'data-filter', state.filter);
  for (const button of elements.filters) {
    setAttribute(button, 'aria-pressed', String(button.dataset.filter === state.filter));
  }
  renderFooter(elements.hints, state.footer);
}
