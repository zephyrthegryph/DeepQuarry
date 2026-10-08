// Merges two data/test-runs/*.json records (the two worlds of dq_focused_test.sh --split-slow) into one
// data/test-runs/<stamp>_<commit>_focused.json and prints its path. Either argument may be empty (a world that
// wrote no results); the part files are removed once the merged record is written.
const fs = require("fs");
const path = require("path");

const parts = process.argv
	.slice(2)
	.filter((p) => p && fs.existsSync(p))
	.map((p) => ({ p, r: JSON.parse(fs.readFileSync(p, "utf8")) }));
if (!parts.length) process.exit(1);
const base = parts[0].r;
const tests = {};
const counts = { passed: 0, failed: 0, skipped: 0 };
const failed = [];
for (const { r } of parts) {
	for (const [name, t] of Object.entries(r.tests || {})) {
		tests[name] = t;
		if (t.status === 0) counts.passed++;
		else if (t.status === 1) {
			counts.failed++;
			failed.push(name);
		} else counts.skipped++;
	}
}
const stamp = parts.map((x) => x.r.id.split("_")[0]).sort()[0];
const record = {
	...base,
	id: `${stamp}_${base.commit}_focused`,
	label: "focused-split",
	clean: parts.every((x) => x.r.clean),
	duration_seconds: Math.max(...parts.map((x) => x.r.duration_seconds)),
	split_worlds: parts.length,
	world_seconds: parts.map((x) => x.r.duration_seconds),
	counts,
	failed: failed.sort(),
	tests,
};
const out = path.join(path.dirname(parts[0].p), `${record.id}.json`);
fs.writeFileSync(`${out}.tmp`, `${JSON.stringify(record, null, 1)}\n`);
fs.renameSync(`${out}.tmp`, out);
for (const { p } of parts) if (path.resolve(p) !== path.resolve(out)) fs.rmSync(p, { force: true });
console.log(out.replace(/\\/g, "/"));
