// Text folded for matching, as the app's SearchKey folds it: lowercased,
// with diacritics and compatibility forms removed ("Café" → "cafe",
// "ﬁ" → "fi", "Ｋｅｐｔ" → "kept", "Straße" → "strasse"). The highlighter
// also needs to know where each folded character came from in the text it
// marks, so `foldWithMap` keeps that.

/** Letters with no decomposition that people type without the mark (SearchKey.foldedLetters). */
const foldedLetters: Readonly<Record<string, string>> = {
  ß: 'ss',
  æ: 'ae',
  œ: 'oe',
  ø: 'o',
  đ: 'd',
  ð: 'd',
  ł: 'l',
  ħ: 'h',
  ı: 'i',
  þ: 'th',
};

/** Nonspacing and enclosing marks: what a decomposition splits off a letter. */
const mark = /^[\p{Mn}\p{Me}]$/u;

/** One character (a code point) folded: decomposed, without its marks, lowercased. */
function foldCharacter(character: string): string {
  const code = character.codePointAt(0) ?? 0;
  if (code < 0x80) return code >= 0x41 && code <= 0x5a ? String.fromCharCode(code + 0x20) : character;
  let folded = '';
  for (const part of character.normalize('NFKD')) {
    if (mark.test(part)) continue;
    for (const lowered of part.toLowerCase()) folded += foldedLetters[lowered] ?? lowered;
  }
  return folded;
}

export function fold(text: string): string {
  let folded = '';
  for (const character of text) folded += foldCharacter(character);
  return folded;
}

export interface FoldedText {
  text: string;
  /** For each UTF-16 unit of `text`, where the character it came from starts in the original. */
  starts: number[];
  /** …and where that character ends. */
  ends: number[];
}

export function foldWithMap(text: string): FoldedText {
  let folded = '';
  const starts: number[] = [];
  const ends: number[] = [];
  let index = 0;
  for (const character of text) {
    const piece = foldCharacter(character);
    for (let unit = 0; unit < piece.length; unit += 1) {
      starts.push(index);
      ends.push(index + character.length);
    }
    folded += piece;
    index += character.length;
  }
  return { text: folded, starts, ends };
}
