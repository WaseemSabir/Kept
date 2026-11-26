// The live panel: the state (the history, the query, the filter, the
// selection), the keys and clicks that change it, and the paste. Loaded by
// LivePanel.astro; without it the panel is the still the page was built as.
//
// Keys act only while focus is in the panel, except ⇧⌘V, which puts the
// keyboard there from anywhere on the page, the way it opens Kept. Nothing
// here reads or writes the visitor's clipboard.
import { clips, initialSelection, type Clip, type FilterId } from '../../data/clips.ts';
import { matchTokens } from './highlight.ts';
import {
  isPinned,
  keptIndex,
  movedIndex,
  pageSize,
  remove,
  sectionBreak,
  startingHistory,
  togglePin,
  type History,
} from './history.ts';
import {
  command as commandFor,
  composing,
  opensPanel,
  pastes,
  platformFrom,
  types,
  type Command,
  type Platform,
} from './keys.ts';
import { searchResults } from './search.ts';
import { findStage, motion, motionMs, reducesMotion, Stage } from './stage.ts';
import { findElements, render, type PanelElements } from './view.ts';
import { emptyState, footerHints, pasted, resultsPhrase, spoken } from './wording.ts';

/** How long a pasted clip sits on the line before the panel comes back by itself. */
const beatMs = 1200;
/** How long typing pauses before the number of results is announced. */
const settleMs = 600;

type Write = 'paste' | 'paste-plain' | 'copy';

const hintCommands: Record<string, Command> = {
  paste: 'paste',
  'paste-plain': 'paste-plain',
  copy: 'copy',
  pin: 'pin',
  delete: 'delete',
  esc: 'cancel',
};

function isFilterId(value: string | undefined): value is FilterId {
  return value === 'all' || value === 'pinned' || value === 'text' || value === 'links' || value === 'images' || value === 'files';
}

function isEditable(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable || target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement)
  );
}

/** The system the page runs on, from what the browser says about it. */
function currentPlatform(): Platform {
  const { userAgentData } = navigator as Navigator & { userAgentData?: { platform?: string } };
  return platformFrom({
    userAgentData: userAgentData?.platform,
    platform: navigator.platform,
    userAgent: navigator.userAgent,
  });
}

/** The parts of the page the panel works with. */
interface Parts {
  elements: PanelElements;
  stage: Stage;
  /** The panel with the lines under it: what ⇧⌘V scrolls into view, where Esc leaves the keyboard. */
  live: HTMLElement;
  status: HTMLElement;
  reset: HTMLButtonElement;
}

function findParts(root: Document): Parts | undefined {
  const elements = findElements(root);
  const live = root.querySelector('[data-live-panel]');
  const status = root.querySelector('[data-panel-status]');
  const reset = root.querySelector('[data-panel-reset]');
  const stage = elements && findStage(root, elements.panel);
  if (!elements || !stage || !(live instanceof HTMLElement) || !(status instanceof HTMLElement)) return undefined;
  if (!(reset instanceof HTMLButtonElement)) return undefined;
  return { elements, stage: new Stage(stage), live, status, reset };
}

/** Makes the panel work, if the page has one; sets <html data-scripted> once it does. */
export function startLivePanel(root: Document = document): void {
  // Once: a second start would handle every key and click twice.
  if (root.documentElement.hasAttribute('data-scripted')) return;
  const parts = findParts(root);
  if (!parts) return;
  wire(parts);
  root.documentElement.setAttribute('data-scripted', '');
}

function wire({ elements, stage, live, status, reset }: Parts): void {
  const { panel, field, list: listElement } = elements;

  // MARK: State

  const platform = currentPlatform();
  const start = startingHistory(clips);
  let history: History = start;
  // What's in the field already: typed while the script was still loading.
  let query = field.value;
  let filter: FilterId = 'all';
  let list: Clip[] = searchResults(query, filter, history);
  let selectedIndex: number | undefined =
    query === '' ? keptIndex(list, initialSelection, 0) : list.length > 0 ? 0 : undefined;
  /** Whether a pin, an unpin or a delete changed the history (and Reset shows). */
  let edited = false;
  let isOpen = true;
  /** What the panel last wrote, standing in for the clipboard: ⌘V while the hint shows pastes it. */
  let clipboard: { clip: Clip; plain: boolean } | undefined;
  /** How the visitor last reached for the page: a tap mustn't bring up the phone's keyboard. */
  let lastInput: 'keyboard' | 'mouse' | 'touch' = 'mouse';
  let reopenTimer: number | undefined;
  let announceTimer: number | undefined;
  let resultsTimer: number | undefined;

  const selected = (): Clip | undefined => (selectedIndex === undefined ? undefined : list[selectedIndex]);

  function show(): void {
    render(elements, {
      list,
      selectedIndex,
      tokens: matchTokens(query),
      filter,
      sectionBreak: sectionBreak(list, query, filter),
      empty: list.length === 0 ? emptyState(history, query, filter) : undefined,
      footer: footerHints(selected(), query),
    });
    reset.hidden = !edited;
  }

  /** The list again from the history, query and filter: the best match first, or the same clip kept. */
  function refresh(selecting: 'first' | 'keep'): void {
    const previous = selected();
    list = searchResults(query, filter, history);
    selectedIndex = selecting === 'first' ? (list.length > 0 ? 0 : undefined) : keptIndex(list, previous?.id, selectedIndex);
    show();
  }

  function select(index: number | undefined): void {
    if (index === undefined || index === selectedIndex) return;
    selectedIndex = index;
    show();
  }

  // MARK: Saying what happened

  /**
   * Into the polite live region; emptied first, so the same words twice are
   * said twice. The latest news wins: a results count still waiting for
   * typing to settle is dropped.
   */
  function announce(message: string): void {
    window.clearTimeout(announceTimer);
    window.clearTimeout(resultsTimer);
    status.textContent = '';
    announceTimer = window.setTimeout(() => {
      status.textContent = message;
    }, 80);
  }

  function announceResults(): void {
    window.clearTimeout(resultsTimer);
    announce(list.length > 0 ? resultsPhrase(list.length, filter) : emptyState(history, query, filter).title);
  }

  // MARK: Changing things

  function setQuery(value: string): void {
    if (value === query) return;
    query = value;
    if (field.value !== value) field.value = value;
    refresh('first');
    window.clearTimeout(resultsTimer);
    resultsTimer = window.setTimeout(announceResults, settleMs);
  }

  function setFilter(value: FilterId): void {
    if (value === filter) return;
    filter = value;
    refresh('first');
    announceResults();
  }

  function change(next: History, message: string): void {
    history = next;
    edited = true;
    refresh('keep');
    announce(message);
  }

  function leave(): void {
    if (document.activeElement instanceof HTMLElement && panel.contains(document.activeElement)) {
      document.activeElement.blur();
    }
  }

  /**
   * Esc with nothing to clear: the keyboard leaves the panel for the box
   * around it, so the panel stops being the key window and its keys stop
   * acting, but Tab goes on from here (a blur would send it back to the
   * top of the page in Safari).
   */
  function stepOut(): void {
    live.focus({ preventScroll: true });
  }

  /** Back to the page as it loaded: the starting history, no search, the image selected. */
  function startOver(): void {
    history = start;
    edited = false;
    query = '';
    field.value = '';
    filter = 'all';
    list = searchResults(query, filter, history);
    selectedIndex = keptIndex(list, initialSelection, 0);
    listElement.scrollTop = 0;
    show();
    announce(spoken.reset);
  }

  /** Runs a command; `false` leaves the key to the search field (⌘⌫ while there's a query). */
  function run(command: Command): boolean {
    switch (command) {
      case 'up':
      case 'down':
        select(movedIndex(list.length, selectedIndex, command === 'up' ? -1 : 1));
        return true;
      case 'page-up':
      case 'page-down':
        select(movedIndex(list.length, selectedIndex, command === 'page-up' ? -pageSize : pageSize));
        return true;
      case 'first':
        select(list.length > 0 ? 0 : undefined);
        return true;
      case 'last':
        select(list.length > 0 ? list.length - 1 : undefined);
        return true;
      case 'paste':
      case 'paste-plain':
      case 'copy':
        write(command);
        return true;
      case 'pin': {
        const clip = selected();
        if (clip) change(togglePin(history, clip.id), isPinned(history, clip.id) ? spoken.unpinned : spoken.pinned);
        return true;
      }
      case 'delete': {
        if (query !== '') return false;
        const clip = selected();
        if (clip) change(remove(history, clip.id), spoken.deleted);
        return true;
      }
      case 'clear-search':
        setQuery('');
        return true;
      case 'cancel':
        if (query !== '') setQuery('');
        else stepOut();
        return true;
    }
  }

  // MARK: Pasting

  /**
   * Closes the panel as the app does and puts the clip on the line under it
   * (or, for ⌘⏎, shows the copy-only hint); then the panel comes back.
   */
  function write(kind: Write): void {
    const clip = selected();
    if (!isOpen || !clip) return;
    const plain = kind === 'paste-plain';
    const returnFocus = panel.contains(document.activeElement) && lastInput !== 'touch';
    clipboard = { clip, plain };
    leave();
    isOpen = false;
    stage.close();
    if (kind === 'copy') {
      announce(spoken.copied);
      stage.showHud(() => reopen(returnFocus));
      return;
    }
    // The paste lands once the panel is gone, as ⌘V follows the closing in the app.
    window.setTimeout(() => stage.land(pasted(clip, plain)), motion(motionMs));
    announce(plain ? spoken.pastedPlain : spoken.pasted);
    window.clearTimeout(reopenTimer);
    reopenTimer = window.setTimeout(() => reopen(returnFocus), motion(motionMs) + beatMs);
  }

  function reopen(returnFocus: boolean): void {
    window.clearTimeout(reopenTimer);
    stage.hideHud();
    if (isOpen) return;
    isOpen = true;
    stage.open();
    const away = document.activeElement === null || document.activeElement === document.body;
    if (returnFocus && away) field.focus({ preventScroll: true });
  }

  /** ⇧⌘V: the panel at once, the keyboard in it, scrolled into view if it isn't. */
  function summon(): void {
    reopen(false);
    const box = live.getBoundingClientRect();
    const inView = box.top >= 0 && box.bottom <= window.innerHeight;
    if (!inView) {
      live.scrollIntoView({
        block: box.height > window.innerHeight ? 'start' : 'center',
        behavior: reducesMotion() ? 'auto' : 'smooth',
      });
    }
    field.focus({ preventScroll: true });
  }

  // MARK: Keys

  // How the visitor reached for the page, noted before any handler acts on it.
  document.addEventListener('keydown', () => (lastInput = 'keyboard'), { capture: true });
  document.addEventListener(
    'pointerdown',
    (event) => (lastInput = event.pointerType === 'touch' ? 'touch' : 'mouse'),
    { capture: true },
  );

  document.addEventListener('keydown', (event) => {
    if (composing(event)) return;
    if (opensPanel(event)) {
      event.preventDefault();
      summon();
    } else if (pastes(event) && clipboard && stage.hudShowing && !isEditable(event.target)) {
      // The hint says "Press ⌘V": the demo's own clipboard goes on the line.
      event.preventDefault();
      stage.land(pasted(clipboard.clip, clipboard.plain));
      announce(clipboard.plain ? spoken.pastedPlain : spoken.pasted);
    }
  });

  panel.addEventListener('keydown', (event) => {
    if (composing(event) || !isOpen) return;
    const onButton = event.target instanceof HTMLButtonElement;
    // A focused filter keeps ⏎ and Space for itself.
    if (onButton && (event.key === 'Enter' || event.key === ' ')) return;
    const command = commandFor(event, platform);
    if (command && run(command)) {
      event.preventDefault();
    } else if (onButton && types(event)) {
      // Typing on a filter types into the search, as it would with the field focused.
      field.focus({ preventScroll: true });
    }
  });

  field.addEventListener('input', () => setQuery(field.value));

  // MARK: Pointer

  // Clicking anywhere in the panel puts the keyboard in the search field. A tap
  // doesn't: it would bring up a phone's keyboard over the list.
  panel.addEventListener('mousedown', (event) => {
    if (lastInput === 'touch' || event.button !== 0 || event.target === field) return;
    event.preventDefault();
    field.focus({ preventScroll: true });
  });

  const rowIndex = (target: EventTarget | null): number => {
    const row = target instanceof Element ? target.closest('[role="option"][data-clip]') : null;
    return row ? list.findIndex((clip) => clip.id === row.getAttribute('data-clip')) : -1;
  };

  // A click selects; on a touch screen, tapping the selected row again pastes it.
  listElement.addEventListener('click', (event) => {
    const index = rowIndex(event.target);
    if (index === -1) return;
    if (lastInput === 'touch' && index === selectedIndex) write('paste');
    else select(index);
  });

  listElement.addEventListener('dblclick', (event) => {
    const index = rowIndex(event.target);
    if (index === -1 || lastInput === 'touch') return;
    select(index);
    write('paste');
  });

  for (const button of elements.filters) {
    button.addEventListener('click', () => {
      const value = button.dataset.filter;
      if (isFilterId(value)) setFilter(value);
    });
  }

  for (const [name, hint] of elements.hints) {
    const command = hintCommands[name];
    if (command) hint.addEventListener('click', () => run(command));
  }

  reset.addEventListener('click', () => {
    const keyboard = lastInput !== 'touch';
    startOver();
    // The button goes away with the changes; the keyboard goes back to the panel.
    if (keyboard) field.focus({ preventScroll: true });
  });

  show();
}
