/**
 * Renders data/bench/report.html: a self-contained page (no network, no
 * libraries) showing benchmark history, the latest run against the previous
 * one on the same map, the latest memory timeline, and unit-test history.
 */

import fs from 'node:fs';
import {
  BENCH_RUNS_DIR,
  type BenchRun,
  compareRuns,
  formatNumber,
  listRuns,
  type ProcessSample,
  readJson,
  TEST_RUNS_DIR,
  type TestRun,
} from './bench';

const escape = (text: unknown) =>
  String(text).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] as string);

function sparkline(values: number[], width = 160, height = 32): string {
  const points = values.filter(Number.isFinite);
  if (points.length < 2) return '';
  const min = Math.min(...points);
  const max = Math.max(...points);
  const span = max - min || 1;
  const coords = points
    .map((v, i) => `${((i / (points.length - 1)) * (width - 4) + 2).toFixed(1)},${(height - 2 - ((v - min) / span) * (height - 4)).toFixed(1)}`)
    .join(' ');
  const [lx, ly] = coords.split(' ').pop()!.split(',');
  return `<svg class="spark" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="trend"><polyline points="${coords}"/><circle cx="${lx}" cy="${ly}" r="2.5"/></svg>`;
}

function memoryTimeline(samples: ProcessSample[], phases: { name: string; t: number }[]): string {
  if (samples.length < 2) return '<p class="muted">No process samples recorded.</p>';
  const width = 720;
  const height = 180;
  const maxT = samples[samples.length - 1].t || 1;
  const maxMb = Math.max(...samples.map((s) => s.private_mb)) * 1.05 || 1;
  const x = (t: number) => 40 + (t / maxT) * (width - 50);
  const y = (mb: number) => height - 24 - (mb / maxMb) * (height - 40);
  const line = samples.map((s) => `${x(s.t).toFixed(1)},${y(s.private_mb).toFixed(1)}`).join(' ');
  const ticks = [0, 0.5, 1].map((f) => {
    const mb = maxMb * f;
    return `<text x="4" y="${y(mb) + 4}">${Math.round(mb)}</text><line class="grid" x1="40" x2="${width - 10}" y1="${y(mb)}" y2="${y(mb)}"/>`;
  });
  const marks = phases.map((p) => `<line class="phase" x1="${x(p.t)}" x2="${x(p.t)}" y1="10" y2="${height - 24}"/><text class="phase-label" x="${x(p.t) + 3}" y="20">${escape(p.name)}</text>`);
  return `<svg class="timeline" viewBox="0 0 ${width} ${height}" role="img" aria-label="Private memory over time">
${ticks.join('')}${marks.join('')}
<polyline class="mem" points="${line}"/>
<text x="40" y="${height - 6}">0 s</text><text x="${width - 60}" y="${height - 6}">${Math.round(maxT)} s</text>
<text x="4" y="12">MB</text></svg>`;
}

export function renderReport(outFile: string): { runs: number; tests: number } {
  const benchRuns = listRuns(BENCH_RUNS_DIR).map((f) => readJson<BenchRun>(f));
  const testRuns = listRuns(TEST_RUNS_DIR).map((f) => readJson<TestRun>(f));
  const sections: string[] = [];

  const latest = benchRuns[benchRuns.length - 1];
  if (latest) {
    const sameMap = benchRuns.filter((r) => r.map === latest.map);
    const previous = sameMap.length > 1 ? sameMap[sameMap.length - 2] : null;
    const comparison = previous ? compareRuns(previous, latest, 5) : [];
    const verdictOf = (scenario: string, metric: string) =>
      comparison.find((c) => c.scenario === scenario && c.metric === metric);

    sections.push(`<section><h2>Latest benchmark</h2>
<p><b>${escape(latest.id)}</b> on ${escape(latest.map)} · commit ${escape(latest.commit)}${latest.dirty_files ? ` (+${latest.dirty_files} uncommitted files)` : ''} · ${escape(latest.iterations.length)} iteration(s)${previous ? ` · compared with ${escape(previous.id)}` : ''}</p>
${latest.failures.length ? `<p class="bad">Failures: ${latest.failures.map(escape).join('; ')}</p>` : ''}</section>`);

    for (const [scenario, metrics] of Object.entries(latest.summary)) {
      const rows = Object.entries(metrics).map(([name, stats]) => {
        const history = sameMap.map((r) => r.summary[scenario]?.[name]?.median ?? NaN);
        const cmp = verdictOf(scenario, name);
        const change = cmp && Number.isFinite(cmp.change_pct) ? `${cmp.change_pct >= 0 ? '+' : ''}${cmp.change_pct.toFixed(1)}%` : '';
        return `<tr class="${cmp?.verdict ?? ''}"><td>${escape(name)}</td><td class="num">${formatNumber(stats.median)} <span class="unit">${escape(stats.unit)}</span></td><td class="num">${stats.n > 1 ? `±${formatNumber(stats.stdev)}` : ''}</td><td class="num">${change}</td><td>${cmp && cmp.verdict !== 'unchanged' ? escape(cmp.verdict) : ''}</td><td>${sparkline(history)}</td></tr>`;
      });
      sections.push(`<section><h3>${escape(scenario)}</h3><div class="scroll"><table>
<thead><tr><th>metric</th><th>median</th><th>spread</th><th>vs previous</th><th></th><th>history (${sameMap.length} runs)</th></tr></thead>
<tbody>${rows.join('\n')}</tbody></table></div></section>`);
    }

    const iteration = latest.iterations.find((it) => !it.warmup) ?? latest.iterations[0];
    if (iteration) {
      const start = iteration.process_samples[0];
      const phases: { name: string; t: number }[] = [];
      for (const scenario of Object.values(iteration.scenarios ?? {})) {
        for (const phase of (scenario.phases ?? []) as { name: string; process?: ProcessSample }[]) {
          if (phase.process?.t !== undefined) phases.push({ name: phase.name, t: phase.process.t - (start?.t ?? 0) });
        }
      }
      sections.push(`<section><h3>Memory timeline (iteration ${iteration.iteration})</h3>${memoryTimeline(iteration.process_samples, phases)}</section>`);
      const worst: string[] = [];
      for (const scenario of Object.values(iteration.scenarios ?? {})) {
        for (const [key, value] of Object.entries(scenario.details ?? {})) {
          if (!key.endsWith('_outliers') || !Array.isArray(value) || !value.length) continue;
          for (const tick of value as { usage: number; top_subsystem: string; world_time: number }[]) {
            worst.push(`<tr><td>${escape(scenario.id)}</td><td>${escape(key.replace(/_outliers$/, ''))}</td><td class="num">${Math.round(tick.usage)}%</td><td>${escape(tick.top_subsystem)}</td><td class="num">${escape(tick.world_time)}</td></tr>`);
          }
        }
      }
      if (worst.length) {
        sections.push(`<section><h3>Overrun ticks</h3><div class="scroll"><table><thead><tr><th>scenario</th><th>window</th><th>usage</th><th>top subsystem</th><th>world.time</th></tr></thead><tbody>${worst.join('')}</tbody></table></div></section>`);
      }
    }
  } else {
    sections.push('<section><h2>Benchmarks</h2><p class="muted">No benchmark runs stored yet. Run <code>tools/build/build.sh bench</code>.</p></section>');
  }

  if (testRuns.length) {
    const recent = testRuns.slice(-20).reverse();
    const rows = recent.map((r) => `<tr class="${r.counts.failed ? 'regression' : ''}"><td>${escape(r.id)}</td><td class="num">${r.counts.passed}</td><td class="num">${r.counts.failed}</td><td class="num">${r.counts.skipped}</td><td class="num">${Math.round(r.duration_seconds)} s</td><td>${r.clean ? 'clean' : 'not clean'}</td><td>${r.failed.map((f) => escape(f.replace('/datum/unit_test/', ''))).join('<br>')}</td></tr>`);
    sections.push(`<section><h2>Unit-test runs</h2><p>${sparkline(testRuns.map((r) => r.counts.failed), 240, 36)} failures over ${testRuns.length} stored runs</p><div class="scroll"><table>
<thead><tr><th>run</th><th>passed</th><th>failed</th><th>skipped</th><th>time</th><th></th><th>failed tests</th></tr></thead><tbody>${rows.join('\n')}</tbody></table></div></section>`);
  }

  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>DeepQuarry Benchmarks</title>
<style>
:root { --bg:#fbfbfa; --fg:#1d1d1b; --muted:#6b6b66; --line:#dddcd6; --accent:#2f6fb0; --bad:#b3261e; --good:#1e7a3c; --card:#ffffff; }
@media (prefers-color-scheme: dark) { :root { --bg:#161615; --fg:#e8e7e2; --muted:#9a9990; --line:#34332f; --accent:#7fb2e5; --bad:#f2847a; --good:#7ccf93; --card:#1f1f1d; } }
body { background:var(--bg); color:var(--fg); font:14px/1.45 system-ui, sans-serif; margin:0; padding:24px 16px; }
main { max-width:1100px; margin:0 auto; }
h1 { font-size:22px; margin:0 0 4px; } h2 { font-size:17px; margin:28px 0 8px; } h3 { font-size:15px; margin:20px 0 6px; }
section { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:12px 16px; margin:12px 0; }
.scroll { overflow-x:auto; }
table { border-collapse:collapse; width:100%; font-variant-numeric:tabular-nums; }
th, td { text-align:left; padding:4px 8px; border-bottom:1px solid var(--line); vertical-align:middle; }
th { color:var(--muted); font-weight:500; font-size:12px; }
td.num { text-align:right; white-space:nowrap; } .unit, .muted { color:var(--muted); }
tr.regression td:nth-child(4), tr.regression td:nth-child(5), .bad { color:var(--bad); }
tr.improvement td:nth-child(4), tr.improvement td:nth-child(5) { color:var(--good); }
svg.spark polyline { fill:none; stroke:var(--accent); stroke-width:1.5; } svg.spark circle { fill:var(--accent); }
svg.timeline { width:100%; height:auto; } svg.timeline text { fill:var(--muted); font-size:10px; }
svg.timeline .mem { fill:none; stroke:var(--accent); stroke-width:1.8; } svg.timeline .grid { stroke:var(--line); }
svg.timeline .phase { stroke:var(--muted); stroke-dasharray:3 3; } svg.timeline .phase-label { fill:var(--fg); }
code { font-size:13px; }
</style></head><body><main>
<h1>DeepQuarry benchmarks</h1>
<p class="muted">Generated ${escape(new Date().toISOString())} from ${benchRuns.length} benchmark run(s) and ${testRuns.length} test run(s) in <code>data/</code>. Regenerate with <code>tools/build/build.sh bench-report</code>.</p>
${sections.join('\n')}
</main></body></html>
`;
  fs.writeFileSync(outFile, html);
  return { runs: benchRuns.length, tests: testRuns.length };
}
