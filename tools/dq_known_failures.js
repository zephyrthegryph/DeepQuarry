// Logic for tools/dq_known_failures.sh (read that script's header). Plain node, no dependencies.
const fs = require("fs");
const path = require("path");

const KNOWN = path.join("tools", "ci", "known_failures.txt");
const PREFIX = "/datum/unit_test/";
const short = (n) => (n.startsWith(PREFIX) ? n.slice(PREFIX.length) : n);

function loadKnown() {
	const lines = fs.existsSync(KNOWN) ? fs.readFileSync(KNOWN, "utf8").split(/\r?\n/) : [];
	return lines.map((raw) => {
		if (!raw.trim() || raw.trim().startsWith("#")) return { raw };
		const [spec, reason = "", sha = ""] = raw.split("\t");
		return { raw, spec: short(spec.trim()), reason: reason.trim(), sha: sha.trim() };
	});
}

function saveKnown(entries) {
	const out = entries.map((e) => (e.spec ? `${e.spec}\t${e.reason}\t${e.sha}` : e.raw));
	while (out.length && out[out.length - 1] === "") out.pop();
	fs.writeFileSync(KNOWN, `${out.join("\n")}\n`);
}

const matches = (spec, name) => spec === name || (spec.endsWith("/*") && name.startsWith(spec.slice(0, -1)));

function loadRun(file) {
	const r = JSON.parse(fs.readFileSync(file, "utf8"));
	return { commit: r.commit, tests: Object.fromEntries(Object.entries(r.tests || {}).map(([k, v]) => [short(k), v.status])) };
}

// Newest result per test across every record for one commit (a batch is several focused runs on the same head).
function loadHead(sha) {
	const dir = path.join("data", "test-runs");
	const key = sha.slice(0, 10);
	const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".json") && f.includes(`_${key}`)).sort() : [];
	const tests = {};
	for (const f of files) {
		let r;
		try {
			r = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
		} catch {
			continue;
		}
		if (r.commit !== key) continue;
		for (const [k, v] of Object.entries(r.tests || {})) tests[short(k)] = v.status;
	}
	return { commit: key, tests, files };
}

function classify(run, known) {
	const failed = Object.keys(run.tests).filter((n) => run.tests[n] === 1);
	const isKnown = (n) => known.some((e) => e.spec && matches(e.spec, n));
	return {
		fresh: failed.filter((n) => !isKnown(n)),
		known: failed.filter(isKnown),
		fixed: known.filter((e) => e.spec && !e.spec.endsWith("/*") && run.tests[e.spec] === 0).map((e) => e.spec),
	};
}

function check(run) {
	const known = loadKnown();
	const c = classify(run, known);
	const reason = (n) => known.find((e) => e.spec && matches(e.spec, n))?.reason || "";
	console.log(`KNOWN FAILURES CHECK: ${c.fresh.length} NEW, ${c.known.length} KNOWN`);
	for (const n of c.known) console.log(`  KNOWN  ${n}  (${reason(n)})`);
	for (const n of c.fresh) console.log(`  NEW    ${n}`);
	for (const n of c.fixed) console.log(`  FIXED  ${n}  (passes now; --refresh removes it)`);
	return c.fresh.length ? 1 : 0;
}

function refresh(run) {
	const known = loadKnown();
	let changed = 0;
	const kept = [];
	for (const e of known) {
		if (!e.spec) {
			kept.push(e);
			continue;
		}
		const names = Object.keys(run.tests).filter((n) => matches(e.spec, n));
		if (names.length && names.every((n) => run.tests[n] === 0)) {
			console.log(`  removed ${e.spec} (passes on ${run.commit})`);
			changed++;
			continue;
		}
		if (names.some((n) => run.tests[n] === 1) && e.sha !== run.commit) {
			console.log(`  updated ${e.spec}: last seen failing ${run.commit}`);
			e.sha = run.commit;
			changed++;
		}
		kept.push(e);
	}
	if (changed) saveKnown(kept);
	console.log(`known_failures: ${changed} change(s) from ${run.commit}`);
	return changed;
}

function adopt(run, reason) {
	const known = loadKnown();
	const c = classify(run, known);
	for (const n of c.fresh) known.push({ spec: n, reason, sha: run.commit });
	if (c.fresh.length) saveKnown(known);
	console.log(`known_failures: adopted ${c.fresh.length} failure(s): ${c.fresh.join(", ")}`);
}

const [cmd, arg, ...rest] = process.argv.slice(2);
const opt = (name) => {
	const i = rest.indexOf(name);
	return i >= 0 ? rest[i + 1] : undefined;
};
if (cmd === "check") process.exit(check(loadRun(arg)));
else if (cmd === "refresh") {
	const run = loadRun(arg);
	if (opt("--sha")) run.commit = opt("--sha").slice(0, 10);
	refresh(run);
} else if (cmd === "adopt") adopt(loadRun(arg), opt("--reason") || "unexplained, adopted from a run");
else if (cmd === "refresh-for-head") {
	const run = loadHead(arg);
	if (!run.files.length || !Object.keys(run.tests).length) {
		console.log(`known_failures: no focused run JSON for head ${arg.slice(0, 10)}; file unchanged`);
		process.exit(0);
	}
	console.log(`known_failures: refreshing from ${run.files.length} run(s) on ${run.commit}`);
	// Exit 10 = the file changed (the push script commits it), 0 = unchanged.
	process.exit(refresh(run) ? 10 : 0);
} else {
	console.error("usage: dq_known_failures.sh --check <run.json> | --refresh <run.json> [--sha S] | --adopt <run.json> [--reason R] | --refresh-for-head <sha>");
	process.exit(2);
}
