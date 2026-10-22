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
	const overCap = runningAt ? Date.now() >= runningAt + capMs : Date.now() >= guardStart + queueMaxMs;
	if (overCap) {
		if (!cappedAt) {
			cappedAt = Date.now();
			log(runningAt ? 'wall-clock cap reached' : 'no slot after the queue ceiling; stopping the run');
			if (marker) { try { fs.writeFileSync(marker, 'capped\n'); } catch { /* best effort */ } }
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
