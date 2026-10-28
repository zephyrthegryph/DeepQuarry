#!/usr/bin/env node
// Wall-clock cap and orphan cleanup for a focused test run (tools/dq_focused_test.sh starts one, detached).
//
//   node tools/dq_run_guard.js --root <pid> --cap-s <seconds> --registry <dir>
//        [--queue-max-s N] [--marker <file>] [--poll-ms N] [--root-grace-s N] [--on-kill "<shell command>"]
//
// <pid> is the OS pid of the focused run's shell (on Windows its Windows pid; bash gives it as `cat /proc/$$/winpid`).
// <dir> is the world registry: the world launcher (tools/build/lib/byond.ts, runDreamDaemonWithWatchdog) writes a file named for the
// pid of every DreamDaemon it starts, and of the build runner that started it, into $DQ_WORLD_REGISTRY, and removes it when the world
// exits. Only pids in that registry are ever killed, so the resident dmbc daemon and other runs' worlds are never touched. A process
// table walk was tried and dropped: it takes tens of seconds on a loaded Windows machine.
// The cap measures RUN time: its clock starts when the run first holds a machine slot (the slot libraries write <dir>/.running then),
// not while it queues for a compile or test slot. A run that never gets a slot within --queue-max-s (default 5400) is stopped
// like a capped one, so nothing waits forever. The focused script reports the queue time separately.
// Time spent waiting in a machine-slot queue AFTER the run started is not run time either: a run that holds its compile slot and then
// queues for test worlds has a <registry>/.waiting.<pid>[.n] file for each live waiter (written by the slot libraries); the guard adds
// every poll interval in which one exists to the deadline. The total of that waiting is bounded by --queue-max-s too, so nothing waits
// forever; the marker then says "queue-ceiling" instead of "capped".
// Every poll:
//   - the run's shell is gone (killed, or its parent was): every registered process still alive is killed, so a stopped task leaves no
//     world running, and the guard exits;
//   - the deadline has passed: the same kill, the marker file is written ("capped"), and the guard keeps killing newly registered
//     worlds until the shell is gone. A shell still alive --root-grace-s (default 20) after the cap (stuck compiling, nothing
//     registered) is killed too (that process only, not its children), after which the rule above applies.
// After a kill it runs --on-kill (the focused run passes `bash tools/dq_machine_slots.sh reap`, which frees the slots a dead holder
// still shows). A registry file records the pid's image name; a pid whose image name no longer matches is not killed (pid reuse).
'use strict';
const { spawnSync, execSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const arg = (name, dflt) => {
	const i = process.argv.indexOf(name);
	return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : dflt;
};
const root = Number(arg('--root', ''));
const capMs = Number(arg('--cap-s', '')) * 1000;
const queueMaxMs = Number(arg('--queue-max-s', '5400')) * 1000;
const guardStart = Date.now();
const registry = arg('--registry', '');
const marker = arg('--marker', '');
const pollMs = Number(arg('--poll-ms', '3000'));
const rootGraceMs = Number(arg('--root-grace-s', '20')) * 1000;
const onKill = arg('--on-kill', '');
// Boot is not test time (28 October: under load a world boot alone took 4-8 min of a 10 min cap, and test phases ended with no result).
// With --boot-dir <dir> (the run's data/logs), the test cap counts from the first "Boot gate: clean" line a world writes there after the
// guard started; until then the run may take --boot-cap-s (default 900) to compile and boot. Without --boot-dir: the old single cap.
const bootDir = arg('--boot-dir', '');
const bootCapMs = Number(arg('--boot-cap-s', '900')) * 1000;
let bootAt = 0;
const bootSeen = new Map(); // tests.log path -> bytes already scanned
function bootClean() {
	if (!bootDir || bootAt) return bootAt;
	let dirs;
	try { dirs = fs.readdirSync(bootDir); } catch { return 0; }
	for (const d of dirs) {
		const f = path.join(bootDir, d, 'tests.log');
		let st;
		try { st = fs.statSync(f); } catch { continue; }
		if (st.mtimeMs < guardStart) continue;
		const from = bootSeen.get(f) || 0;
		if (st.size <= from) continue;
		try {
			const fd = fs.openSync(f, 'r');
			const buf = Buffer.alloc(st.size - from);
			fs.readSync(fd, buf, 0, buf.length, from);
			fs.closeSync(fd);
			bootSeen.set(f, st.size);
			if (buf.toString('utf8').includes('Boot gate: clean')) { bootAt = Date.now(); log(`boot gate clean in ${f}; the ${Math.round(capMs / 1000)}s test cap counts from now`); return bootAt; }
		} catch { /* best effort: try again next tick */ }
	}
	return 0;
}
if (!Number.isInteger(root) || root <= 0 || !(capMs > 0) || !registry) {
	console.error('usage: dq_run_guard.js --root <pid> --cap-s <seconds> --registry <dir> [--queue-max-s N] [--marker file] [--poll-ms N] [--root-grace-s N] [--on-kill cmd]');
	process.exit(2);
}
const win = process.platform === 'win32';
const log = (m) => console.log(`dq_run_guard[${root}]: ${m}`);

/** The image name of a live pid (lower case, no .exe), or null when no such process. */
function imageName(pid) {
	if (win) {
		const r = spawnSync('tasklist', ['/FI', `PID eq ${pid}`, '/FO', 'CSV', '/NH'], { encoding: 'utf8', windowsHide: true });
		const m = /^"([^"]+)","(\d+)"/m.exec(r.stdout || '');
		return m && Number(m[2]) === pid ? m[1].toLowerCase().replace(/\.exe$/, '') : null;
	}
	const r = spawnSync('ps', ['-p', String(pid), '-o', 'comm='], { encoding: 'utf8' });
	const name = (r.stdout || '').trim();
	return name ? path.basename(name).toLowerCase() : null;
}

function registered() { // [{pid, name, file}]
	let names;
	try { names = fs.readdirSync(registry); } catch { return []; }
	const out = [];
	for (const n of names) {
		const pid = Number(n);
		if (!Number.isInteger(pid) || pid <= 0) continue;
		const file = path.join(registry, n);
		let name = '';
		try { name = fs.readFileSync(file, 'utf8').trim().toLowerCase().replace(/\.exe$/, ''); } catch { /* unreadable: treat as unnamed */ }
		out.push({ pid, name, file });
	}
	return out;
}

function kill(pid) {
	if (win) spawnSync('taskkill', ['/pid', String(pid), '/t', '/f'], { stdio: 'ignore', windowsHide: true });
	else { try { process.kill(pid, 'SIGKILL'); } catch { /* gone */ } }
}

function killRegistered(why) {
	let killed = 0;
	for (const e of registered()) {
		const cur = imageName(e.pid);
		if (cur && (!e.name || cur === e.name)) {
			log(`killing ${cur} pid ${e.pid} (${why})`);
			kill(e.pid);
			killed++;
		}
		try { fs.rmSync(e.file, { force: true }); } catch { /* best effort */ }
	}
	if (killed && onKill) {
		try { execSync(onKill, { stdio: 'inherit' }); } catch (e) { log(`--on-kill failed: ${e.message}`); }
	}
	return killed;
}

let pausedMs = 0;
let lastTick = Date.now();
/** Is a live process waiting in a slot queue for this run? (.waiting.<pid>[.n] files of the registry; a dead pid's file is ignored and removed) */
function someoneWaiting() {
	let names;
	try { names = fs.readdirSync(registry); } catch { return false; }
	let any = false;
	for (const n of names) {
		const m = /^\.waiting\.(\d+)(\.\d+)?$/.exec(n);
		if (!m) continue;
		const pid = Number(m[1]);
		// a bash pid in the file name is an msys pid; a node pid is a Windows one: either may fail the image check, so a file also counts while it is fresh
		let fresh = false;
		try { fresh = Date.now() - fs.statSync(path.join(registry, n)).mtimeMs < 6 * 3600 * 1000; } catch { /* gone */ }
		if (fresh && (imageName(pid) !== null || !win)) any = true;
		else if (!fresh) { try { fs.rmSync(path.join(registry, n), { force: true }); } catch { /* best effort */ } }
	}
	return any;
}

let cappedAt = 0;
let startedLogged = false;
let rootKilled = false;
function tick() {
	const rootAlive = imageName(root) !== null;
	if (!rootAlive) {
		const n = killRegistered('the run that started it is gone');
		log(`run shell ended; killed ${n} orphaned process(es); exiting`);
		return process.exit(0);
	}
	let runningAt = 0;
	try { runningAt = Number(fs.readFileSync(path.join(registry, '.running'), 'utf8').trim()) * 1000 || 0; } catch { /* still queued */ }
	if (runningAt && !startedLogged) { startedLogged = true; log(`run started after queueing ${Math.round((runningAt - guardStart) / 1000)}s; cap clock starts now`); }
	const nowMs = Date.now();
	if (runningAt && someoneWaiting()) pausedMs += nowMs - lastTick;
	lastTick = nowMs;
	const queueCeiling = !runningAt ? nowMs >= guardStart + queueMaxMs : pausedMs >= queueMaxMs;
	let limitMs = runningAt + capMs;
	if (bootDir && runningAt) {
		const b = bootClean();
		limitMs = b ? Math.max(runningAt + capMs, b + capMs) : runningAt + Math.max(capMs, bootCapMs);
	}
	const overCap = queueCeiling || (runningAt && nowMs >= limitMs + pausedMs);
	if (overCap) {
		if (!cappedAt) {
			cappedAt = Date.now();
			log(queueCeiling ? `no slot after the queue ceiling (${Math.round(pausedMs / 1000)}s queued while running); stopping the run` : `wall-clock cap reached (${Math.round(pausedMs / 1000)}s of queueing not counted; ${bootDir ? (bootAt ? `test cap from the boot gate, ${Math.round((Date.now() - bootAt) / 1000)}s after it` : `no world reached the boot gate within the ${Math.round(bootCapMs / 1000)}s boot cap`) : 'single cap'})`);
			if (marker) { try { fs.writeFileSync(marker, `${queueCeiling ? 'queue-ceiling' : 'capped'}\npaused_s=${Math.round(pausedMs / 1000)}\n`); } catch { /* best effort */ } }
		}
		killRegistered('wall-clock cap');
		if (!rootKilled && Date.now() - cappedAt >= rootGraceMs) {
			rootKilled = true;
			log(`the run shell ${root} is still alive ${rootGraceMs / 1000}s after the cap; killing it`);
			if (win) spawnSync('taskkill', ['/pid', String(root), '/f'], { stdio: 'ignore', windowsHide: true });
			else { try { process.kill(root, 'SIGKILL'); } catch { /* gone */ } }
		}
	}
	setTimeout(tick, pollMs);
}
tick();
