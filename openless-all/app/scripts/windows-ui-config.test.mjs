import { readFile } from 'node:fs/promises';

function assertEqual(actual, expected, name) {
  if (actual !== expected) {
    throw new Error(`${name}: expected ${expected}, got ${actual}`);
  }
}

const raw = await readFile(new URL('../src-tauri/tauri.conf.json', import.meta.url), 'utf-8');
const config = JSON.parse(raw);
const mainWindow = config.app.windows.find((window) => window.label === 'main');

if (!mainWindow) {
  throw new Error('main window config missing');
}

assertEqual(mainWindow.decorations, false, 'windows main window should use only custom titlebar');
