// Questions on the home page. Plain strings, so the same questions are also
// the home page's FAQPage structured data and part of its Markdown twin and
// llms-full.txt: answers use only the inline convention in src/lib/inline.ts
// ({⌘P} key caps, `code`, **strong**). The first sentence of each answer
// answers the question on its own; assistants quote it.
//
// Every claim is backed by README.md, docs/DESIGN.md, docs/ROADMAP.md or
// Resources/ (Info.plist, Kept.entitlements).

export interface Question {
  /** Stable, for the element's id. */
  id: string;
  question: string;
  /** One or more paragraphs. */
  answer: string[];
}

export const questions: Question[] = [
  {
    id: 'what-is-kept',
    question: 'What is Kept?',
    answer: [
      'Kept is a clipboard manager for the Mac. It keeps what you copy (text, rich text, links, images, ' +
        'files and colors) and brings it back when you press {⇧⌘V}, so you can find something you copied ' +
        'earlier and paste it where you’re typing without touching the mouse.',
    ],
  },
  {
    id: 'how-is-it-different',
    question: 'How is Kept different from other clipboard managers?',
    answer: [
      'Kept is made for the keyboard: every action in the panel has a key, and the panel’s footer shows ' +
        'the ones that apply. Clips sit in a dense list, not a grid of cards, so more of them fit on screen ' +
        'and they’re quick to scan from the keyboard.',
      'It’s a native Mac app, written in Swift with AppKit and SwiftUI. Nothing you copy leaves your Mac: ' +
        'Kept has no network access, no account, no sync and no telemetry. And it’s free and open source ' +
        'under the MIT license.',
    ],
  },
  {
    id: 'is-it-free',
    question: 'Is Kept free?',
    answer: [
      'Yes. Kept is free and open source under the MIT license, with no paid tier and no account to ' +
        'create.',
    ],
  },
  {
    id: 'which-macs',
    question: 'Which Macs does Kept run on?',
    answer: [
      'Kept needs macOS 14 Sonoma or later. Releases are universal apps, so Kept runs natively on Macs ' +
        'with Apple silicon and on Intel Macs.',
    ],
  },
  {
    id: 'does-it-send-anything',
    question: 'Does Kept send what I copy anywhere?',
    answer: [
      'No. Your history stays on your Mac, in Kept’s sandbox container ' +
        '(`~/Library/Containers/app.kept.Kept`), readable only by you. Kept runs in the App Sandbox ' +
        'without network access, and has no accounts, no sync and no telemetry.',
    ],
  },
  {
    id: 'passwords',
    question: 'Does Kept save passwords?',
    answer: [
      'Not the ones apps mark as secret. Kept never saves copies marked as concealed, transient or ' +
        'auto-generated, and it ignores everything copied in Passwords, Keychain Access, 1Password, ' +
        'Bitwarden and KeePassXC.',
      'You can exclude more apps in Settings › Privacy, or choose **Ignore next copy** before you copy ' +
        'something sensitive.',
    ],
  },
  {
    id: 'open-and-paste',
    question: 'How do I open Kept and paste a clip?',
    answer: [
      'Press {⇧⌘V} in any app, type a few letters to find the clip, and press {⏎} to paste it where ' +
        'you were typing. {⌥⏎} pastes as plain text, {⌘⏎} copies without pasting, and {⌘1}–{⌘9} ' +
        'paste the first nine clips. You can also click Kept’s icon in the menu bar.',
    ],
  },
  {
    id: 'not-opened',
    question: 'Why does macOS say “Kept” Not Opened?',
    answer: [
      'Because Kept’s releases aren’t notarized by Apple yet, macOS stops the first launch. On macOS 15 ' +
        'and later, click **Done**, then **Open Anyway** in System Settings › Privacy & Security (under ' +
        'Security). On macOS 14, Control-click Kept and choose **Open**.',
      'Or run `xattr -dr com.apple.quarantine /Applications/Kept.app` in Terminal.',
    ],
  },
  {
    id: 'accessibility-permission',
    question: 'Why does Kept ask for Accessibility permission?',
    answer: [
      'To paste for you. Kept pastes by pressing {⌘V} in the app you were using, which macOS allows ' +
        'only once you turn Kept on in System Settings › Privacy & Security (under Accessibility up to ' +
        'macOS 26). Until you do, Kept copies the clip and you press {⌘V} yourself.',
    ],
  },
  {
    id: 'how-many-clips',
    question: 'How many clips does Kept keep?',
    answer: [
      '500 by default, and you can pick a limit from 100 up to 10,000 in Settings › General. Pinned ' +
        'clips don’t count toward the limit and always stay.',
      'Settings › Privacy can also forget unpinned clips you haven’t copied or pasted for a day, a week ' +
        'or a month.',
    ],
  },
  {
    id: 'sync-and-iphone',
    question: 'Does Kept sync, or have an iPhone app?',
    answer: [
      'No. Kept keeps your history on one Mac; sync and an iOS app are out of scope. Copies that reach ' +
        'your Mac from your other devices through Universal Clipboard are kept like any other, unless you ' +
        'turn on **Ignore copies from other devices** in Settings › Privacy.',
    ],
  },
  {
    id: 'menu-bar-icon',
    question: 'Can I hide Kept’s menu bar icon?',
    answer: [
      'Yes. Turn off **Show Kept in the menu bar** in Settings › General, and {⇧⌘V} still opens Kept. ' +
        'Opening Kept again from Applications brings the icon back.',
    ],
  },
  {
    id: 'uninstall',
    question: 'How do I uninstall Kept?',
    answer: [
      'Quit Kept, drag it from Applications to the Trash, and delete `~/Library/Containers/app.kept.Kept` ' +
        'to remove your history too.',
      'To quit, right-click Kept’s icon in the menu bar and choose **Quit Kept**; if you’ve hidden the ' +
        'icon, opening Kept again from Applications brings it back. If you let Kept paste for you, remove ' +
        'it from System Settings › Privacy & Security as well (under Accessibility up to macOS 26).',
    ],
  },
  {
    id: 'build-from-source',
    question: 'How do I build Kept from source?',
    answer: [
      'Clone `https://github.com/WaseemSabir/Kept.git` and run `make app` in it, which builds and ad-hoc ' +
        'signs `dist/Kept.app`; you need macOS and Xcode 26 or later. `make run` builds and opens it, ' +
        'and `make test` runs every test.',
    ],
  },
];
