#!/usr/bin/env node
// Estimated seconds a test world needs for a list of tests, from the recorded runs (data/test-runs/*.json: per-test duration_ds).
// tools/dq_train.sh uses it to size a batch so the union of the lanes' tests (plus the smoke set) fits the gate's test cap.
//
//   node tools/dq_train_estimate.js [--runs DIR]... [--base SEC] [--unknown SEC] [--max-runs N] [--per-test] name|glob...
//
// A name is a /datum/unit_test name without its prefix; `dq_gameplay/*` style globs (a trailing *) match by prefix. The estimate is the
// mean recorded duration per test (a test with no record counts --unknown, default 20 s) plus --base (default 30 s: boot and world setup).
// Prints one integer, or with --per-test one `seconds<TAB>name` row per test and the total last. Exit 0; an unreadable directory is ignored.
'use strict';
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const dirs = [];
const names = [];
let base = 30;
let unknown = 20;
let maxRuns = 150;
let perTest = false;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--runs') dirs.push(args[++i]);
  else if (a === '--base') base = Number(args[++i]);
  else if (a === '--unknown') unknown = Number(args[++i]);
  else if (a === '--max-runs') maxRuns = Number(args[++i]);
  else if (a === '--per-test') perTest = true;
  else names.push(a.replace(/^\/datum\/unit_test\//, ''));
}

const sums = new Map();
for (const dir of dirs) {
  let files;
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort().slice(-maxRuns);
  } catch {
    continue;
  }
  for (const f of files) {
    let run;
    try {
      run = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    } catch {
      continue;
    }
    for (const [key, t] of Object.entries(run.tests || {})) {
      // a record with no durations at all (older runs) says nothing
      if (typeof t.duration_ds !== 'number') continue;
      const name = key.replace(/^\/datum\/unit_test\//, '');
      const s = sums.get(name) || { total: 0, n: 0 };
      s.total += t.duration_ds / 10;
      s.n += 1;
      sums.set(name, s);
    }
  }
}

function mean(name) {
  if (name.endsWith('*')) {
    const prefix = name.slice(0, -1);
    let total = 0;
    let any = false;
    for (const [k, s] of sums) {
      if (k.startsWith(prefix)) {
        total += s.total / s.n;
        any = true;
      }
    }
    return any ? total : unknown;
  }
  const s = sums.get(name);
  return s ? s.total / s.n : unknown;
}

let total = base;
const rows = [];
for (const n of new Set(names)) {
  const sec = mean(n);
  total += sec;
  rows.push([sec, n]);
}
if (perTest) {
  rows.sort((a, b) => b[0] - a[0]);
  for (const [sec, n] of rows) console.log(`${Math.round(sec)}\t${n}`);
}
console.log(Math.round(total));
