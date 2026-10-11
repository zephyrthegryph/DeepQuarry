import { ByondCompileFailure, observedCompileOutcome, type CompileOutcome } from './compile_outcome';
import { CompilerProvenanceError } from './compiler_provenance';
import { bindCompilerInvocation, type CompilerInvocation } from './compiler_invocation';
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import Bun from 'bun';
import Juke from '../juke/index.js';
import { regQuery } from './winreg';
import { acquiredWorldArguments, resolveDreamDaemonExecutable } from './byond_runtime';
import { compilerMode, selectedCompiler } from './compiler_selection';
import { currentCompiledOutput, rememberCompiledOutput, withCompiledOutput, type CompiledOutput } from './native_pair';
import { observeRuntimeLibrary, stageRuntimeLibrary, verifyObservedRuntimeLibrary, type HostedLibraryIdentity } from './runtime_library';

/** Cached path to DM compiler */
let dmPath: string;

async function getDmPath(namedVersion?: string | null): Promise<string> {
  // Use specific named version
  if (namedVersion) {
    return getNamedByondVersionPath(namedVersion);
  }
  if (dmPath) {
    return dmPath;
  }
  dmPath = await (async () => {
    // Search in array of paths
    const paths = [
      ...(process.env.DM_EXE?.split(',') || []),
      ...(await getDefaultNamedByondVersionPath()),
      'C:\\Program Files\\BYOND\\bin\\dm.exe',
      'C:\\Program Files (x86)\\BYOND\\bin\\dm.exe',
      ['reg', 'HKLM\\Software\\Dantom\\BYOND', 'installpath'],
      ['reg', 'HKLM\\SOFTWARE\\WOW6432Node\\Dantom\\BYOND', 'installpath'],
    ];
    const isFile = (path: string) => {
      try {
        return fs.statSync(path).isFile();
      } catch (err) {
        return false;
      }
    };
    for (let path of paths) {
      // Resolve a registry key
      if (Array.isArray(path)) {
        const [_type, ...args] = path;
        path = (await regQuery(args[0], args[1])) || '';
      }
      if (!path) {
        continue;
      }
      // Check if path exists
      if (isFile(path)) {
        return path;
      }
      if (isFile(`${path}/dm.exe`)) {
        return `${path}/dm.exe`;
      }
      if (isFile(`${path}/bin/dm.exe`)) {
        return `${path}/bin/dm.exe`;
      }
    }
    // Default paths
    return (process.platform === 'win32' && 'dm.exe') || 'DreamMaker';
  })();
  return dmPath;
}

async function getNamedByondVersionPath(namedVersion: string): Promise<string> {
  const all_entries = await getAllNamedDmVersions(true);
  const map_entry = all_entries.find((x) => x.name === namedVersion);
  if (map_entry === undefined) {
    Juke.logger.error(
      `No named byond version with name "${namedVersion}" found.`,
    );
    throw new Juke.ExitCode(1);
  }
  return map_entry.path;
}

async function getDefaultNamedByondVersionPath(): Promise<string[]> {
  const all_entries = await getAllNamedDmVersions(false);
  const map_entry = all_entries.find((x) => x.default === true);
  if (map_entry === undefined) return [];
  return [map_entry.path];
}

type NamedDmVersion = {
  name: string;
  path: string;
  default: boolean;
};

let namedDmVersionList: NamedDmVersion[];
export const NamedVersionFile = 'tools/build/dm_versions.json';

async function getAllNamedDmVersions(
  throw_on_fail: boolean,
): Promise<NamedDmVersion[]> {
  if (!namedDmVersionList) {
    if (!fs.existsSync(NamedVersionFile)) {
      if (throw_on_fail) {
        Juke.logger.error(`No byond version map file found.`);
        throw new Juke.ExitCode(1);
      }
      namedDmVersionList = [];
      return namedDmVersionList;
    }
    try {
      namedDmVersionList = await Bun.file(NamedVersionFile).json();
    } catch (err) {
      if (throw_on_fail) {
        Juke.logger.error(`Failed to parse byond version map file. ${err}`);
        throw new Juke.ExitCode(1);
      }
      namedDmVersionList = [];
      return namedDmVersionList;
    }
  }
  return namedDmVersionList;
}

export type DreamMakerOptions = Partial<{
  defines: string[];
  warningsAsErrors: boolean;
  namedDmVersion: string | null;
  ignoreWarningCodes: string[];
}>;

declare const byondSnapshotAuthority: unique symbol;
/** Reserved for a producer that compiles an authenticated immutable closure.
 * No current producer issues this receipt; a manifest hash is insufficient.
 */
export type AuthenticatedByondSnapshot = {
  readonly [byondSnapshotAuthority]: true;
  readonly schema: 1;
  readonly immutableRoot: string;
  readonly files: readonly { readonly path: string; readonly bytes: number; readonly sha256: string }[];
  readonly resourceSearchRoots: readonly string[];
  readonly configuration: {
    readonly project: string;
    readonly effectiveDefines: Readonly<Record<string, string>>;
    readonly compilerSha256: string;
    readonly version: number;
    readonly build: number;
  };
  readonly outputSha256: { readonly dmb: string; readonly rsc: string };
};
export type DreamMakerIdentity =
  | { readonly status: 'observed'; readonly executable: string; readonly sha256: string }
  | { readonly status: 'unknown'; readonly executable: string; readonly reason: string };
export type PreparedDreamMaker = {
  readonly executable: string; readonly identity: DreamMakerIdentity;
  readonly version: number; readonly build: number;
  readonly defines: readonly string[]; readonly namedDmVersion: string | null;
};
const issuedDreamMakers = new WeakSet<PreparedDreamMaker>();
/** Only the current preparation producer can issue this configuration evidence.
 * This does not certify all implicit predefines or any input/resource closure.
 */
export function currentDreamMakerConfiguration(prepared: PreparedDreamMaker, defines: readonly string[]) {
  if (!issuedDreamMakers.has(prepared)) throw new Error('DreamMaker configuration was not issued by current preparation.');
  if (prepared.identity.status !== 'observed') throw new Error('DreamMaker configuration requires a resolved executable identity.');
  if (JSON.stringify(prepared.defines) !== JSON.stringify(defines)) throw new Error('DreamMaker configuration ordered defines changed.');
  checkDreamMakerIdentity(prepared);
  return Object.freeze({ compilerSha256: prepared.identity.sha256, executable: prepared.identity.executable,
    version: prepared.version, build: prepared.build, orderedDefines: prepared.defines,
    implicitPredefinesComplete: false as const, inputClosureAuthenticated: false as const });
}
/** A bare command uses process search rules; never hash a similarly named cwd file. */
export function observeDreamMakerIdentity(executable: string): DreamMakerIdentity {
  if (!path.isAbsolute(executable) && !/[\\/]/.test(executable)) {
    return { status: 'unknown', executable, reason: 'executable resolved by process PATH search; exact file identity unavailable' };
  }
  const resolved = fs.realpathSync.native(path.resolve(executable));
  if (!fs.statSync(resolved).isFile()) throw new Error('DreamMaker executable is not a regular file.');
  return { status: 'observed', executable: resolved, sha256: createHash('sha256').update(fs.readFileSync(resolved)).digest('hex') };
}
function checkDreamMakerIdentity(prepared: PreparedDreamMaker): void {
  if (prepared.identity.status === 'observed') {
    const current = observeDreamMakerIdentity(prepared.executable);
    if (current.status !== 'observed' || current.sha256 !== prepared.identity.sha256 || current.executable !== prepared.identity.executable) {
      throw new Error('DreamMaker executable changed after preparation.');
    }
  }
}
export async function prepareDreamMaker(options: DreamMakerOptions): Promise<PreparedDreamMaker> {
  const identity = observeDreamMakerIdentity(await getDmPath(options.namedDmVersion));
  const version = await testDmVersion(identity.executable);
  const prepared = Object.freeze({ executable: identity.executable, identity: Object.freeze(identity), ...version,
    defines: Object.freeze([...(options.defines ?? [])]), namedDmVersion: options.namedDmVersion ?? null });
  checkDreamMakerIdentity(prepared);
  issuedDreamMakers.add(prepared);
  return prepared;
}
async function testDmVersion(dmPath: string) {
  const execReturn = await Juke.exec(dmPath, [], {
    silent: true,
    throw: false,
  });
  const version = execReturn.combined.match(
    `DM compiler version (\\d+)\\.(\\d+)`,
  );
  if (version == null) {
    Juke.logger.error(
      `Unexpected DreamMaker return, ensure "${dmPath}" is correct DM path.`,
    );
    throw new Juke.ExitCode(1);
  }
  const requiredMajorVersion = 515;
  const requiredMinorVersion = 1597; // First with -D switch functionality
  const major = Number(version[1]);
  const minor = Number(version[2]);
  if (
    major < requiredMajorVersion ||
    (major === requiredMajorVersion && minor < requiredMinorVersion)
  ) {
    Juke.logger.error(
      `${requiredMajorVersion}.${requiredMinorVersion} or later DM version required. Version ${major}.${minor} found at: ${dmPath}`,
    );
    throw new Juke.ExitCode(1);
  }
  return { version: major, build: minor };
}

export type ByondCompilationResult = {
  readonly outcome?: CompileOutcome;
  readonly invocation: { readonly command: readonly string[]; readonly version: number; readonly build: number; readonly compilerIdentity?: DreamMakerIdentity; readonly orderedDefines?: readonly string[]; readonly workingDirectory?: string };
  readonly snapshot?: AuthenticatedByondSnapshot;
};

export async function DreamMaker(
  dmeFile: string,
  options: DreamMakerOptions = {},
  invocation?: CompilerInvocation,
): Promise<CompiledOutput> {
  // A future core-issued closed snapshot can route both backends through the
  // same owned project. Until that issuer exists, selection passes no override.
  const output = await selectedCompiler(dmeFile, options, (capturedProject, prepared, bound) => compileByond(capturedProject ?? dmeFile, options, prepared, bound), Juke.exec, () => prepareDreamMaker(options), invocation);
  rememberCompiledOutput(dmeFile, output);
  return output;
}

async function compileByond(
  dmeFile: string,
  options: DreamMakerOptions,
  prepared?: PreparedDreamMaker,
  invocation?: CompilerInvocation,
): Promise<ByondCompilationResult> {
  if (options.namedDmVersion !== null) {
    Juke.logger.info('Using named byond version:', options.namedDmVersion);
  }
  const compiler = prepared ?? await prepareDreamMaker(options);
  if (compiler.namedDmVersion !== (options.namedDmVersion ?? null) || JSON.stringify(compiler.defines) !== JSON.stringify(options.defines ?? [])) {
    throw new Error('Prepared DreamMaker configuration differs from compilation request.');
  }
  checkDreamMakerIdentity(compiler);
  const dmPath = compiler.executable;
  // Get project basename
  const bound = bindCompilerInvocation(invocation, options.defines ?? []);
  const outputProject = bound ? path.join(bound.root, bound.relativeManifest) : dmeFile;
  const dmeBaseName = outputProject.replace(/\.dme$/, '');
  // Make sure output files are writable
  const testOutputFile = (name: string) => {
    try {
      fs.closeSync(fs.openSync(name, 'r+'));
    } catch (err: unknown) {
      if (!err || typeof err !== 'object' || !('code' in err)) {
        throw err;
      }
      if (err.code === 'ENOENT') {
        return;
      }
      if (err.code === 'EBUSY') {
        Juke.logger.error(
          `File '${name}' is locked by the DreamDaemon process.`,
        );
        Juke.logger.error(`Stop the currently running server and try again.`);
        throw new Juke.ExitCode(1);
      }
      throw err;
    }
  };

  testOutputFile(`${dmeBaseName}.dmb`);
  testOutputFile(`${dmeBaseName}.rsc`);

  const runWithWarningChecks = async (dmPath: string, args: string[]) => {
    const execReturn = await Juke.exec(dmPath, args, { throw: false, ...(bound ? { cwd: bound.root } : {}) });
    if (execReturn.code !== 0) {
      throw new ByondCompileFailure(execReturn.code, observedCompileOutcome(execReturn.code, execReturn.combined, execReturn.code, execReturn.signal), execReturn.signal);
    }
    if (options.warningsAsErrors) {
      const ignoredWarningCodes = options.ignoreWarningCodes ?? [];
      if (ignoredWarningCodes.length > 0) {
        Juke.logger.info(
          'Ignored warning codes:',
          ignoredWarningCodes.join(', '),
        );
      }
      const base_regex = '\\d+:warning( \\([a-z_]*\\))?:';
      const with_ignores = `\\d+:warning( \\([a-z_]*\\))?:(?!(${ignoredWarningCodes
        .map((x) => `.*${x}.*$`)
        .join('|')}))`;
      const reg =
        ignoredWarningCodes.length > 0
          ? new RegExp(with_ignores, 'm')
          : new RegExp(base_regex, 'm');
      if (options.warningsAsErrors && execReturn.combined.match(reg)) {
        Juke.logger.error(`Compile warnings treated as errors`);
        throw new ByondCompileFailure(2, observedCompileOutcome(execReturn.code, execReturn.combined, 2));
      }
    }
    return execReturn;
  };
  // Compile
  const { defines = [] } = options;
  if (defines && defines.length > 0) {
    Juke.logger.info('Using defines:', defines.join(', '));
  }

  const observed = await runWithWarningChecks(dmPath, [
    ...defines.map((def) => `-D${def}`),
    dmeFile,
  ]);
  checkDreamMakerIdentity(compiler);
  return { outcome: observedCompileOutcome(observed.code, observed.combined), invocation: { command: [dmPath, ...defines.map(def => `-D${def}`), dmeFile], version: compiler.version, build: compiler.build,
    compilerIdentity: compiler.identity, orderedDefines: compiler.defines, ...(bound ? { workingDirectory: bound.root } : {}) } };
}

type DDOptions = {
  dmbFile: string;
  /** Exact successful native pair, or explicit conventional fallback output. */
  compiledOutput?: CompiledOutput;
  /** After exact acquisition, before runtime preparation or spawn. Failure stops hosting. */
  onPreparedOutput?: (dmbFile: string) => void;
  onRuntimeIdentity?: (identity: { executable: string; sha256: string; version: null; security: string; library?: HostedLibraryIdentity }) => void;
  watchdogMaximumMs?: number;
  namedDmVersion?: string | null;
  /**
   * Watchdog for runs that terminate themselves (e.g. the unit-test boot, which
   * qdels the world when done). On Windows, dreamdaemon.exe frequently fails to
   * exit after the world ends and lingers as a zombie, so `Juke.exec`'s wait
   * never resolves and the whole build hangs. When `watchdogFile` is set, the
   * daemon is spawned with a handle we control: once that file appears (the
   * run-complete marker, written on pass OR fail), the daemon is given
   * `watchdogGraceMs` to self-close and then force-killed (process tree).
   * `watchdogTimeoutMs` is a hard backstop for a genuinely hung run.
   */
  watchdogFile?: string;
  watchdogGraceMs?: number;
  watchdogTimeoutMs?: number;
  /** Called with the daemon's pid once it has started (watchdog runs only). */
  onSpawn?: (pid: number) => void;
  /** Set by DreamDaemon(): the -logself file the world's output goes to (Windows). */
  daemonLog?: string;
};

/** Prints the tail of a DreamDaemon -logself file, if there is one. */
export function printDaemonLog(daemonLog: string | undefined, lineCount = 60): void {
  if (!daemonLog || !fs.existsSync(daemonLog)) {
    Juke.logger.warn('DreamDaemon left no output log to show.');
    return;
  }
  const lines = fs.readFileSync(daemonLog, 'utf-8').trim().split(/\r?\n/);
  Juke.logger.error(`Last DreamDaemon output (${daemonLog}):`);
  console.error(lines.slice(-lineCount).join('\n'));
}

/**
 * Refuses to boot a world against a verdigris library built from a different
 * bind set. The DLL embeds its ABI hash (`verdigris/ffi/src/abi.rs`, a
 * `pub const &str`) as plain bytes, and `_bindings.dm` carries the DM side's
 * VERDIGRIS_ABI, so a byte search catches a stale or copied-in library before
 * DreamDaemon spends minutes booting only to shut down at `verdigris_init`
 * ("null is not an external function", then an arbitrary exit code, with no
 * logs written). Workers copy verdigris.dll between worktrees, which is how
 * this goes wrong. DQ_SKIP_VERDIGRIS_ABI_CHECK=1 bypasses it.
 */
export function checkVerdigrisAbi(root = '.'): void {
  if (process.env.DQ_SKIP_VERDIGRIS_ABI_CHECK === '1') return;
  const bindings = path.join(root, 'code/__defines/verdigris/_bindings.dm');
  const lib = path.join(root, process.platform === 'win32' ? 'verdigris.dll' : 'libverdigris.so');
  let abi: string | undefined;
  try {
    abi = /#define VERDIGRIS_ABI "([0-9a-f]+)"/.exec(fs.readFileSync(bindings, 'utf-8'))?.[1];
  } catch {
    // no bindings in this tree
  }
  if (!abi) return;
  if (!fs.existsSync(lib)) {
    Juke.logger.error(`verdigris check: ${lib} is missing; the world cannot boot without it.`);
    Juke.logger.error('Build it with tools/build/build.sh verdigris (unset DQ_PREBUILT_VERDIGRIS).');
    throw new Juke.ExitCode(1);
  }
  if (fs.readFileSync(lib).includes(Buffer.from(abi, 'latin1'))) return;
  const stat = fs.statSync(lib);
  Juke.logger.error(
    `verdigris check: ${path.resolve(lib)} (modified ${stat.mtime.toISOString()}) was not built from this tree: `
      + `it does not contain VERDIGRIS_ABI ${abi} from ${bindings}.`,
  );
  Juke.logger.error(
    'DreamDaemon would shut down at verdigris_init with an ABI mismatch and write no results. '
      + 'Rebuild the library here (drop DQ_PREBUILT_VERDIGRIS=1, or run tools/build/build.sh verdigris), '
      + 'or copy verdigris.dll from a worktree on the same commit.',
  );
  throw new Juke.ExitCode(1);
}

/** Force-kill a process tree cross-platform. */
function killProcessTree(pid: number): void {
  if (process.platform === 'win32') {
    spawnSync('taskkill', ['/pid', String(pid), '/t', '/f'], { stdio: 'ignore' });
  } else {
    try {
      process.kill(-pid, 'SIGKILL');
    } catch {
      try {
        process.kill(pid, 'SIGKILL');
      } catch {
        // already gone
      }
    }
  }
}

/**
 * Spawn DreamDaemon and resolve when the run completes, force-killing the
 * daemon if it zombies instead of exiting. See DDOptions.watchdogFile.
 */
export type DDResult = Juke.ExecReturn & {
  /** TRUE only for the genuine "still running past the hard timeout" kill --
   * NOT for the benign post-completion zombie cleanup (Windows frequently
   * fails to let dreamdaemon.exe self-close after -close; that one is
   * expected and not logged as an error). A killedByWatchdog run's results
   * file is likely missing or mid-write; callers should treat it as
   * unclean/incomplete, not just another failure. */
  killedByWatchdog?: boolean;
};

function runDreamDaemonWithWatchdog(
  exe: string,
  args: string[],
  options: DDOptions,
): Promise<DDResult> {
  const watchdogFile = options.watchdogFile as string;
  const graceMs = options.watchdogGraceMs ?? 30_000;
  // The full unit-test suite runs close to 20 minutes on a busy, contended
  // machine (many concurrent DreamDaemons across worktrees/shards), so the
  // backstop sits well above that; DQ_DD_WATCHDOG_MINUTES overrides it, and
  // callers that know their own expected duration (the sharded runner, sized
  // per shard) can pass watchdogTimeoutMs explicitly, which wins over both.
  // DQ_DD_WATCHDOG_MINUTES is a manual override and wins over everything,
  // including a caller-computed watchdogTimeoutMs (e.g. the sharded
  // runner's per-shard estimate) -- it exists for exactly the case where
  // that estimate is wrong for someone's machine/run.
  const envMinutes = Number(process.env.DQ_DD_WATCHDOG_MINUTES);
  const hardTimeoutMs = Math.min(options.watchdogMaximumMs ?? Infinity, envMinutes > 0 ? envMinutes * 60 * 1000 : (options.watchdogTimeoutMs ?? 45 * 60 * 1000));
  return new Promise((resolve) => {
    const child = spawn(exe, args, {
      stdio: 'inherit',
      detached: process.platform !== 'win32',
    });
    if (child.pid && options.onSpawn) {
      options.onSpawn(child.pid);
    }
    let settled = false;
    let hardTimeout = false;
    let graceTimer: ReturnType<typeof setTimeout> | null = null;
    const poll = setInterval(checkDone, 1_000);
    const hardTimer = setTimeout(() => finish(true, 'hard timeout', true), hardTimeoutMs);

    function finish(forceKill: boolean, reason: string, isHardTimeout: boolean) {
      if (settled) {
        return;
      }
      settled = true;
      hardTimeout = isHardTimeout;
      clearInterval(poll);
      clearTimeout(hardTimer);
      if (graceTimer) {
        clearTimeout(graceTimer);
      }
      if (forceKill && child.pid && child.exitCode === null && child.signalCode === null) {
        const log = isHardTimeout ? Juke.logger.error : Juke.logger.info;
        log(`DreamDaemon watchdog: force-killing daemon (${reason}).`);
        killProcessTree(child.pid);
      }
      // A kill request is not a reaped child. Native acquired copies remain
      // owned until close, including the forced-timeout path.
    }

    function checkDone() {
      if (settled || graceTimer) {
        return;
      }
      if (fs.existsSync(watchdogFile)) {
        // Tests finished. Give -close a chance to exit cleanly, then force-kill
        // if the daemon is still alive (the Windows zombie case).
        graceTimer = setTimeout(() => finish(true, 'run complete, daemon did not self-close', false), graceMs);
      }
    }

    child.on('exit', (code, signal) => {
      if (!settled && !graceTimer) {
        // Exited before the tests finished: record how, so a crash (e.g. an
        // NTSTATUS such as 0xC0000005 / 0xC0000409) is distinguishable from
        // a clean world shutdown.
        const hex = code === null ? 'null' : `0x${(code >>> 0).toString(16).toUpperCase()}`;
        Juke.logger.warn(`DreamDaemon exited before the run completed: code=${code} (${hex}) signal=${signal}`);
        // The exit code alone says nothing useful (a world that shuts itself
        // down, e.g. on a verdigris ABI mismatch, returns an arbitrary value
        // such as 48/80/96/128). Show what the world actually printed.
        printDaemonLog(options.daemonLog);
      }
      finish(false, 'exited', false);
    });
    child.on('error', () => finish(false, 'spawn error', false));
    child.on('close', (code, signal) => {
      finish(false, 'closed', false);
      resolve({ code: code ?? 0, signal, stdout: '', stderr: '', combined: '', killedByWatchdog: hardTimeout } as DDResult);
    });
  });
}

/**
 * Records `dmbFile` in the user's BYOND world-approval list
 * (`<userpath>/cfg/trusted.txt`) if it isn't there yet.
 *
 * Our worlds load DLLs (verdigris, rust_g) with call_ext. For a .dmb path
 * BYOND has never approved, DreamDaemon shows a modal "Security Alert: This
 * game uses one or more external libraries" dialog -- in -safe mode as well
 * as -trusted -- and waits for a click. Headless test and bench runs never
 * get one, so every run in a new worktree hung until the watchdog. The
 * dialog's "Host Game" button does exactly what this does: it appends the
 * absolute .dmb path to trusted.txt. Only that one path is added; the
 * security level the world runs with (-safe for tests) and BYOND's default
 * host-security setting are left alone. No-op off Windows (no dialog there).
 */
async function approveWorldDlls(dmbFile: string) {
  if (process.platform !== 'win32') return;
  const userPath = await regQuery('HKCU\\Software\\Dantom\\BYOND', 'userpath');
  const candidates = [
    userPath,
    process.env.USERPROFILE && path.join(process.env.USERPROFILE, 'Documents', 'BYOND'),
  ].filter(Boolean) as string[];
  const cfgDir = candidates.map((d) => path.join(d, 'cfg')).find((d) => fs.existsSync(d));
  if (!cfgDir) {
    Juke.logger.warn('BYOND user cfg folder not found; DreamDaemon may stop on a DLL approval dialog.');
    return;
  }
  const file = path.join(cfgDir, 'trusted.txt');
  const want = path.resolve(dmbFile);
  let text = '';
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    // no list yet
  }
  const listed = text.split(/\r?\n/).some((line) => line.trim().toLowerCase() === want.toLowerCase());
  if (listed) return;
  const sep = text.length && !text.endsWith('\n') ? '\r\n' : '';
  fs.appendFileSync(file, `${sep}${want}\r\n`);
  Juke.logger.info(`Approved ${want} for DLL use in ${file} (avoids BYOND's headless security dialog).`);
}

export async function DreamDaemon(
  options: DDOptions,
  ...args: any[]
): Promise<DDResult> {
  const output = options.compiledOutput ?? currentCompiledOutput(options.dmbFile, compilerMode() === 'native');
  // BYOND defaults its world directory to the DMB directory, independently of
  // the spawned process cwd. Acquiring a pair must preserve the caller's world
  // directory for config, focus files, logs and other runtime libraries.
  const hostedArgs = acquiredWorldArguments(args, options.dmbFile, output.kind === 'native_pair');
  return withCompiledOutput(output, Juke.exec, async dmbFile => {
    options.onPreparedOutput?.(dmbFile);
    const hosted = { ...options, dmbFile, compiledOutput: output };
    try { return await runHostedWorld(hosted, hostedArgs); }
    finally {
      if (output.kind === 'native_pair' && hosted.daemonLog && fs.existsSync(hosted.daemonLog)) {
        const destination = options.daemonLog ?? options.dmbFile.replace(/\.dmb$/, '.log');
        try { fs.copyFileSync(hosted.daemonLog, destination); }
        catch (error) { Juke.logger.warn(`Native daemon log preserved at ${hosted.daemonLog}: ${error}`); }
      }
    }
  });
}

async function runHostedWorld(options: DDOptions, args: any[]): Promise<DDResult> {
  checkVerdigrisAbi();
  const library = options.compiledOutput?.kind === 'native_pair'
    ? stageRuntimeLibrary(path.resolve(process.platform === 'win32' ? 'verdigris.dll' : 'libverdigris.so'), path.dirname(options.dmbFile))
    : undefined;
  let runtimeFailed = false;
  let conventionalLibrary: HostedLibraryIdentity | undefined;
  try {
  await approveWorldDlls(options.dmbFile);
  const ddExePath = await resolveDreamDaemonExecutable(options.namedDmVersion, getDmPath);
  if (options.onRuntimeIdentity) {
    // Hash the actual resolved file; unresolved PATH commands cannot certify it.
    if (!path.isAbsolute(ddExePath)) throw new CompilerProvenanceError('runtime identity requires an absolute DreamDaemon executable');
    const libraryIdentity = library?.identity ?? observeRuntimeLibrary(path.resolve(process.platform === 'win32' ? 'verdigris.dll' : 'libverdigris.so'));
    if (!library) conventionalLibrary = libraryIdentity;
    options.onRuntimeIdentity({ executable: ddExePath, sha256: createHash('sha256').update(fs.readFileSync(ddExePath)).digest('hex'),
      version: null, security: args.find(arg => ['-safe', '-trusted', '-ultrasafe'].includes(arg)) ?? 'unspecified', library: libraryIdentity });
  }

  if (options.watchdogFile) {
    // On Windows dreamdaemon.exe writes nothing to our stdout, so a world that
    // dies early would leave no trace. -logself sends its output to
    // <dmb>.log beside the (per-run) .dmb, which we print on an early exit.
    if (process.platform === 'win32' && !args.includes('-logself')) {
      options.daemonLog = options.dmbFile.replace(/\.dmb$/, '.log');
      fs.rmSync(options.daemonLog, { force: true });
      args = [...args, '-logself'];
    }
    return await runDreamDaemonWithWatchdog(ddExePath, [options.dmbFile, ...args], options);
  }
  return await Juke.exec(ddExePath, [options.dmbFile, ...args]);
  } catch (error) {
    runtimeFailed = true;
    throw error;
  } finally {
    try {
      if (conventionalLibrary) verifyObservedRuntimeLibrary(conventionalLibrary);
      library?.remove();
    }
    catch (error) {
      if (!runtimeFailed) throw error;
      console.warn('Runtime library cleanup failed; preserving the original runtime failure:', error);
    }
  }
}
