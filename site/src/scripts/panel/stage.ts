// What happens around the panel when it pastes: it closes as the app's does
// (a 120 ms fade, its space kept), the clip lands on the line under it, the
// copy-only hint shows where the app shows it, and the panel comes back with
// its opening motion. Under Reduce Motion nothing fades or scales, and the
// timings that wait for a motion are zero.
import type { Pasted } from './wording.ts';

/** The panel's open and close, and the hint's fade (DESIGN.md › Motion). */
export const motionMs = 120;
/** How long the short copy-only hint stays (PasteHintController). */
export const hintMs = 2500;

export interface StageElements {
  panel: HTMLElement;
  hud: HTMLElement;
  pasteText: HTMLElement;
  pasteImage: HTMLTemplateElement;
}

export function findStage(root: ParentNode, panel: HTMLElement): StageElements | undefined {
  const hud = root.querySelector('[data-panel-hud]');
  const pasteText = root.querySelector('[data-paste-text]');
  const pasteImage = root.querySelector('template[data-paste-image]');
  if (!(hud instanceof HTMLElement) || !(pasteText instanceof HTMLElement) || !(pasteImage instanceof HTMLTemplateElement)) {
    return undefined;
  }
  return { panel, hud, pasteText, pasteImage };
}

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

export function reducesMotion(): boolean {
  return reducedMotion.matches;
}

/** `ms`, or no time at all under Reduce Motion. */
export function motion(ms: number): number {
  return reducesMotion() ? 0 : ms;
}

/** Restarts a class's animation: off, a layout, on. */
function replay(element: HTMLElement, className: string): void {
  element.classList.remove(className);
  void element.offsetWidth;
  element.classList.add(className);
}

export class Stage {
  readonly #elements: StageElements;
  #panelTimer: number | undefined;
  #hudTimer: number | undefined;
  #hudDone: (() => void) | undefined;

  constructor(elements: StageElements) {
    this.#elements = elements;
  }

  /** Fades the panel out; it keeps its space and can't be reached until it opens again. */
  close(): void {
    const { panel } = this.#elements;
    window.clearTimeout(this.#panelTimer);
    panel.inert = true;
    panel.classList.remove('is-opening');
    replay(panel, 'is-closing');
    this.#panelTimer = window.setTimeout(() => {
      panel.classList.remove('is-closing');
      panel.classList.add('is-closed');
    }, motion(motionMs));
  }

  /** Brings the panel back with the opening motion. */
  open(): void {
    const { panel } = this.#elements;
    window.clearTimeout(this.#panelTimer);
    panel.inert = false;
    panel.classList.remove('is-closing', 'is-closed');
    replay(panel, 'is-opening');
    this.#panelTimer = window.setTimeout(() => panel.classList.remove('is-opening'), motion(motionMs));
  }

  get hudShowing(): boolean {
    return !this.#elements.hud.hidden;
  }

  /** Shows "Copied. Press ⌘V to paste." for 2.5 s, then calls `done` once it has faded. */
  showHud(done: () => void): void {
    const { hud } = this.#elements;
    window.clearTimeout(this.#hudTimer);
    this.#hudDone = done;
    hud.classList.remove('is-leaving');
    hud.hidden = false;
    replay(hud, 'is-showing');
    this.#hudTimer = window.setTimeout(() => {
      hud.classList.remove('is-showing');
      hud.classList.add('is-leaving');
      this.#hudTimer = window.setTimeout(() => this.hideHud(), motion(motionMs));
    }, motion(motionMs) + hintMs);
  }

  /** Hides the hint now (the panel is opening again, say) and runs what waited for it. */
  hideHud(): void {
    const { hud } = this.#elements;
    window.clearTimeout(this.#hudTimer);
    hud.hidden = true;
    hud.classList.remove('is-showing', 'is-leaving');
    const done = this.#hudDone;
    this.#hudDone = undefined;
    done?.();
  }

  /** Puts a paste on the line under the panel, replacing the last one; the caret follows it. */
  land(paste: Pasted): void {
    const { pasteText, pasteImage } = this.#elements;
    if (paste.kind === 'image') {
      const picture = pasteImage.content.firstElementChild?.cloneNode(true);
      if (picture instanceof Element) {
        picture.setAttribute('aria-label', paste.label);
        pasteText.replaceChildren(picture);
      }
      return;
    }
    const text = document.createElement('span');
    text.textContent = paste.text;
    if (paste.code) text.classList.add('pasted-code');
    if (paste.link) text.classList.add('pasted-link');
    pasteText.replaceChildren(text);
  }

  /** Back to the empty line. */
  clear(): void {
    this.#elements.pasteText.replaceChildren();
  }
}
