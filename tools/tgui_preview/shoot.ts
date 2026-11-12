/**
 * Screenshots tgui windows rendered from the renderAll fixtures (tgui/packages/tgui/preview).
 *
 *   bun tools/tgui_preview/shoot.ts --out <dir> [--legacy] [Window ...]
 *
 * Builds the preview bundle (tgui/rspack.preview.config.ts) into <dir>/bundle, then drives headless Chrome once per
 * window and writes <dir>/<Window>.png. With no window names it shoots SPREAD. --legacy builds with the pre-console
 * default theme (Layout and Window default to 'nanotrasen'), for before/after pairs; the two files are restored after.
 */
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = path.resolve(import.meta.dirname, '..', '..');
const tgui = path.join(root, 'tgui');
const CHROME = process.env.CHROME ?? 'C:/Program Files/Google/Chrome/Application/chrome.exe';

/** A representative spread: machines, consoles, medical, cargo, engineering, records, PDA programs, misc. */
const SPREAD = [
  'Sleeper', 'Cryo', 'SpaceHeater', 'Tank', 'PartsLathe', 'SuitStorageUnit', 'PortableTurret', 'PipeDispenser',
  'CommunicationsConsole', 'GeneralRecords', 'MessageMonitor', 'RequestConsole', 'DroneConsole', 'RoboticsControlConsole',
  'OperatingComputer', 'CloningConsole', 'Pandemic', 'MechaSleeper', 'Medbot', 'MiningVendor',
  'MiningOreProcessingConsole', 'OreSilo', 'AtmosControlPanel', 'AirlockConsoleAdvanced', 'RadiationConfig',
  'EngineeringAssembly', 'NtosFileManager', 'NtosNetDownloader', 'NtosWordProcessor', 'Jukebox', 'TimeClock',
  'Turbolift', 'Newscaster', 'Signaler', 'MuleBot', 'LawManager',
];

const args = process.argv.slice(2);
const flag = (n: string) => args.includes(n);
const outIdx = args.indexOf('--out');
const out = path.resolve(outIdx >= 0 ? args[outIdx + 1] : path.join(root, 'data', 'tgui_preview_shots'));
const names = args.filter((a, i) => !a.startsWith('--') && i !== outIdx + 1);
const windows = names.length ? names : SPREAD;
const bundle = path.join(out, 'bundle');
mkdirSync(out, { recursive: true });

const patched: Array<[string, string]> = [];
if (flag('--legacy')) {
  for (const [file, from, to] of [
    ['layouts/Layout.tsx', 'theme = CONSOLE_THEME', "theme = 'nanotrasen'"],
    ['layouts/Window.tsx', 'theme = CONSOLE_THEME', "theme = 'nanotrasen'"],
  ]) {
    const p = path.join(tgui, 'packages/tgui', file);
    const text = readFileSync(p, 'utf8');
    patched.push([p, text]);
    writeFileSync(p, text.replace(from, to));
  }
}
try {
  const build = spawnSync('bunx', ['rspack', 'build', '-c', 'rspack.preview.config.ts'], {
    cwd: tgui,
    stdio: 'inherit',
    shell: true,
    env: { ...process.env, PREVIEW_OUT: bundle },
  });
  if (build.status !== 0) throw new Error('preview bundle build failed');
} finally {
  for (const [p, text] of patched) writeFileSync(p, text);
}

const { buildWindowGeometryManifest } = await import(pathToFileURL(path.join(tgui, 'windowGeometryManifest.ts')).href);
const geometry = buildWindowGeometryManifest(path.join(tgui, 'packages/tgui/interfaces'));
const page = pathToFileURL(path.join(bundle, 'index.html')).href;
for (const name of windows) {
  const g = geometry[name] ?? { width: 560, height: 640 };
  const shot = path.join(out, `${name}.png`);
  const r = spawnSync(
    CHROME,
    ['--headless=new', '--disable-gpu', '--hide-scrollbars', `--window-size=${Math.max(g.width, 500)},${g.height}`,
      '--virtual-time-budget=4000', `--screenshot=${shot}`, `${page}?w=${name}`],
    { stdio: 'ignore' },
  );
  console.log(r.status === 0 ? `shot ${name} ${Math.max(g.width, 500)}x${g.height}` : `FAILED ${name}`);
}

// Headless Chrome will not make a window narrower than 500px, so narrower windows are shot at 500.
