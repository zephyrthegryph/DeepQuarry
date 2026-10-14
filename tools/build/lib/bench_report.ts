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

type DataRow = Record<string, unknown>;

const dataRow = (value: unknown): DataRow =>
  value && typeof value === 'object' && !Array.isArray(value) ? value as DataRow : {};

const numberField = (row: DataRow, key: string): number =>
  typeof row[key] === 'number' && Number.isFinite(row[key]) ? row[key] as number : 0;

const detailJson = (value: unknown): string =>
  `<details><summary>Full record</summary><pre>${escape(JSON.stringify(value, null, 2))}</pre></details>`;

/** Scheduler costs are sampled. Counts and sampled totals cover only this window. */
function schedulerSections(iteration: BenchRun['iterations'][number]): string[] {
  const windows: { scenario: string; window: string; diagnostic: DataRow }[] = [];
  const systems: { scenario: string; window: string; name: string; data: DataRow }[] = [];
  const slowCalls: { scenario: string; window: string; data: DataRow }[] = [];
  const incidents: { scenario: string; window: string; data: DataRow }[] = [];
  for (const scenario of Object.values(iteration.scenarios ?? {})) {
    for (const [key, value] of Object.entries(scenario.details ?? {})) {
      if (!key.endsWith('_scheduler')) continue;
      const window = key.replace(/_scheduler$/, '');
      const diagnostic = dataRow(value);
      windows.push({ scenario: scenario.id, window, diagnostic });
      for (const [name, raw] of Object.entries(dataRow(diagnostic.systems))) {
        systems.push({ scenario: scenario.id, window, name, data: dataRow(raw) });
      }
      for (const raw of Array.isArray(diagnostic.slow_calls) ? diagnostic.slow_calls : []) {
        slowCalls.push({ scenario: scenario.id, window, data: dataRow(raw) });
      }
      for (const raw of Array.isArray(diagnostic.incidents) ? diagnostic.incidents : []) {
        incidents.push({ scenario: scenario.id, window, data: dataRow(raw) });
      }
    }
  }
  const sections: string[] = [];
  if (windows.length) {
    const rows = windows.map(({ scenario, window, diagnostic }) => {
      const totals = dataRow(diagnostic.totals);
      const pending = Object.entries(dataRow(diagnostic.pending_end))
        .map(([name, count]) => `${name}: ${formatNumber(Number(count))}`)
        .join(', ');
      return `<tr><td>${escape(scenario)}</td><td>${escape(window)}</td>
<td class="num">${formatNumber(numberField(totals, 'calls'))}</td>
<td class="num">${formatNumber(numberField(diagnostic, 'work_units'))}</td>
<td class="num">${formatNumber(numberField(diagnostic, 'estimated_window_ms'))}</td>
<td class="num">${formatNumber(numberField(totals, 'slow_calls'))}</td>
<td class="num">${formatNumber(numberField(totals, 'deadline_misses'))}</td>
<td class="num">${formatNumber(numberField(totals, 'deferred_budget'))}</td>
<td class="num">${formatNumber(numberField(totals, 'deferred_tick'))}</td>
<td>${escape(pending)}</td></tr>`;
    });
    sections.push(`<section><h3>Scheduler windows (iteration ${iteration.iteration})</h3><div class="scroll"><table><thead><tr><th>scenario</th><th>window</th><th>calls</th><th>work units</th><th>est. ms</th><th>slow</th><th>late</th><th>budget deferrals</th><th>tick deferrals</th><th>pending at end</th></tr></thead><tbody>${rows.join('')}</tbody></table></div></section>`);
  }
  if (systems.length) {
    systems.sort((a, b) =>
      numberField(b.data, 'estimated_window_ms') - numberField(a.data, 'estimated_window_ms')
      || numberField(b.data, 'deadline_misses') - numberField(a.data, 'deadline_misses'));
    const rows = systems.map(({ scenario, window, name, data }) => `<tr>
<td>${escape(scenario)}</td><td>${escape(window)}</td><td>${escape(name)}</td>
<td class="num">${formatNumber(numberField(data, 'calls'))}</td>
<td class="num">${formatNumber(numberField(data, 'sampled_calls'))}</td>
<td class="num">${formatNumber(numberField(data, 'estimated_window_ms'))}</td>
<td class="num">${formatNumber(numberField(data, 'sampled_total_ms'))}</td>
<td class="num">${formatNumber(numberField(data, 'max_call_ms_since_boot'))}</td>
<td class="num">${formatNumber(numberField(data, 'slow_calls'))}</td>
<td class="num">${formatNumber(numberField(data, 'deadline_misses'))}</td>
<td class="num">${formatNumber(numberField(data, 'max_lateness_ds_since_boot') / 10)}</td></tr>`);
    sections.push(`<section><h3>Scheduler systems (iteration ${iteration.iteration})</h3>
<p class="muted">Estimated window time scales the sampled average by call count. Call counts, sampled time, slow calls and missed deadlines cover the measurement window. Worst call and maximum lateness are since boot. Budget and tick deferrals are shown in the scenario metrics.</p>
<div class="scroll"><table><thead><tr><th>scenario</th><th>window</th><th>system</th><th>calls</th><th>samples</th><th>est. ms</th><th>sampled ms</th><th>worst ms</th><th>slow</th><th>late</th><th>max late s</th></tr></thead><tbody>${rows.join('')}</tbody></table></div></section>`);
  }
  if (slowCalls.length) {
    const rows = slowCalls.map(({ scenario, window, data }) => `<tr>
<td>${escape(scenario)}</td><td>${escape(window)}</td><td>${escape(data.kind)} · ${escape(data.system_type)}</td><td>${escape(data.entity_type)}</td>
<td class="num">${formatNumber(numberField(data, 'elapsed_ms'))}</td><td class="num">${formatNumber(numberField(data, 'slow_limit_ms'))}</td><td class="num">${formatNumber(numberField(data, 'lateness_ds') / 10)}</td>
<td>${escape(data.reason)}</td><td>${detailJson(data)}</td></tr>`);
    sections.push(`<section><h3>Recent slow scheduler calls</h3><div class="scroll"><table><thead><tr><th>scenario</th><th>window</th><th>system</th><th>entity</th><th>ms</th><th>slow limit ms</th><th>late s</th><th>reason</th><th>detail</th></tr></thead><tbody>${rows.join('')}</tbody></table></div></section>`);
  }
  if (incidents.length) {
    const rows = incidents.map(({ scenario, window, data }) => {
      const subsystems = (Array.isArray(data.subsystems) ? data.subsystems : [])
        .map(dataRow)
        .sort((a, b) => numberField(b, 'usage') - numberField(a, 'usage'));
      const top = subsystems[0];
      return `<tr><td>${escape(scenario)}</td><td>${escape(window)}</td><td class="num">${formatNumber(numberField(data, 'usage'))}%</td>
<td>${top ? `${escape(top.name)} (${formatNumber(numberField(top, 'usage'))}%)` : ''}</td>
<td class="num">${formatNumber(numberField(data, 'unattributed_usage'))}%</td><td>${detailJson(data)}</td></tr>`;
    });
    sections.push(`<section><h3>Scheduler overrun incidents</h3><p class="muted">Subsystem usage contains the scheduler work shown inside each full record; these are nested costs, not additional tick time.</p>
<div class="scroll"><table><thead><tr><th>scenario</th><th>window</th><th>tick use</th><th>top subsystem</th><th>unattributed</th><th>contributors and pending work</th></tr></thead><tbody>${rows.join('')}</tbody></table></div></section>`);
  }
  return sections;
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
      sections.push(...schedulerSections(iteration));
      const worst: string[] = [];
      for (const scenario of Object.values(iteration.scenarios ?? {})) {
        for (const [key, value] of Object.entries(scenario.details ?? {})) {
          if (!key.endsWith('_outliers') || !Array.isArray(value) || !value.length) continue;
          for (const tick of value as { usage: number; top_subsystem: string; world_time: number; top_systems?: { key: string; ms: number }[] }[]) {
            // The systems inside the MC subsystem (Behaviours) that the tick's time went to, when the world recorded them.
            const systems = (tick.top_systems ?? []).map((s) => `${s.key} ${formatNumber(s.ms)} ms`).join(', ');
            worst.push(`<tr><td>${escape(scenario.id)}</td><td>${escape(key.replace(/_outliers$/, ''))}</td><td class="num">${Math.round(tick.usage)}%</td><td>${escape(tick.top_subsystem)}</td><td>${escape(systems)}</td><td class="num">${escape(tick.world_time)}</td></tr>`);
          }
        }
      }
      if (worst.length) {
        sections.push(`<section><h3>Overrun ticks</h3><div class="scroll"><table><thead><tr><th>scenario</th><th>window</th><th>usage</th><th>top subsystem</th><th>top systems</th><th>world.time</th></tr></thead><tbody>${worst.join('')}</tbody></table></div></section>`);
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
details pre { max-height:400px; overflow:auto; white-space:pre-wrap; overflow-wrap:anywhere; font-size:12px; }
</style></head><body><main>
<h1>DeepQuarry benchmarks</h1>
<p class="muted">Generated ${escape(new Date().toISOString())} from ${benchRuns.length} benchmark run(s) and ${testRuns.length} test run(s) in <code>data/</code>. Regenerate with <code>tools/build/build.sh bench-report</code>.</p>
${sections.join('\n')}
</main></body></html>
`;
  fs.writeFileSync(outFile, html);
  return { runs: benchRuns.length, tests: testRuns.length };
}
