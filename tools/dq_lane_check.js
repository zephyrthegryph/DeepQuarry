#!/usr/bin/env node
// The logic of tools/dq_lane_check.sh (read its header). Node because the stamp is JSON and the rules are set arithmetic.
'use strict';
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');

const NOTES = 'refs/notes/lane-ready';
const NON_CODE = [/^html\/changelogs\//, /^doc\//, /^data\//, /^[A-Za-z_.-]+\.md$/];

function git(args, opts = {}) {
  const r = spawnSync('git', args, { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, ...opts });
  return { ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

function lines(s) {
  return s ? s.split(/\r?\n/).filter(Boolean) : [];
}

function globToRegex(glob) {
  const esc = glob.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*\*/g, '\u0000').replace(/\*/g, '[^/]*').replace(/\u0000/g, '.*');
  return new RegExp(`^${esc}`);
}

function globalPrefixes(file = 'tools/ci/lane_ready_global.txt') {
  try {
    return fs
      .readFileSync(file, 'utf8')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith('#'));
  } catch {
    return [];
  }
}

/** The note on `ref` or on the nearest ancestor (at most 40 back) whose later commits touch no code. */
function findStamp(ref) {
  const revs = lines(git(['rev-list', '-n', '40', ref]).out);
  for (const c of revs) {
    const note = git(['notes', `--ref=${NOTES}`, 'show', c]);
    if (!note.ok || !note.out) continue;
    let stamp;
    try {
      stamp = JSON.parse(note.out);
    } catch {
      return { error: `the note on ${c.slice(0, 10)} is not JSON` };
    }
    if (c !== revs[0]) {
      const later = lines(git(['diff', '--name-only', c, revs[0]]).out).filter((f) => !NON_CODE.some((re) => re.test(f)));
      if (later.length) return { error: `${later.length} file(s) changed after the stamped commit ${c.slice(0, 10)} (${later.slice(0, 3).join(', ')})`, stamp, commit: c };
    }
    return { stamp, commit: c };
  }
  return { none: true };
}

function testFiles(tests) {
  const files = new Set();
  for (const t of tests) {
    const name = t.replace(/^\/datum\/unit_test\//, '');
    const base = name.split('/')[0];
    const r = git(['grep', '-l', '-E', `^/datum/unit_test/${base}(/|[[:space:]]|$)`, '--', 'code/*.dm']);
    for (const f of lines(r.out)) files.add(f);
  }
  return files;
}

/** Files derived from the tree, regenerated after every merge (look keys, the factored pin bases): an overlap there is no overlap. */
const REGENERATED = [/^code\/modules\/unit_tests\/snapshots\/look_keys\.txt$/, /^code\/modules\/unit_tests\/snapshots\/op_bases\//];

/** The snapshot directories the files defining the tests read (`code/modules/unit_tests/snapshots/<dir>/`). */
function snapshotDirs(tfiles) {
  const dirs = new Set();
  for (const f of tfiles) {
    let text = '';
    try {
      text = fs.readFileSync(f, 'utf8');
    } catch {
      continue;
    }
    for (const m of text.matchAll(/code\/modules\/unit_tests\/snapshots\/[A-Za-z0-9_]+\//g)) dirs.add(m[0]);
  }
  return dirs;
}

function check(ref, master) {
  const found = findStamp(ref);
  if (found.none) return { verdict: 'UNSTAMPED', why: 'no lane-ready note on this branch (run tools/dq_lane_ready.sh in the lane)', tests: [] };
  if (found.error && !found.stamp) return { verdict: 'INVALID', why: found.error, tests: [] };
  const s = found.stamp;
  const tests = s.tests || [];
  if (found.error) return { verdict: 'INVALID', why: found.error, tests };
  // A failure tools/ci/known_failures.txt lists is not the lane's (new_failed counts the others; an older stamp has only failed).
  const lost = s.new_failed ?? s.failed;
  if (!s.ok || lost > 0) return { verdict: 'INVALID', why: `the stamp records a failed run (${lost} failed)`, tests };
  const masterTip = git(['rev-parse', master]);
  if (!masterTip.ok) return { verdict: 'INVALID', why: `no ${master}`, tests };
  if (s.master_commit === masterTip.out) return { verdict: 'VALID', why: `base is current (master ${masterTip.out.slice(0, 10)})`, tests };
  if (!git(['merge-base', '--is-ancestor', s.master_commit, master]).ok) {
    return { verdict: 'INVALID', why: `the stamp's master ${String(s.master_commit).slice(0, 10)} is not in ${master}'s history (rebased or force-pushed)`, tests };
  }
  const delta = lines(git(['diff', '--name-only', s.master_commit, master]).out);
  const own = lines(git(['diff', '--name-only', s.master_commit, found.commit]).out);
  const dirs = new Set(own.map((f) => f.replace(/[^/]*$/, '')).filter(Boolean));
  const tfiles = testFiles(tests);
  const covers = (s.covers || []).map(globToRegex);
  const globals = globalPrefixes();
  const hits = [];
  const ignored = [];
  const snaps = snapshotDirs(tfiles);
  const docReads = globalPrefixes('tools/ci/lane_ready_doc_reads.txt');
  for (const f of delta) {
    if (REGENERATED.some((re) => re.test(f))) continue;
    let why = '';
    // Changelogs, docs, data and root markdown are not compiled, generated, linted or tested: master changing them never moves a
    // result, unless a tool reads that very file (tools/ci/lane_ready_doc_reads.txt). This also beats the "directory the branch changed" rule.
    if (NON_CODE.some((re) => re.test(f))) {
      if (docReads.some((g) => f.startsWith(g))) hits.push(`${f} (a doc a tool reads, tools/ci/lane_ready_doc_reads.txt)`);
      else ignored.push(f);
      continue;
    }
    if (own.includes(f)) why = 'a file the branch changed';
    else if ([...snaps].some((d) => f.startsWith(d))) why = 'a snapshot its tests read';
    else if (tfiles.has(f)) why = 'a file that defines its tests';
    else if (globals.some((g) => f.startsWith(g))) why = 'a global path (tools/ci/lane_ready_global.txt)';
    else if (covers.some((re) => re.test(f))) why = 'covered by the stamp';
    else {
      const dir = f.replace(/[^/]*$/, '');
      if (dirs.has(dir)) why = 'a directory the branch changed';
    }
    if (why) hits.push(`${f} (${why})`);
  }
  if (hits.length) {
    return { verdict: 'INVALID', why: `master changed ${hits.length} file(s) the stamp depends on since ${String(s.master_commit).slice(0, 10)}: ${hits.slice(0, 8).join('; ')}${hits.length > 8 ? '; ...' : ''}${ignored.length ? ` (${ignored.length} changelog/doc/data file(s) ignored)` : ''}`, tests };
  }
  const others = delta.length - ignored.length;
  return { verdict: 'VALID', why: `kept: master moved ${delta.length} file(s) since ${String(s.master_commit).slice(0, 10)}; ${ignored.length} changelog/doc/data file(s) ignored${ignored.length ? ` (${ignored.slice(0, 3).join(', ')}${ignored.length > 3 ? ', ...' : ''})` : ''}; ${others} other file(s), none the branch's files, directories, covers or tests depend on`, tests };
}

const args = process.argv.slice(2);
let master = 'origin/master';
const refs = [];
let fetch = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--fetch') fetch = true;
  else if (args[i] === '--master') master = args[++i];
  else if (args[i] === '-h' || args[i] === '--help') {
    console.log(fs.readFileSync(__dirname + '/dq_lane_check.sh', 'utf8').split('\n').slice(1, 22).join('\n'));
    process.exit(0);
  } else refs.push(args[i]);
}
if (!refs.length) {
  console.error('usage: dq_lane_check.sh [--fetch] [--master REF] <branch-or-commit>...');
  process.exit(2);
}
if (fetch) {
  git(['fetch', '-q', 'origin']);
  git(['fetch', '-q', 'origin', `+${NOTES}:${NOTES}`]);
}
let allValid = true;
/** The ref a person meant: as given, then rewrite/<name>, origin/<name>, origin/rewrite/<name>. */
function resolveRef(ref) {
  for (const cand of [ref, `rewrite/${ref}`, `origin/${ref}`, `origin/rewrite/${ref}`]) {
    if (git(['rev-parse', '-q', '--verify', `${cand}^{commit}`]).ok) return cand;
  }
  return null;
}

/** The branch names recorded in the stamps of this clone, for the hint when a name matches nothing. */
function stampedBranches() {
  const names = new Set();
  for (const row of lines(git(['notes', `--ref=${NOTES}`, 'list']).out)) {
    const note = git(['notes', `--ref=${NOTES}`, 'show', row.split(' ')[1]]);
    try {
      const b = JSON.parse(note.out).branch;
      if (b) names.add(b);
    } catch {
      /* not a stamp */
    }
  }
  return [...names];
}

for (const given of refs) {
  const ref = resolveRef(given);
  if (!ref) {
    const known = stampedBranches();
    console.log(`LANE ${given} UNSTAMPED no such ref (tried ${given}, rewrite/${given}, origin/...); stamped branches: ${known.join(' ') || 'none'} tests=`);
    allValid = false;
    continue;
  }
  const r = check(ref, master);
  if (r.verdict !== 'VALID') allValid = false;
  console.log(`LANE ${ref} ${r.verdict} ${r.why} tests=${r.tests.map((t) => t.replace(/^\/datum\/unit_test\//, '')).join(',')}`);
}
process.exit(allValid ? 0 : 1);
