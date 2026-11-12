/**
 * Screenshots tgui windows rendered from the renderAll fixtures (tgui/packages/tgui/preview).
 *
 *   bun tools/tgui_preview/shoot.ts --out <dir> [--legacy] [Window ...]
 *
 * Builds the preview bundle (tgui/rspack.preview.config.ts) into <dir>/bundle, then drives headless Chrome once per
 * window and writes <dir>/<Window>.png. With no window names it shoots SPREAD. --legacy builds with the pre-console
 * default theme (resolveTheme falls back to 'nanotrasen'), for before/after pairs; the two files are restored after.
 */
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
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
  'ChemMaster', 'ChemDispenser', 'ChemAnalyzerPro', 'MedicalRecords', 'SecurityRecords', 'BodyScanner', 'DNAModifier',
  'Biogenerator', 'Autolathe', 'SupplyConsole', 'APC', 'AirAlarm', 'Smes', 'PowerMonitor', 'SupermatterMonitor',
  'Techweb', 'ExosuitFabricatorTg', 'Fabricator', 'ResleevingConsole', 'CrewMonitor', 'CameraConsole', 'Vending',
  'Teleporter', 'ShuttleControl', 'SeedStorage', 'PlantAnalyzer', 'Microwave', 'StationAlertConsole', 'TelesciConsole',
  'Photocopier', 'Fax', 'AccountsTerminal', 'StockExchange', 'Spellbook', 'OvermapNavigation', 'PersonalCrafting',
  'Wires', 'Safe',
];

const args = process.argv.slice(2);
const flag = (n: string) => args.includes(n);
const outIdx = args.indexOf('--out');
const out = path.resolve(outIdx >= 0 ? args[outIdx + 1] : path.join(root, 'data', 'tgui_preview_shots'));
const reuseIdx = args.indexOf('--reuse');
const sizesIdx = args.indexOf('--sizes');
const requested: Record<string, [number, number]> = sizesIdx >= 0 ? JSON.parse(readFileSync(args[sizesIdx + 1], 'utf8')) : {};
const names = args.filter((a, i) => !a.startsWith('--') && i !== outIdx + 1 && i !== reuseIdx + 1 && i !== sizesIdx + 1);
const windows = names.length ? names : SPREAD;
const bundle = reuseIdx >= 0 ? path.resolve(args[reuseIdx + 1]) : path.join(out, 'bundle');
mkdirSync(out, { recursive: true });

const patched: Array<[string, string]> = [];
if (flag('--legacy') && reuseIdx < 0) {
  for (const [file, from, to] of [
    ['layouts/consoleTheme.ts', 'WINDOW_THEMES.includes(theme) ? theme : CONSOLE_THEME', "WINDOW_THEMES.includes(theme) ? theme : 'nanotrasen'"],
  ]) {
    const p = path.join(tgui, 'packages/tgui', file);
    const text = readFileSync(p, 'utf8');
    patched.push([p, text]);
    writeFileSync(p, text.replace(from, to));
  }
}
try {
  if (reuseIdx >= 0) throw new Error('reuse');
  const build = spawnSync('bunx', ['rspack', 'build', '-c', 'rspack.preview.config.ts'], {
    cwd: tgui,
    stdio: 'inherit',
    shell: true,
    env: { ...process.env, PREVIEW_OUT: bundle },
  });
  if (build.status !== 0) throw new Error('preview bundle build failed');
} catch (e) {
  if ((e as Error).message !== 'reuse') throw e;
} finally {
  for (const [p, text] of patched) writeFileSync(p, text);
}

// Icon fonts: the game's Font Awesome (html/font-awesome), linked from the page.
if (reuseIdx < 0) {
cpSync(path.join(root, 'html', 'font-awesome'), path.join(bundle, 'font-awesome'), { recursive: true });
// The game's stylesheet names its fonts beside itself (the asset cache serves them flat).
cpSync(path.join(bundle, 'font-awesome', 'webfonts'), path.join(bundle, 'font-awesome', 'css'), { recursive: true });
}
if (flag('--build-only')) process.exit(0);

const { buildWindowGeometryManifest } = await import(pathToFileURL(path.join(tgui, 'windowGeometryManifest.ts')).href);
const geometry = buildWindowGeometryManifest(path.join(tgui, 'packages/tgui/interfaces'));
// Served over http: Chrome will not load web fonts (Font Awesome) from file:// pages.
const server = Bun.serve({ port: 0, fetch: (req) => {
  const file = Bun.file(path.join(bundle, decodeURIComponent(new URL(req.url).pathname)));
  return file.size ? new Response(file) : new Response('not found', { status: 404 });
} });
const page = `http://localhost:${server.port}/index.html`;
for (const name of windows) {
  const g = requested[name] ? { width: requested[name][0], height: requested[name][1] } : (geometry[name] ?? { width: 560, height: 640 });
  const shot = path.join(out, `${name}.png`);
  const query = flag('--mark') ? `w=${name}&mark=1` : `w=${name}`;
  const proc = Bun.spawn(
    [CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', `--window-size=${Math.max(g.width, 500)},${g.height}`,
      '--virtual-time-budget=4000', `--screenshot=${shot}`, `${page}?${query}`],
    { stdout: 'ignore', stderr: 'ignore' },
  );
  const r = { status: await proc.exited };
  console.log(r.status === 0 ? `shot ${name} ${Math.max(g.width, 500)}x${g.height}` : `FAILED ${name}`);
}

// Headless Chrome will not make a window narrower than 500px, so narrower windows are shot at 500.
server.stop(true);
