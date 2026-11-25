#!/usr/bin/env node
// Makes the site's icons and its social card in public/, with headless
// Chrome on a Mac (`npm run images`; see site/README.md). The PNGs it
// writes are committed; CI never runs this.
//
//   favicon.svg               a copy of Resources/Icon/AppIcon-32.svg
//   favicon.ico               AppIcon-16.svg and AppIcon-32.svg at 16 and 32 px, PNGs in an ICO
//   icon-192.png, icon-512.png    AppIcon.svg as is, the macOS margin included
//   apple-touch-icon.png      180 px, full bleed: the icon's graphite to every edge, since
//                             iOS rounds the corners itself and fills transparency with black
//   icon-maskable-512.png     512 px, full bleed, the drawing inside the maskable safe circle
//   og.png                    1200 × 630, the social card, composed from the built home page
//
// The card is made from the site itself, not a template: the script serves
// dist/ (run `npm run build` first), opens the home page without its
// script (so the panel is the server-rendered still, the image selected),
// and rearranges the page's own brand, headline and panel into the card.
// Chrome draws the real system font, which is the point.
//
// CHROME_PATH overrides where Chrome is.

import { spawn } from 'node:child_process';
import { copyFileSync, existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const siteDir = fileURLToPath(new URL('..', import.meta.url));
const iconDir = join(siteDir, '..', 'Resources', 'Icon');
const publicDir = join(siteDir, 'public');
const distDir = join(siteDir, 'dist');
const chromePath = process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// MARK: Chrome over the DevTools protocol

async function launchChrome() {
  if (!existsSync(chromePath)) {
    throw new Error(`No Chrome at ${chromePath}. Install Google Chrome or set CHROME_PATH.`);
  }
  const profile = mkdtempSync(join(tmpdir(), 'kept-images-'));
  const chrome = spawn(
    chromePath,
    ['--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--hide-scrollbars', '--force-color-profile=srgb', 'about:blank'],
    { stdio: 'ignore' },
  );
  // Chrome writes the port it picked to DevToolsActivePort.
  const portFile = join(profile, 'DevToolsActivePort');
  for (let i = 0; i < 100 && !existsSync(portFile); i++) await sleep(100);
  if (!existsSync(portFile)) throw new Error('Chrome did not start.');
  await sleep(100);
  const port = readFileSync(portFile, 'utf8').split('\n')[0];
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find((target) => target.type === 'page');
  const socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });

  let lastId = 0;
  const pending = new Map();
  const loads = [];
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject, method } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(`${method}: ${message.error.message}`));
      else resolve(message.result);
    } else if (message.method === 'Page.loadEventFired') {
      loads.splice(0).forEach((resolve) => resolve());
    }
  });
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++lastId;
      pending.set(id, { resolve, reject, method });
      socket.send(JSON.stringify({ id, method, params }));
    });
  await send('Page.enable');

  return {
    send,
    async open(url, { width, height, scale = 1, scripts = true }) {
      await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: scale, mobile: false });
      await send('Emulation.setEmulatedMedia', {
        features: [
          { name: 'prefers-color-scheme', value: 'light' },
          { name: 'prefers-reduced-motion', value: 'reduce' },
          { name: 'prefers-contrast', value: 'no-preference' },
        ],
      });
      await send('Emulation.setScriptExecutionDisabled', { value: !scripts });
      const loaded = new Promise((resolve) => loads.push(resolve));
      await send('Page.navigate', { url });
      await loaded;
      await send('Runtime.evaluate', { expression: 'document.fonts.ready', awaitPromise: true });
    },
    async evaluate(expression) {
      const result = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
      if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
      return result.result.value;
    },
    /** A PNG of the top-left width × height CSS px, at the page's scale. */
    async png(width, height, { transparent = false } = {}) {
      await send('Emulation.setDefaultBackgroundColorOverride', transparent ? { color: { r: 0, g: 0, b: 0, a: 0 } } : {});
      const shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width, height, scale: 1 } });
      return Buffer.from(shot.data, 'base64');
    },
    close() {
      socket.close();
      chrome.kill();
      // Chrome may still be writing to its profile for a moment.
      setTimeout(() => rmSync(profile, { recursive: true, force: true }), 500).unref();
    },
  };
}

// MARK: Icons

const appIcon = readFileSync(join(iconDir, 'AppIcon.svg'), 'utf8');

/** One edit to the icon's SVG, which must find what it replaces: if the SVG changes shape, say so. */
function replaceOnce(svg, find, replacement, what) {
  if (!find.test(svg)) throw new Error(`AppIcon.svg: couldn't find ${what}; update scripts/make-images.mjs.`);
  return svg.replace(find, replacement);
}

/**
 * The icon with its graphite body as a full square over `box` (x, y, size in
 * the 1024 canvas) and no rim: for icons the platform masks itself.
 */
function fullBleedIcon(box) {
  const { x, y, size } = box;
  let svg = replaceOnce(appIcon, /viewBox="[^"]*"/, `viewBox="${x} ${y} ${size} ${size}"`, 'the viewBox');
  svg = replaceOnce(
    svg,
    /<use href="#body" fill="url\(#graphite\)"\/>/,
    `<rect x="${x}" y="${y}" width="${size}" height="${size}" fill="url(#graphite)"/>`,
    'the graphite body',
  );
  svg = replaceOnce(svg, /<use href="#body" fill="none" stroke="url\(#rim\)"[^>]*\/>/, '', 'the rim');
  // The light falls from the top of what's shown.
  svg = replaceOnce(
    svg,
    /(<linearGradient id="graphite"[^>]*?)y1="100" x2="0" y2="924"/,
    `$1y1="${y}" x2="0" y2="${y + size}"`,
    'the graphite gradient',
  );
  return svg;
}

/** An SVG drawn into a size × size PNG with a transparent background. */
async function renderSvg(chrome, svg, size) {
  const src = `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
  const html = `<!doctype html><style>html,body{margin:0;background:transparent}img{display:block}</style><img src="${src}" width="${size}" height="${size}">`;
  await chrome.open(`data:text/html;base64,${Buffer.from(html).toString('base64')}`, { width: size, height: size, scripts: false });
  return chrome.png(size, size, { transparent: true });
}

/** PNGs in an ICO container (each entry a whole PNG file, which every current browser reads). */
export function icoFromPngs(images) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // 1 = icon
  header.writeUInt16LE(images.length, 4);
  let offset = 6 + 16 * images.length;
  const entries = images.map(({ size, png }) => {
    const entry = Buffer.alloc(16);
    entry.writeUInt8(size >= 256 ? 0 : size, 0); // width
    entry.writeUInt8(size >= 256 ? 0 : size, 1); // height
    entry.writeUInt8(0, 2); // no palette
    entry.writeUInt8(0, 3); // reserved
    entry.writeUInt16LE(1, 4); // color planes
    entry.writeUInt16LE(32, 6); // bits per pixel
    entry.writeUInt32LE(png.length, 8);
    entry.writeUInt32LE(offset, 12);
    offset += png.length;
    return entry;
  });
  return Buffer.concat([header, ...entries, ...images.map(({ png }) => png)]);
}

// MARK: The social card

/** Serves dist/ on a free port, as the host would: "/" is index.html. */
function serveDist() {
  if (!existsSync(join(distDir, 'index.html'))) {
    throw new Error('No dist/index.html: run `npm run build` first; the social card is made from the built home page.');
  }
  const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.png': 'image/png' };
  const server = createServer((request, response) => {
    let path = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    if (path.endsWith('/')) path += 'index.html';
    const file = normalize(join(distDir, path));
    if (!file.startsWith(distDir) || !existsSync(file) || !statSync(file).isFile()) {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream' });
    response.end(readFileSync(file));
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

/** The card, 600 × 315 CSS px drawn at 2x: 1200 × 630. */
const card = { width: 600, height: 315, scale: 2 };

/** Clips the strip starts from (the history's 4th row), so the marked image is the second row shown. */
const firstClip = 'changecount';

// Runs in the page. The card's own layout; everything inside it keeps the site's styles.
const composeCard = `(() => {
  const style = document.createElement('style');
  style.textContent = \`
    html, body { margin: 0; overflow: hidden; background: var(--page); }
    .og-card {
      position: relative;
      width: ${card.width}px;
      height: ${card.height}px;
      overflow: hidden;
      background: var(--page);
    }
    .og-card .brand {
      position: absolute;
      left: 36px;
      top: 28px;
    }
    .og-card .og-headline {
      position: absolute;
      left: 36px;
      top: 70px;
      margin: 0;
      font-size: 50px;
      font-weight: 600;
      letter-spacing: -0.025em;
      line-height: 1.04;
      color: var(--ink);
    }
    .og-card .og-strip {
      position: absolute;
      left: 36px;
      right: 36px;
      top: 192px;
    }
    .og-card .og-strip [data-panel] { height: auto; max-width: none; }
    .og-card .og-strip .list { height: auto; overflow: visible; }
  \`;
  document.head.append(style);

  const brand = document.querySelector('.header .brand').cloneNode(true);
  const headline = document.querySelector('#kept-title').cloneNode(true);
  headline.removeAttribute('id');
  headline.className = 'og-headline';

  // The panel as the page renders it without its script: the image selected.
  const panel = document.querySelector('[data-panel]').cloneNode(true);
  panel.removeAttribute('role');
  for (const part of panel.querySelectorAll('.search, .previews, [data-panel-empty], [data-panel-footer]')) part.remove();
  const list = panel.querySelector('#panel-list');
  list.removeAttribute('id');
  const rows = [...list.children];
  const first = rows.findIndex((row) => row.dataset.clip === '${firstClip}');
  if (first < 0) throw new Error('No row for ${firstClip}');
  rows.slice(0, first).forEach((row) => row.remove());
  if (!list.querySelector('[aria-selected="true"]')) throw new Error('No selected row in the strip');

  const strip = document.createElement('div');
  strip.className = 'og-strip';
  strip.append(panel);
  const cardElement = document.createElement('div');
  cardElement.className = 'og-card';
  cardElement.append(brand, headline, strip);
  document.body.replaceChildren(cardElement);
  return [...list.children].map((row) => row.dataset.clip);
})()`;

// MARK: Main

async function main() {
  const chrome = await launchChrome();
  const written = [];
  const write = (name, data) => {
    writeFileSync(join(publicDir, name), data);
    written.push(`${name} (${data.length.toLocaleString('en')} bytes)`);
  };
  try {
    copyFileSync(join(iconDir, 'AppIcon-32.svg'), join(publicDir, 'favicon.svg'));
    written.push('favicon.svg (copy of AppIcon-32.svg)');

    const favicon16 = await renderSvg(chrome, readFileSync(join(iconDir, 'AppIcon-16.svg'), 'utf8'), 16);
    const favicon32 = await renderSvg(chrome, readFileSync(join(iconDir, 'AppIcon-32.svg'), 'utf8'), 32);
    write('favicon.ico', icoFromPngs([{ size: 16, png: favicon16 }, { size: 32, png: favicon32 }]));

    write('icon-192.png', await renderSvg(chrome, appIcon, 192));
    write('icon-512.png', await renderSvg(chrome, appIcon, 512));
    // The macOS body (100…924) fills the square; iOS draws its own corners.
    write('apple-touch-icon.png', await renderSvg(chrome, fullBleedIcon({ x: 100, y: 100, size: 824 }), 180));
    // The whole canvas: the drawing stays within the central circle (80%) every mask keeps.
    write('icon-maskable-512.png', await renderSvg(chrome, fullBleedIcon({ x: 0, y: 0, size: 1024 }), 512));

    const server = await serveDist();
    try {
      const { port } = server.address();
      await chrome.open(`http://127.0.0.1:${port}/`, { ...card, scripts: false });
      const rows = await chrome.evaluate(composeCard);
      // (No requestAnimationFrame here: with the page's scripts off it never fires. The screenshot draws a fresh frame.)
      await chrome.evaluate('document.fonts.ready.then(() => true)');
      write('og.png', await chrome.png(card.width, card.height));
      written.push(`  the card's strip: ${rows.join(', ')}`);
    } finally {
      server.close();
    }
  } finally {
    chrome.close();
  }
  console.log(`Wrote to public/:\n  ${written.join('\n  ')}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`make-images: ${error.message}`);
    process.exit(1);
  });
}
