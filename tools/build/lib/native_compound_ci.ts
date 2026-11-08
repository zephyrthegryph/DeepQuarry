import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { pipeline } from 'node:stream/promises';
import { assertDirectoryChain, createNativeRequestDirectory } from './native_pair';
import { dmbcVersionDir, readCurrentDmbcVersion, sharedDmbcBinDir } from './dmbc_cache';
import { observedExecutable } from './compiler_provenance';
import { enterDaemonScope } from './dmbc_daemons';

const MAX_HEADER = 1024;
const MAX_REPORTS = 64 * 1024 * 1024;
const TIMEOUT_SECONDS = 300;
const ROOTS = ['code', 'doc/rewrite', 'interface', 'maps', 'modular_chomp', 'tgui'] as const;

export function fullCiCompoundRequest(root: string, cache: string, workers: number) {
  if (!path.isAbsolute(root) || !path.isAbsolute(cache) || !Number.isSafeInteger(workers) || workers < 1 || workers > 8) {
    throw new Error('Compound CI requires absolute source/cache paths and one to eight workers.');
  }
  return {
    analyze_registry: 'full',
    analyze_judgment: 'ci',
    strict_profile: 'cbt',
    output_name: 'compound-ci',
    selected: {
      exclusions: [],
      build: {
        command: 'PrepareQuery',
        project: path.join(root, 'deepquarry.dme'),
        defines: {},
        workers,
        engine_template: null,
        bootstrap_catalog: false,
        progress_enabled: false,
        output_store: null,
        exact_inputs: true,
        no_cache: true,
        cache_root: cache,
        record_inputs: null,
        replay_inputs: null,
        artifact_directory: null,
        no_daemon: false,
        trace_path: null,
        timeout_seconds: TIMEOUT_SECONDS,
        policy_inputs: {
          analysis_context: 'original_analyze0290',
          files: [],
          search_folders: [],
          workspace_generators: [],
          workspace_auxiliary: [],
          workspace: {
            root,
            recursive_roots: ROOTS.map((name) => path.join(root, name)),
            configuration: path.join(root, 'tools', 'ci', 'lint_scopes.toml'),
          },
        },
      },
    },
  };
}

function sealLength(value: unknown): number {
  if (!value || typeof value !== 'object') throw new Error('Compound CI receipt lacks a report seal.');
  const { length, hash } = value as { length: number; hash: string };
  if (!Number.isSafeInteger(length) || length < 1 || length > MAX_REPORTS
      || typeof hash !== 'string' || !/^[a-f0-9]{32}$/.test(hash)) {
    throw new Error('Compound CI receipt has an invalid report seal.');
  }
  return length;
}

/** Rust verifies the pair and all hashes before it emits the receipt. This
 * checks mode, status and byte framing without decoding u128 pair hashes
 * into imprecise JS numbers or loading either report into memory. */
export function requireFullCiReceipt(prefix: Buffer, stdoutBytes: number, stderrBytes: number, exit: 0 | 1): void {
  const newline = prefix.indexOf(10);
  if (newline < 0 || newline >= MAX_HEADER) throw new Error('Compound CI receipt header is missing or oversized.');
  const receipt = JSON.parse(prefix.toString('utf8', 0, newline));
  const reports = receipt?.selected;
  if (receipt?.schema !== 'native-compiled-full-registry-ci-cbt-v1'
      || reports?.schema !== 'native-checker-analyze-full-registry-ci-cbt-v1'
      || reports.clean !== (exit === 0)
      || receipt.native_pair?.version !== 1
      || !Number.isSafeInteger(receipt.native_pair.dmb_bytes) || receipt.native_pair.dmb_bytes < 1) {
    throw new Error('Compound CI receipt does not match the requested Strict CBT gate.');
  }
  const diagnostics = reports.diagnostics === null ? 0 : sealLength(reports.diagnostics);
  const reportsBytes = sealLength(reports.checker) + sealLength(reports.report);
  if (diagnostics !== stderrBytes || reportsBytes + diagnostics > MAX_REPORTS
      || stdoutBytes !== newline + 1 + reportsBytes) {
    throw new Error('Compound CI receipt does not cover the exact report bytes.');
  }
}

function publishedCompiler() {
  const bin = sharedDmbcBinDir();
  const version = readCurrentDmbcVersion(bin);
  if (!version) throw new Error('Compound CI requires an installed immutable compiler version.');
  const directory = path.resolve(dmbcVersionDir(bin, version));
  assertDirectoryChain(directory);
  const suffix = process.platform === 'win32' ? '.exe' : '';
  const client = observedExecutable(path.resolve(directory, 'dmbc' + suffix));
  const daemon = observedExecutable(path.resolve(directory, 'dmbd' + suffix));
  const physical = fs.realpathSync.native(directory);
  if (!client.sha256 || !daemon.sha256 || path.dirname(client.executable) !== physical
      || path.dirname(daemon.executable) !== physical) {
    throw new Error('Compound CI compiler pair did not resolve inside its published version.');
  }
  return { version, client, daemon };
}

function invoke(
  executable: string, request: string, cwd: string, stdout: number, stderr: number,
): Promise<number> {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, ['compile-checker-analyze-selected', request, '--report-batch'], {
      cwd, windowsHide: true, stdio: ['ignore', stdout, stderr], timeout: (TIMEOUT_SECONDS + 30) * 1000,
    });
    child.once('error', reject);
    child.once('close', (code, signal) => {
      if (code === null || signal !== null) reject(new Error('Compound CI client did not finish within its execution budget.'));
      else resolve(code);
    });
  });
}

function readHeader(file: string): Buffer {
  const fd = fs.openSync(file, 'r');
  try {
    const prefix = Buffer.alloc(MAX_HEADER);
    let length = 0;
    while (length < prefix.length) {
      const read = fs.readSync(fd, prefix, length, prefix.length - length, length);
      if (read === 0) break;
      length += read;
    }
    return prefix.subarray(0, length);
  } finally {
    fs.closeSync(fd);
  }
}

/** Called while the ordinary DM compile slot is held. Pair artifacts stay
 * under the existing budgeted native integration cache, never the checkout. */
export async function runFullCiCompound(root: string, workers: number): Promise<number> {
  root = fs.realpathSync.native(root);
  if (process.env.DMB_DAEMON_NAMESPACE) throw new Error('Compound CI requires the shared versioned compiler daemon.');
  const compiler = publishedCompiler();
  const scratch = createNativeRequestDirectory('compound-ci');
  const request = path.join(scratch, 'request.json');
  const stdout = path.join(scratch, 'stdout');
  const stderr = path.join(scratch, 'stderr');
  const scope = enterDaemonScope(root, compiler.client.executable);
  try {
    fs.writeFileSync(request, JSON.stringify(fullCiCompoundRequest(root, scratch, workers)), { flag: 'wx' });
    const out = fs.openSync(stdout, 'wx');
    let code: number;
    try {
      const err = fs.openSync(stderr, 'wx');
      try { code = await invoke(compiler.client.executable, request, root, out, err); }
      finally { fs.closeSync(err); }
    } finally { fs.closeSync(out); }

    if (JSON.stringify(compiler) !== JSON.stringify(publishedCompiler())) {
      throw new Error('Published native compiler changed during compound CI.');
    }
    const stdoutBytes = fs.statSync(stdout).size;
    const stderrBytes = fs.statSync(stderr).size;
    if (stderrBytes > MAX_REPORTS || stdoutBytes > MAX_HEADER + MAX_REPORTS) {
      throw new Error('Compound CI client exceeded the report envelope.');
    }
    if (code === 0 || code === 1) {
      requireFullCiReceipt(readHeader(stdout), stdoutBytes, stderrBytes, code);
      await pipeline(fs.createReadStream(stderr), process.stderr, { end: false });
      await pipeline(fs.createReadStream(stdout), process.stdout, { end: false });
    } else {
      if (stdoutBytes !== 0) throw new Error('Refused compound CI request emitted a partial success report.');
      await pipeline(fs.createReadStream(stderr), process.stderr, { end: false });
    }
    return code;
  } finally {
    scope.release();
    for (const file of [request, stdout, stderr]) {
      try { fs.rmSync(file, { force: true }); }
      catch (error) { process.stderr.write('Compound CI scratch cleanup preserved ' + file + ': ' + String(error) + '\n'); }
    }
  }
}
