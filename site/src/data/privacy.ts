// Privacy, from README.md › Privacy & security, Resources/Kept.entitlements
// (sandboxed, no network entitlement) and SECURITY.md. Each fact has a
// short `summary` for the home page and the full `detail` for /privacy.
// Values use the inline convention in src/lib/inline.ts.

export interface PrivacyFact {
  label: string;
  summary: string;
  detail: string;
}

export const privacy: PrivacyFact[] = [
  {
    label: 'Stays on your Mac',
    summary:
      'Your history lives in Kept’s sandbox container, `~/Library/Containers/app.kept.Kept`, ' +
      'readable only by you. Kept has no network access, no accounts, no sync and no telemetry.',
    detail:
      'Your history lives in Kept’s sandbox container, `~/Library/Containers/app.kept.Kept`, ' +
      'readable only by you. Kept runs in the App Sandbox without the network entitlement, so it ' +
      'can’t send what you copy anywhere. It has no accounts, no sync and no telemetry.',
  },
  {
    label: 'Skips secrets',
    summary:
      'Copies that apps mark as concealed, transient or auto-generated are never saved, and neither is ' +
      'anything copied in Passwords, Keychain Access, 1Password, Bitwarden or KeePassXC.',
    detail:
      'Copies that apps mark as concealed, transient or auto-generated ' +
      '([nspasteboard.org](http://nspasteboard.org) markers) are never saved, and neither is anything ' +
      'copied in Passwords, Keychain Access, 1Password, Bitwarden or KeePassXC.',
  },
  {
    label: 'You decide',
    summary:
      'Exclude more apps, pause capture, ignore the next copy before copying something sensitive, ' +
      'skip copies from your other devices, and clear the history any time.',
    detail:
      'Add or remove excluded apps in Settings › Privacy, pause capture from the menu bar menu (or a ' +
      'shortcut), choose **Ignore next copy** before copying something sensitive, skip copies from ' +
      'your other devices, and clear the history any time.',
  },
  {
    label: 'Forgets',
    summary:
      'On a schedule, if you like: unpinned clips you haven’t copied or pasted for a day, a week or ' +
      'a month are deleted. Pinned clips always stay.',
    detail:
      'Settings › Privacy › **Forget unpinned clips** deletes clips you haven’t copied or pasted for ' +
      'a day, a week or a month. Pinned clips always stay.',
  },
  {
    label: 'Clipboard access',
    summary:
      'On macOS 15.4 and later, if macOS is set to ask or deny Kept’s clipboard reads, Kept notices ' +
      'and shows where to allow it.',
    detail:
      'On macOS 15.4 and later, if macOS is set to ask or deny clipboard reads for Kept, Kept ' +
      'detects this and shows where to allow it.',
  },
  {
    label: 'Pasting',
    summary:
      'Kept pastes for you only once you allow it in System Settings › Privacy & Security. Until then ' +
      'it copies, and you press {⌘V}.',
    detail:
      'Kept pastes by pressing {⌘V} in the app you were using, which macOS allows only once you turn ' +
      'Kept on in System Settings › Privacy & Security (under Accessibility up to macOS 26). Kept ' +
      'asks the first time you paste; until then it copies the clip and you press {⌘V} yourself.',
  },
];
