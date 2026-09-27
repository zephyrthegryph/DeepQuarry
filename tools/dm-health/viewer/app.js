(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const databaseName = 'dm-health-reports-v1';
  const PAGE = 50;
  let reports = [];
  let current = null;
  let pages = { findings: 0, procs: 0, files: 0, modules: 0, coupling: 0, globals: 0 };
  let moduleFolder = '';
  const moduleExpanded = new Set(['code', 'code/modules']);
  let fileModules = new Map();
  let sourcePath = '', sourceLines = [], sourceLine = 1;
  const number = n => Number(n || 0).toLocaleString();
  const fmtDate = value => { const d = new Date(value); return Number.isNaN(+d) ? value : d.toLocaleString(); };
  const fingerprint = f => `${f.rule}:${f.path}:${f.message}`;
  const severityRank = { error: 0, warning: 1, info: 2 };
  function findingCategory(rule) {
    if (/null|nullable|nonnull/.test(rule)) return 'Nullability';
    if (/type|argument|assignment/.test(rule)) return 'Type safety';
    if (/global|singleton/.test(rule)) return 'Shared state';
    if (/private|protected|access|readonly/.test(rule)) return 'Access';
    if (/module|coupling/.test(rule)) return 'Modules';
    if (/large|complex|god|nest|deref-heavy/.test(rule)) return 'Complexity';
    return 'Other';
  }
  function procCategory(owner) { return owner.split('/').filter(Boolean)[0] || 'global'; }
  function moduleForPath(path) { return fileModules.get(path) || 'Unassigned'; }
  const child = (tag, text, className) => { const el = document.createElement(tag); el.textContent = text; if (className) el.className = className; return el; };
  function validate(data) {
    if (!data || ![1, 2].includes(data.schema_version) || !Array.isArray(data.findings) || !data.metrics || !Array.isArray(data.metrics.procs) || !Array.isArray(data.metrics.files) || !data.generated_at) throw new Error('This is not a supported DM Health report');
    return data;
  }
  function database() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(databaseName, 1);
      request.onupgradeneeded = () => request.result.createObjectStore('reports', { keyPath: 'id' });
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }
  async function persist(data) {
    try {
      const db = await database();
      await new Promise((resolve, reject) => {
        const tx = db.transaction('reports', 'readwrite');
        tx.objectStore('reports').put({ id: `${data.project || ''}|${data.generated_at}`, data });
        tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
      });
      db.close();
      $('storage-status').textContent = `${reports.length} report${reports.length === 1 ? '' : 's'} saved in this browser`;
    } catch { $('storage-status').textContent = 'Browser storage is unavailable; download reports to keep them'; }
  }
  async function clearStored() {
    const db = await database();
    await new Promise((resolve, reject) => { const tx = db.transaction('reports', 'readwrite'); tx.objectStore('reports').clear(); tx.oncomplete = resolve; tx.onerror = () => reject(tx.error); });
    db.close();
  }
  async function restore() {
    try {
      const db = await database();
      const items = await new Promise((resolve, reject) => { const request = db.transaction('reports').objectStore('reports').getAll(); request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); });
      db.close();
      reports = items.map(item => validate(item.data)).sort((a, b) => new Date(a.generated_at) - new Date(b.generated_at));
      current = reports.at(-1) || null;
      $('storage-status').textContent = `${reports.length} report${reports.length === 1 ? '' : 's'} saved in this browser`;
    } catch { reports = []; $('storage-status').textContent = 'Browser storage is unavailable'; }
    render();
    if (location.hostname === '127.0.0.1' || location.hostname === 'localhost') {
      try {
        const indexResponse = await fetch('/api/index');
        if (!indexResponse.ok) return;
        for (const name of await indexResponse.json()) {
          if (!/^dm-health-[\w.-]+\.json$/.test(name)) continue;
          const response = await fetch(`/api/report/${name}`);
          if (response.ok) addReport(await response.json());
        }
      } catch { /* The standalone viewer still supports file imports. */ }
    }
  }
  function addReport(data) {
    validate(data);
    const id = `${data.project || ''}|${data.generated_at}`;
    reports = reports.filter(r => `${r.project || ''}|${r.generated_at}` !== id);
    reports.push(data);
    reports.sort((a, b) => new Date(a.generated_at) - new Date(b.generated_at));
    current = data;
    void persist(data);
    render();
  }
  function td(row, value, className) { row.appendChild(child('td', String(value ?? ''), className)); }
  function sortedEntries(object) { return Object.entries(object || {}).sort((a, b) => b[1] - a[1]); }
  function score(proc) { return proc.lines + proc.branches * 5 + proc.max_nesting * 8 + proc.global_reads * 4 + proc.global_writes * 7 + proc.distinct_calls * 2; }
  function renderRank(target, rows, maxCount = 6, onClick = null) {
    target.replaceChildren();
    const list = rows.slice(0, maxCount), max = Math.max(1, ...list.map(r => r[1]));
    if (!list.length) { target.appendChild(child('p', 'No data in this report.', 'muted')); return; }
    for (const [label, count] of list) {
      const row = child('div', '', 'rank-row');
      const left = child('div', ''); left.appendChild(child('div', label, 'rank-name'));
      const track = child('div', '', 'bar-track'), bar = child('div', '', 'bar-fill'); bar.style.width = `${Math.max(2, count / max * 100)}%`; track.appendChild(bar); left.appendChild(track);
      row.append(left, child('span', number(count), 'rank-number')); target.appendChild(row);
      if (onClick) { row.classList.add('clickable'); row.tabIndex = 0; row.onclick = () => onClick(label); row.onkeydown = event => { if (event.key === 'Enter') onClick(label); }; }
    }
  }
  function drawTrend() {
    const target = $('trend'); target.replaceChildren();
    if (reports.length < 2) { target.appendChild(child('p', 'Import another report to see how findings change over time.')); return; }
    const ns = 'http://www.w3.org/2000/svg', svg = document.createElementNS(ns, 'svg'); svg.setAttribute('viewBox', '0 0 700 210'); svg.setAttribute('role', 'img'); svg.setAttribute('aria-label', 'Findings over time');
    const margin = { left: 35, right: 16, top: 12, bottom: 28 }, width = 700 - margin.left - margin.right, height = 210 - margin.top - margin.bottom;
    const keys = [['errors', '#ef7f82'], ['warnings', '#f0b75e'], ['info', '#69acdf']];
    const max = Math.max(1, ...reports.flatMap(r => keys.map(([key]) => Number(r.counts?.[key] || 0))));
    for (let tick = 0; tick <= 4; tick++) {
      const y = margin.top + height - height * tick / 4;
      const line = document.createElementNS(ns, 'line'); line.setAttribute('x1', margin.left); line.setAttribute('x2', 700 - margin.right); line.setAttribute('y1', y); line.setAttribute('y2', y); line.setAttribute('class', 'axis'); svg.appendChild(line);
      const label = document.createElementNS(ns, 'text'); label.setAttribute('x', 0); label.setAttribute('y', y + 3); label.textContent = number(Math.round(max * tick / 4)); svg.appendChild(label);
    }
    keys.forEach(([key, color]) => {
      const points = reports.map((r, i) => `${margin.left + i * width / (reports.length - 1)},${margin.top + height - Number(r.counts?.[key] || 0) / max * height}`).join(' ');
      const path = document.createElementNS(ns, 'polyline'); path.setAttribute('points', points); path.setAttribute('stroke', color); svg.appendChild(path);
      reports.forEach((r, i) => { const c = document.createElementNS(ns, 'circle'); c.setAttribute('cx', margin.left + i * width / (reports.length - 1)); c.setAttribute('cy', margin.top + height - Number(r.counts?.[key] || 0) / max * height); c.setAttribute('r', 3.5); c.setAttribute('fill', color); const title = document.createElementNS(ns, 'title'); title.textContent = `${fmtDate(r.generated_at)}: ${number(r.counts?.[key])} ${key}`; c.appendChild(title); svg.appendChild(c); });
    });
    for (const i of [0, reports.length - 1]) { const label = document.createElementNS(ns, 'text'); label.setAttribute('x', margin.left + i * width / (reports.length - 1)); label.setAttribute('y', 205); label.setAttribute('text-anchor', i ? 'end' : 'start'); label.textContent = new Date(reports[i].generated_at).toLocaleDateString(); svg.appendChild(label); }
    target.appendChild(svg);
  }
  function renderOverview() {
    const cards = $('cards'); cards.replaceChildren();
    const total = current.metrics.totals || {}, counts = current.counts || {};
    const cardData = [['Errors', counts.errors, 'error'], ['Warnings', counts.warnings, 'warning'], ['New findings', counts.new, 'new'], ['Code lines', total.code_lines, ''], ['Modules', total.module_roots, ''], ['Source files', total.files, ''], ['Cross-module links', total.cross_module_edges, ''], ['Global fields', total.global_fields_read, '']];
    if (Number.isFinite(current.analysis_phases_ms?.strict_types)) {
      cardData.push(['Type scan time', `${(current.analysis_phases_ms.strict_types / 1000).toFixed(1)}s`, '']);
    }
    if (current.type_coverage?.strict_declarations) {
      const coverage = current.type_coverage;
      cardData.push(['OpenDream export', coverage.frontend_verified ? 'Verified' : 'Unverified', `Schema ${coverage.bridge_schema ?? '?'} · ${coverage.frontend_errors ?? '?'} frontend errors`]);
      cardData.push(['Typed declarations', `${number(coverage.known_declarations)} / ${number(coverage.strict_declarations)}`, '']);
      const typedExpressions = coverage.typed_expressions ?? coverage.checked_expressions ?? 0;
      const expressionTotal = typedExpressions + (coverage.unresolved_expressions || 0);
      cardData.push(['Typed expressions', `${number(typedExpressions)} / ${number(expressionTotal)}`, '']);
      const callTotal = (coverage.resolved_calls || 0) + (coverage.unresolved_calls || 0);
      cardData.push(['Resolved calls', `${number(coverage.resolved_calls || 0)} / ${number(callTotal)}`, '']);
      if (coverage.checked_procs_reused || coverage.checked_procs_recomputed) {
        cardData.push(['Proc checks reused', `${number(coverage.checked_procs_reused || 0)} / ${number((coverage.checked_procs_reused || 0) + (coverage.checked_procs_recomputed || 0))}`, '']);
      }
      const topUnknown = Object.entries(coverage.unresolved_by_kind || {}).sort((a, b) => b[1] - a[1])[0];
      if (topUnknown) cardData.push(['Top unknown expression', topUnknown[0].replace(/^DMAST/, ''), `${number(topUnknown[1])} occurrences`]);
      const topIdentifier = Object.entries(coverage.unresolved_identifiers || {}).sort((a, b) => b[1] - a[1])[0];
      if (topIdentifier) cardData.push(['Top unknown identifier', topIdentifier[0], `${number(topIdentifier[1])} occurrences`]);
      cardData.push(['Unresolved type flows', coverage.unresolved_assignments, 'warning']);
      if (coverage.unresolved_source_types !== undefined) {
        cardData.push(['Need destination type', coverage.unresolved_destination_types || 0, 'warning']);
        cardData.push(['Need source proof', coverage.unresolved_source_types || 0, 'warning']);
        cardData.push(['Need both types', coverage.unresolved_both_types || 0, 'warning']);
      }
      cardData.push(['Unverified control paths', coverage.unverified_control_flow || 0, 'warning']);
      cardData.push(['Dynamic calls', coverage.dynamic_operations, '']);
    }
    for (const [name, value, type] of cardData) { const card = child('article', '', `card ${type}`); card.append(child('div', name, 'label'), child('div', number(value), 'number')); cards.appendChild(card); }
    const rules = {}; for (const finding of current.findings) rules[finding.rule] = (rules[finding.rule] || 0) + 1;
    renderRank($('top-rules'), sortedEntries(rules));
    renderRank($('unknown-causes'), sortedEntries(current.type_coverage?.unresolved_causes || {}));
    renderRank($('hot-procs'), [...current.metrics.procs].sort((a, b) => score(b) - score(a)).slice(0, 6).map(p => [`${p.owner}/${p.name}`, score(p)]));
    const reads = current.metrics.global_readers || {}, writes = current.metrics.global_writers || {};
    renderRank($('hot-globals'), [...new Set([...Object.keys(reads), ...Object.keys(writes)])].map(g => [`GLOB.${g}`, (reads[g] || 0) + (writes[g] || 0)]).sort((a, b) => b[1] - a[1]));
    renderRank($('hot-modules'), [...(current.metrics.modules || [])].filter(m => m.boundary && m.name !== 'code' && m.name !== 'code/modules').sort((a, b) => b.code_lines - a.code_lines).slice(0, 6).map(m => [m.name, m.code_lines]), 6, name => openModule(name));
    const priority = new Map();
    for (const f of current.findings) { if (!f.path.endsWith('.dm')) continue; const item = priority.get(f.path) || { errors: 0, warnings: 0, info: new Set() }; if (f.severity === 'error') item.errors++; else if (f.severity === 'warning') item.warnings++; else item.info.add(f.rule); priority.set(f.path, item); }
    renderRank($('priority-files'), [...priority].map(([path, item]) => [path, item.errors * 10 + item.warnings * 3 + Math.min(item.info.size, 5)]).sort((a, b) => b[1] - a[1]), 6, path => void openSource(path, 1));
    renderRank($('undocumented-modules'), (current.metrics.modules || []).filter(m => !m.documented && m.parent && m.files >= 10).sort((a, b) => b.code_lines - a.code_lines).slice(0, 6).map(m => [m.name, m.code_lines]), 6, name => openModule(name));
    drawTrend();
    drawLocTrend();
  }
  function renderRootCauses() {
    const body = $('root-body'), summary = $('root-summary');
    body.replaceChildren();
    const report = current.root_causes;
    if (!report) { summary.textContent = 'This report predates root-cause analysis.'; return; }
    const total = report.traced + report.untraced;
    const expressionTotal = Number(report.unresolved_expressions || 0);
    const rootPercent = expressionTotal ? (Number(report.rooted_expressions || 0) / expressionTotal * 100).toFixed(1) : '0.0';
    summary.textContent = `${number(report.rooted_expressions)} of ${number(expressionTotal)} unresolved expressions have a source-linked root (${rootPercent}%); ${number(report.fallback_expressions)} use a fallback. ${number(report.traced)} of ${number(total)} downstream diagnostics link to a declaration (${total ? (report.traced / total * 100).toFixed(1) : '0.0'}%).`;
    const expressionBody = $('expression-root-body'); expressionBody.replaceChildren();
    for (const root of (report.expression_roots || []).slice(0, 500)) {
      const row = child('tr'); td(row, root.count); td(row, root.category); td(row, root.symbol, 'path');
      const hasLocation = root.path && root.line;
      const sourceKind = root.category === 'Unknown side effect' ? 'invalidating effect' : root.category === 'Unverified value write' ? 'value write' : root.source_linked ? 'declaration' : 'expression';
      const location = child('td', hasLocation ? `${root.path}:${root.line} · ${sourceKind}` : 'No source location', hasLocation ? 'path clickable' : 'muted');
      if (hasLocation) { location.tabIndex = 0; location.onclick = () => void openSource(root.path, root.line); location.onkeydown = event => { if (event.key === 'Enter') location.click(); }; }
      row.appendChild(location); expressionBody.appendChild(row);
    }
    renderRank($('root-expressions'), (report.expression_causes || []).map(item => [`${item.upstream} · ${item.cause}`, item.count]), 12);
    renderRank($('root-untraced'), sortedEntries(report.untraced_by_rule || {}), 12);
    for (const cause of report.groups.slice(0, 500)) {
      const row = child('tr');
      td(row, cause.dependent_findings);
      td(row, cause.category);
      td(row, cause.symbol, 'path');
      const origin = child('td', `${cause.path}:${cause.line}`, 'path clickable');
      origin.tabIndex = 0;
      origin.onclick = () => void openSource(cause.path, cause.line);
      origin.onkeydown = event => { if (event.key === 'Enter') origin.click(); };
      row.appendChild(origin);
      const example = cause.examples?.[0];
      if (example) {
        const link = child('td', `${example.path}:${example.line} · ${example.rule}`, 'path clickable');
        link.tabIndex = 0;
        link.onclick = () => void openSource(example.path, example.line);
        link.onkeydown = event => { if (event.key === 'Enter') link.click(); };
        row.appendChild(link);
      } else td(row, '—');
      body.appendChild(row);
    }
  }
  function drawLocTrend() {
    const target = $('loc-trend'); target.replaceChildren();
    const snapshots = reports.filter(r => Number.isFinite(r.metrics?.totals?.code_lines));
    if (snapshots.length < 2) { target.textContent = 'Import another report with LOC metrics to see the trend.'; return; }
    const ns = 'http://www.w3.org/2000/svg', svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 600 220'); svg.setAttribute('role', 'img'); svg.setAttribute('aria-label', 'Code lines over time');
    const values = snapshots.map(r => r.metrics.totals.code_lines), min = Math.min(...values), max = Math.max(...values), span = Math.max(max - min, 1);
    const points = values.map((v, i) => `${38 + i * 524 / (values.length - 1)},${183 - (v - min) * 140 / span}`).join(' ');
    const line = document.createElementNS(ns, 'polyline'); line.setAttribute('points', points); line.setAttribute('stroke', '#65ddbd'); svg.appendChild(line);
    snapshots.forEach((r, i) => { const c = document.createElementNS(ns, 'circle'); c.setAttribute('cx', 38 + i * 524 / (snapshots.length - 1)); c.setAttribute('cy', 183 - (values[i] - min) * 140 / span); c.setAttribute('r', '4'); c.setAttribute('fill', '#65ddbd'); const title = document.createElementNS(ns, 'title'); title.textContent = `${fmtDate(r.generated_at)}: ${number(values[i])} code lines`; c.appendChild(title); svg.appendChild(c); });
    for (const [value, y] of [[max, 39], [min, 188]]) { const label = document.createElementNS(ns, 'text'); label.setAttribute('x', '35'); label.setAttribute('y', String(y)); label.textContent = number(value); svg.appendChild(label); }
    target.appendChild(svg);
  }
  function paginate(target, pager, rows, pageKey, renderRow) {
    target.replaceChildren(); pager.replaceChildren();
    const count = Math.max(1, Math.ceil(rows.length / PAGE)); pages[pageKey] = Math.min(pages[pageKey], count - 1);
    rows.slice(pages[pageKey] * PAGE, (pages[pageKey] + 1) * PAGE).forEach(item => { const row = document.createElement('tr'); renderRow(row, item); target.appendChild(row); });
    if (!rows.length) { const row = document.createElement('tr'); const cell = child('td', 'No matching items.'); cell.colSpan = target.closest('table').querySelectorAll('th').length; row.appendChild(cell); target.appendChild(row); }
    const prev = child('button', 'Previous'), next = child('button', 'Next'); prev.disabled = pages[pageKey] === 0; next.disabled = pages[pageKey] >= count - 1;
    prev.onclick = () => { pages[pageKey]--; renderTables(); }; next.onclick = () => { pages[pageKey]++; renderTables(); };
    pager.append(prev, child('span', `${number(rows.length)} items · page ${pages[pageKey] + 1} of ${count}`), next);
  }
  function renderFindings() {
    const query = $('finding-search').value.toLowerCase(), severity = $('severity-filter').value, rule = $('rule-filter').value, newOnly = $('new-only').checked;
    const module = $('finding-module').value, category = $('finding-category').value, sort = $('finding-sort').value;
    const newSet = new Set(current.new_fingerprints || []);
    const rows = current.findings.filter(f => (!severity || f.severity === severity) && (!rule || f.rule === rule) && (!module || moduleForPath(f.path) === module) && (!category || findingCategory(f.rule) === category) && (!newOnly || newSet.has(fingerprint(f))) && (!query || `${f.path} ${f.rule} ${f.message}`.toLowerCase().includes(query)));
    rows.sort((a, b) => (sort === 'module' ? moduleForPath(a.path).localeCompare(moduleForPath(b.path)) : sort === 'category' ? findingCategory(a.rule).localeCompare(findingCategory(b.rule)) : sort === 'path' ? a.path.localeCompare(b.path) : severityRank[a.severity] - severityRank[b.severity]) || a.path.localeCompare(b.path) || a.line - b.line);
    $('finding-count').textContent = `(${number(rows.length)})`;
    paginate($('findings-body'), $('finding-page'), rows, 'findings', (row, f) => {
      const cell = document.createElement('td'); cell.appendChild(child('span', f.severity, `badge ${f.severity}`)); if (newSet.has(fingerprint(f))) cell.appendChild(child('span', 'NEW', 'flag')); row.appendChild(cell);
      td(row, findingCategory(f.rule)); td(row, f.rule); td(row, moduleForPath(f.path), 'path'); td(row, `${f.path}:${f.line}`, 'path'); td(row, f.message, 'message');
      if (f.path.endsWith('.dm')) { row.classList.add('clickable'); row.onclick = () => void openSource(f.path, f.line); }
    });
  }
  function renderProcs() {
    const query = $('proc-search').value.toLowerCase(), sort = $('proc-sort').value, module = $('proc-module').value, category = $('proc-category').value;
    const rows = current.metrics.procs.filter(p => `${p.owner}/${p.name} ${p.path}`.toLowerCase().includes(query) && (!module || moduleForPath(p.path) === module) && (!category || procCategory(p.owner) === category)).sort((a, b) => (sort === 'module' ? moduleForPath(a.path).localeCompare(moduleForPath(b.path)) : sort === 'category' ? procCategory(a.owner).localeCompare(procCategory(b.owner)) : sort === 'owner' ? a.owner.localeCompare(b.owner) : sort === 'name' ? a.name.localeCompare(b.name) : sort === 'score' ? score(b) - score(a) : sort === 'globals' ? (b.global_reads + b.global_writes) - (a.global_reads + a.global_writes) : b[sort] - a[sort]) || a.path.localeCompare(b.path));
    $('proc-count').textContent = `(${number(rows.length)})`;
    paginate($('procs-body'), $('proc-page'), rows, 'procs', (row, p) => { td(row, `${p.owner}/${p.name}`); td(row, procCategory(p.owner)); td(row, moduleForPath(p.path), 'path'); td(row, `${p.path}:${p.line}`, 'path'); for (const n of [p.lines, p.branches, p.max_nesting, p.calls, p.global_reads + p.global_writes]) td(row, number(n), 'number'); row.classList.add('clickable'); row.onclick = () => void openSource(p.path, p.line); });
  }
  function selectTab(name) {
    document.querySelectorAll('.tab').forEach(tab => tab.classList.toggle('active', tab.dataset.tab === name));
    document.querySelectorAll('.view').forEach(view => view.classList.toggle('active', view.id === name));
    document.body.classList.toggle('source-active', name === 'modules');
  }
  function openModule(name) {
    moduleFolder = name; sourcePath = ''; sourceLines = [];
    const parts = name.split('/');
    for (let i = 1; i <= parts.length; i++) moduleExpanded.add(parts.slice(0, i).join('/'));
    selectTab('modules'); renderModules();
    $('module-tree').querySelector('.selected')?.scrollIntoView({ block: 'nearest' });
  }
  async function renderModuleReadme() {
    const panel = $('module-readme'), module = (current.metrics.modules || []).find(m => m.name === moduleFolder);
    panel.hidden = !module?.documented;
    if (!module?.documented) return;
    $('module-readme-text').textContent = 'Loading documentation…';
    try { const response = await fetch(`/api/readme/${encodeURIComponent(module.name)}`); if (!response.ok) throw new Error('unavailable'); const content = await response.text(); if (moduleFolder === module.name) $('module-readme-text').textContent = content; }
    catch { if (moduleFolder === module.name) $('module-readme-text').textContent = 'README available in the repository; open the local viewer to read it here.'; }
  }
  function renderModules() {
    const query = $('module-search').value.trim().toLowerCase(), sort = $('module-sort').value;
    const modules = current.metrics.modules || [], allFiles = current.metrics.files || [];
    const byParent = new Map(), byName = new Map(modules.map(m => [m.name, m]));
    if (!byName.has(moduleFolder)) moduleFolder = byName.has('code') ? 'code' : modules[0]?.name || '';
    for (const m of modules) { const siblings = byParent.get(m.parent) || []; siblings.push(m); byParent.set(m.parent, siblings); }
    const byFolder = new Map(); for (const file of allFiles) { const files = byFolder.get(file.module) || []; files.push(file); byFolder.set(file.module, files); }
    const folderGroup = m => m.documented ? 0 : byParent.has(m.name) ? 1 : 2;
    for (const siblings of byParent.values()) siblings.sort((a, b) => folderGroup(a) - folderGroup(b) || (sort === 'name' ? a.name.localeCompare(b.name) : (b[sort] || 0) - (a[sort] || 0) || a.name.localeCompare(b.name)));
    for (const files of byFolder.values()) files.sort((a, b) => sort === 'name' ? a.path.localeCompare(b.path) : (b[sort] || 0) - (a[sort] || 0) || a.path.localeCompare(b.path));
    const visible = new Set(), matchingFiles = new Set();
    function reveal(name) { let ancestor = byName.get(name); while (ancestor) { visible.add(ancestor.name); ancestor = byName.get(ancestor.parent); } }
    if (query) {
      for (const m of modules.filter(m => m.name.toLowerCase().includes(query))) reveal(m.name);
      for (const file of allFiles.filter(f => f.path.toLowerCase().includes(query))) { matchingFiles.add(file.path); reveal(file.module); }
    }
    const tree = $('module-tree'), scroll = tree.scrollTop; tree.replaceChildren();
    $('module-count').textContent = `${number(modules.filter(m => m.documented).length)} modules · ${number(allFiles.length)} files`;
    function branch(parent, depth) {
      for (const m of byParent.get(parent) || []) {
        if (query && !visible.has(m.name)) continue;
        const children = byParent.has(m.name) || (byFolder.get(m.name)?.length || 0) > 0;
        const expanded = query ? true : moduleExpanded.has(m.name);
        const row = child('div', '', `module-node ${m.name === moduleFolder ? 'selected' : ''}`);
        row.setAttribute('role', 'treeitem'); row.setAttribute('aria-level', String(depth + 1)); row.setAttribute('aria-selected', String(m.name === moduleFolder));
        row.tabIndex = 0;
        row.onclick = () => openModule(m.name);
        row.onkeydown = event => { if (event.target === row && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); openModule(m.name); } };
        row.style.paddingLeft = `${8 + depth * 16}px`;
        const toggle = child('button', children ? expanded ? '▾' : '▸' : '·', 'module-toggle'); toggle.disabled = !children;
        toggle.setAttribute('aria-label', children ? `${expanded ? 'Collapse' : 'Expand'} ${m.name}` : `Empty folder ${m.name}`);
        if (children) toggle.setAttribute('aria-expanded', String(expanded));
        toggle.onclick = event => { event.stopPropagation(); if (moduleExpanded.has(m.name)) moduleExpanded.delete(m.name); else moduleExpanded.add(m.name); renderModules(); };
        const label = child('span', m.name.split('/').at(-1), 'module-label'); label.title = m.name;
        row.append(toggle, label);
        if (m.documented) row.appendChild(child('span', 'M', 'module-marker'));
        row.appendChild(child('span', number(m.code_lines), 'module-size'));
        tree.appendChild(row);
        if (byParent.has(m.name) && expanded) branch(m.name, depth + 1);
        if (expanded) for (const file of byFolder.get(m.name) || []) {
          if (query && !matchingFiles.has(file.path) && !m.name.toLowerCase().includes(query)) continue;
          const item = child('div', '', `module-node module-file-node ${file.path === sourcePath ? 'selected' : ''}`);
          item.setAttribute('role', 'treeitem'); item.setAttribute('aria-level', String(depth + 2)); item.setAttribute('aria-selected', String(file.path === sourcePath));
          item.tabIndex = 0;
          item.onclick = () => void openSource(file.path, 1);
          item.onkeydown = event => { if (event.target === item && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); void openSource(file.path, 1); } };
          item.style.paddingLeft = `${28 + depth * 16}px`;
          const button = child('span', file.path.split('/').at(-1), 'module-label'); button.title = file.path;
          item.append(button, child('span', number(file.findings), 'module-size')); tree.appendChild(item);
        }
      }
    }
    branch('', 0); tree.scrollTop = scroll;
    if (!tree.childElementCount) tree.appendChild(child('p', 'No matching folders.', 'muted'));
    const selected = byName.get(moduleFolder);
    $('module-folder-detail').hidden = Boolean(sourcePath);
    $('source-viewer').hidden = !sourcePath;
    $('module-kind').textContent = selected ? selected.documented ? 'README MODULE' : 'SOURCE FOLDER' : 'SELECT A FOLDER';
    $('module-title').textContent = selected ? selected.name.split('/').at(-1) : 'Explore the source tree';
    $('module-path').textContent = selected ? selected.name : 'Select any folder to see its size, findings, source files, and README.';
    const stats = $('module-stats'); stats.replaceChildren();
    if (selected) for (const [label, value] of [['Files', selected.files], ['Code lines', selected.code_lines], ['Procedures', selected.procs], ['Findings', selected.findings], ['Findings / KLOC', selected.code_lines ? (selected.findings * 1000 / selected.code_lines).toFixed(1) : '—']]) { const card = child('div', '', 'module-stat'); card.append(child('span', label), child('strong', typeof value === 'number' ? number(value) : value)); stats.appendChild(card); }
    const files = selected ? current.metrics.files.filter(f => f.module === selected.name).sort((a, b) => b.findings - a.findings || a.path.localeCompare(b.path)) : [];
    $('module-file-count').textContent = selected ? `${number(files.length)} direct files` : '';
    const fileList = $('module-files'); fileList.replaceChildren();
    for (const file of files.slice(0, 100)) { const button = child('button', '', 'module-file'); button.append(child('span', file.path.split('/').at(-1)), child('small', `${number(file.code_lines)} LOC · ${number(file.findings)} finding${file.findings === 1 ? '' : 's'}`)); button.title = file.path; button.onclick = () => void openSource(file.path, 1); fileList.appendChild(button); }
    if (files.length > 100) fileList.appendChild(child('p', 'Showing 100 direct files. Search the tree for the full list.', 'muted'));
    if (selected && !files.length) fileList.appendChild(child('p', 'No DM files directly in this folder. Expand its children in the tree.', 'muted'));
    if (!sourcePath) void renderModuleReadme();
  }
  function renderCoupling() {
    const edges = current.metrics.coupling || [], query = $('coupling-search').value.toLowerCase(), kind = $('coupling-kind').value;
    const rows = edges.filter(e => (!kind || e.kind === kind) && (!query || `${e.from} ${e.to}`.toLowerCase().includes(query))).sort((a, b) => b.references - a.references);
    $('coupling-count').textContent = `(${number(rows.length)})`;
    paginate($('coupling-body'), $('coupling-page'), rows, 'coupling', (row, e) => { td(row, e.from, 'path'); td(row, e.to, 'path'); td(row, e.kind); td(row, number(e.references), 'number'); row.classList.add('clickable'); row.onclick = () => openModule(e.from); });
    const pairs = new Map(); for (const e of edges) { const key = `${e.from} → ${e.to}`; pairs.set(key, (pairs.get(key) || 0) + e.references); }
    renderRank($('coupling-rank'), [...pairs.entries()].sort((a, b) => b[1] - a[1]), 8, label => openModule(label.split(' → ')[0]));
    const summary = $('coupling-summary'); summary.replaceChildren();
    for (const k of ['type', 'global read', 'global write']) { const count = edges.filter(e => e.kind === k).reduce((n, e) => n + e.references, 0); summary.appendChild(child('div', `${number(count)} ${k} references`)); }
  }
  function renderSource() {
    const title = $('source-title'), status = $('source-status'), code = $('source-code'), list = $('source-findings'); code.replaceChildren(); list.replaceChildren();
    title.textContent = sourcePath || 'Select a source file';
    const file = current.metrics.files.find(f => f.path === sourcePath), stats = $('source-file-stats'); stats.replaceChildren();
    if (file) for (const [label, value] of [['Module', file.module_root], ['Lines', file.lines], ['Code', file.code_lines], ['Comments', file.comment_lines], ['Procedures', file.procs], ['Findings', file.findings]]) { const card = child('div', '', 'source-file-stat'); card.append(child('span', label), child('strong', typeof value === 'number' ? number(value) : value)); stats.appendChild(card); }
    if (!sourcePath || !sourceLines.length) { status.textContent = sourcePath ? 'Source unavailable. Run the local DM Health viewer from the repository root.' : 'Select a file or a finding to view source.'; $('source-prev').disabled = true; $('source-next').disabled = true; return; }
    const findings = current.findings.filter(f => f.path === sourcePath).sort((a, b) => a.line - b.line);
    $('source-prev').disabled = !findings.some(f => f.line < sourceLine);
    $('source-next').disabled = !findings.some(f => f.line > sourceLine);
    $('source-line-jump').max = String(sourceLines.length);
    $('source-line-jump').value = String(sourceLine);
    const start = Math.max(1, sourceLine - 250), end = Math.min(sourceLines.length, sourceLine + 250);
    status.textContent = `${number(sourceLines.length)} lines · ${number(findings.length)} findings · viewing ${number(start)}–${number(end)}`;
    const byLine = new Map(); for (const finding of findings) { if (!byLine.has(finding.line)) byLine.set(finding.line, []); byLine.get(finding.line).push(finding); }
    const groups = new Map(); for (const finding of findings) { const group = groups.get(finding.rule) || { count: 0, first: finding }; group.count++; groups.set(finding.rule, group); }
    for (const [rule, group] of [...groups].sort((a, b) => b[1].count - a[1].count)) { const button = child('button', `${rule} · ${number(group.count)}`, `source-finding ${group.first.severity}`); button.title = group.first.message; button.onclick = () => { sourceLine = group.first.line; renderSource(); }; list.appendChild(button); }
    for (let line = start; line <= end; line++) {
      const row = child('div', '', `source-line ${byLine.has(line) ? 'has-finding' : ''} ${line === sourceLine ? 'focused' : ''}`);
      row.append(child('span', String(line), 'source-number'), child('span', sourceLines[line - 1] || ' ', 'source-text'));
      code.appendChild(row);
      const notes = new Map();
      for (const finding of byLine.get(line) || []) { const key = `${finding.severity}:${finding.rule}:${finding.message}`; const item = notes.get(key) || { finding, count: 0 }; item.count++; notes.set(key, item); }
      for (const { finding, count } of notes.values()) { const note = child('div', '', `source-note ${finding.severity}`); note.append(child('strong', `${finding.severity.toUpperCase()} · ${finding.rule}`), child('span', `${finding.message}${count > 1 ? ` (${count} occurrences on this line)` : ''}`)); code.appendChild(note); }
    }
    const focus = code.querySelector('.focused'); if (focus) focus.scrollIntoView({ block: 'center' });
  }
  async function openSource(path, line) {
    sourcePath = path; sourceLine = Math.max(1, Number(line) || 1); sourceLines = [];
    moduleFolder = current.metrics.files.find(f => f.path === path)?.module || path.slice(0, path.lastIndexOf('/'));
    const parts = moduleFolder.split('/'); for (let i = 1; i <= parts.length; i++) moduleExpanded.add(parts.slice(0, i).join('/'));
    selectTab('modules'); renderModules(); renderSource();
    $('module-tree').querySelector('.selected')?.scrollIntoView({ block: 'nearest' });
    try {
      const response = await fetch(`/api/source/${encodeURIComponent(path)}`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const text = await response.text();
      if (sourcePath !== path) return;
      sourceLines = text.split(/\r?\n/); renderSource();
    } catch { if (sourcePath === path) renderSource(); }
  }
  function renderGlobals() {
    const query = $('global-search').value.toLowerCase(), reads = current.metrics.global_readers || {}, writes = current.metrics.global_writers || {};
    const rows = [...new Set([...Object.keys(reads), ...Object.keys(writes)])].filter(g => g.toLowerCase().includes(query)).sort((a, b) => ((writes[b] || 0) * 2 + (reads[b] || 0)) - ((writes[a] || 0) * 2 + (reads[a] || 0)));
    $('global-count').textContent = `(${number(rows.length)})`;
    paginate($('globals-body'), $('global-page'), rows, 'globals', (row, g) => { td(row, `GLOB.${g}`, 'path'); td(row, number(reads[g]), 'number'); td(row, number(writes[g]), 'number'); });
  }
  function renderCi() {
    const checks = current.ci_checks || [];
    $('ci-empty').textContent = checks.length ? '' : 'CI results appear in reports produced by the full lint suite.';
    $('ci-body').replaceChildren();
    checks.forEach(c => { const row = document.createElement('tr'); td(row, c.name); const status = document.createElement('td'); status.appendChild(child('span', c.passed ? 'Passed' : 'Failed', `badge ${c.passed ? 'info' : 'error'}`)); row.appendChild(status); td(row, c.exit_code ?? '—', 'number'); td(row, `${number((c.duration_ms || 0) / 1000)} s`, 'number'); $('ci-body').appendChild(row); });
  }
  function renderTables() { if (!current) return; renderFindings(); renderProcs(); renderModules(); renderCoupling(); renderGlobals(); renderCi(); }
  function render() {
    const hasReport = Boolean(current); $('empty').hidden = hasReport; $('dashboard').hidden = !hasReport; $('save-report').disabled = !hasReport;
    const select = $('report-select'); select.replaceChildren();
    reports.forEach((r, i) => { const option = child('option', `${fmtDate(r.generated_at)} · ${r.project || 'DM project'}`); option.value = String(i); option.selected = r === current; select.appendChild(option); });
    $('report-date').textContent = current
      ? `Generated ${fmtDate(current.generated_at)}${Number.isFinite(current.rust_analysis_ms) ? ` · Rust ${current.analysis_reused ? 'reused' : 'full'} ${(current.rust_analysis_ms / 1000).toFixed(1)}s` : ''}`
      : 'No report loaded';
    if (!hasReport) return;
    fileModules = new Map(current.metrics.files.map(f => [f.path, f.module_root || 'Unassigned']));
    function setOptions(id, placeholder, values) { const select = $(id), chosen = select.value; select.replaceChildren(); const first = child('option', placeholder); first.value = ''; select.appendChild(first); for (const value of [...new Set(values)].sort()) { const option = child('option', value); option.value = value; select.appendChild(option); } select.value = chosen; }
    const moduleNames = current.metrics.modules.filter(m => m.documented).map(m => m.name);
    setOptions('finding-module', 'All modules', moduleNames);
    setOptions('proc-module', 'All modules', moduleNames);
    setOptions('finding-category', 'All categories', current.findings.map(f => findingCategory(f.rule)));
    setOptions('proc-category', 'All types', current.metrics.procs.map(p => procCategory(p.owner)));
    const ruleFilter = $('rule-filter'), selected = ruleFilter.value; ruleFilter.replaceChildren(); const all = child('option', 'All rules'); all.value = ''; ruleFilter.appendChild(all);
    [...new Set(current.findings.map(f => f.rule))].sort().forEach(rule => { const option = child('option', rule); option.value = rule; ruleFilter.appendChild(option); }); ruleFilter.value = selected;
    renderOverview(); renderRootCauses(); renderTables(); if (sourcePath) renderSource();
  }
  $('report-files').addEventListener('change', async event => {
    for (const file of event.target.files) { try { addReport(JSON.parse(await file.text())); } catch (error) { alert(`${file.name}: ${error.message}`); } }
    event.target.value = '';
  });
  $('report-select').addEventListener('change', event => { current = reports[Number(event.target.value)]; pages = { findings: 0, procs: 0, files: 0, modules: 0, coupling: 0, globals: 0 }; render(); });
  $('save-report').addEventListener('click', () => { if (!current) return; const blob = new Blob([JSON.stringify(current, null, 2)], { type: 'application/json' }); const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = `dm-health-${current.generated_at.replace(/[:.]/g, '-')}.json`; link.click(); setTimeout(() => URL.revokeObjectURL(link.href), 1000); });
  $('clear-reports').addEventListener('click', () => { if (!reports.length || confirm('Remove saved reports from this browser? Download any reports you want to keep first.')) { reports = []; current = null; void clearStored(); render(); } });
  document.querySelectorAll('.tab').forEach(button => button.addEventListener('click', () => selectTab(button.dataset.tab)));
  $('source-line-jump').addEventListener('change', () => { if (!sourceLines.length) return; sourceLine = Math.min(sourceLines.length, Math.max(1, Number($('source-line-jump').value) || 1)); renderSource(); });
  $('source-toggle-browser').addEventListener('click', () => { const hidden = document.body.classList.toggle('explorer-tree-collapsed'); $('source-toggle-browser').textContent = hidden ? 'Show tree' : 'Hide tree'; $('source-toggle-browser').setAttribute('aria-pressed', String(hidden)); });
  $('source-prev').addEventListener('click', () => { const lines = current.findings.filter(f => f.path === sourcePath && f.line < sourceLine).map(f => f.line); if (lines.length) { sourceLine = Math.max(...lines); renderSource(); } });
  $('source-next').addEventListener('click', () => { const lines = current.findings.filter(f => f.path === sourcePath && f.line > sourceLine).map(f => f.line); if (lines.length) { sourceLine = Math.min(...lines); renderSource(); } });
  for (const id of ['finding-search', 'finding-module', 'finding-category', 'finding-sort', 'severity-filter', 'rule-filter', 'new-only', 'proc-search', 'proc-module', 'proc-category', 'proc-sort', 'module-search', 'module-sort', 'coupling-search', 'coupling-kind', 'global-search']) $(id).addEventListener('input', () => { pages = { findings: 0, procs: 0, coupling: 0, globals: 0 }; renderTables(); });
  void restore();
})();
