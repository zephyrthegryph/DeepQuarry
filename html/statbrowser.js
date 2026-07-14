// Polyfills and compatibility ------------------------------------------------
const decoder = decodeURIComponent;
if (!Array.prototype.includes) {
  Array.prototype.includes = function (thing) {
    for (let i = 0; i < this.length; i++) {
      if (this[i] === thing) return true;
    }
    return false;
  };
}
if (!String.prototype.trim) {
  String.prototype.trim = function () {
    return this.replace(/^[\s\uFEFF\xA0]+|[\s\uFEFF\xA0]+$/g, '');
  };
}

// Status panel implementation ------------------------------------------------
let status_tab_parts = ['Loading...'];
let current_tab = null;
let mc_tab_parts = [['Loading...', '']];
let mc_metrics = null;
let mc_view = 'overview';
let mc_selected_outlier = null;
let mc_details_open = false;
let href_token = null;
let spells = [];
let spell_tabs = [];
let verb_tabs = [];
let verbs = [['', '']]; // list with a list inside
let examine = [];
let tickets = [];
const misc = new Map();
let sdql2 = [];
const permanent_tabs = []; // tabs that won't be cleared by wipes
let turfcontents = [];
let turfname = '';
const imageRetryDelay = 500;
const imageRetryLimit = 50;
const menu = document.getElementById('menu');
const statcontentdiv = document.getElementById('statcontent');
const storedimages = [];
let split_admin_tabs = false;

// Any BYOND commands that could result in the client's focus changing go through this
// to ensure that when we relinquish our focus, we don't do it after the result of
// a command has already taken focus for itself.
function run_after_focus(callback) {
  setTimeout(callback, 0);
}

function createStatusTab(name) {
  if (name.indexOf('.') !== -1) {
    const splitName = name.split('.');
    if (split_admin_tabs && splitName[0] === 'Admin') name = splitName[1];
    else name = splitName[0];
  }
  if (document.getElementById(name) || name.trim() === '') {
    return;
  }
  if (!verb_tabs.includes(name) && !permanent_tabs.includes(name)) {
    return;
  }
  const button = document.createElement('DIV');
  button.onclick = function () {
    tab_change(name);
    this.blur();
    statcontentdiv.focus();
  };
  button.id = name;
  button.textContent = name;
  button.className = 'button';
  //ORDERING ALPHABETICALLY
  button.style.order = name.charCodeAt(0);
  if (name === 'Status' || name === 'MC') {
    button.style.order = name === 'Status' ? 1 : 2;
  }
  if (name === 'Tickets') {
    button.style.order = 3;
  }
  //END ORDERING
  menu.appendChild(button);
  SendTabToByond(name);
}

function removeStatusTab(name) {
  if (!document.getElementById(name) || permanent_tabs.includes(name)) {
    return;
  }
  for (let i = verb_tabs.length - 1; i >= 0; --i) {
    if (verb_tabs[i] === name) {
      verb_tabs.splice(i, 1);
    }
  }
  if (current_tab === name) {
    tab_change('Status');
  }
  menu.removeChild(document.getElementById(name));
  TakeTabFromByond(name);
}

function sortVerbs() {
  verbs.sort((a, b) => {
    const selector = a[0] === b[0] ? 1 : 0;
    if (a[selector].toUpperCase() < b[selector].toUpperCase()) {
      return 1;
    } else if (a[selector].toUpperCase() > b[selector].toUpperCase()) {
      return -1;
    }
    return 0;
  });
}

function addPermanentTab(name) {
  if (!permanent_tabs.includes(name)) {
    permanent_tabs.push(name);
  }
  createStatusTab(name);
}

function removePermanentTab(name) {
  for (let i = permanent_tabs.length - 1; i >= 0; --i) {
    if (permanent_tabs[i] === name) {
      permanent_tabs.splice(i, 1);
    }
  }
  removeStatusTab(name);
}

function checkStatusTab() {
  for (let i = 0; i < menu.children.length; i++) {
    if (
      !verb_tabs.includes(menu.children[i].id) &&
      !permanent_tabs.includes(menu.children[i].id)
    ) {
      menu.removeChild(menu.children[i]);
    }
  }
}

function remove_verb(v) {
  const verb_to_remove = v; // to_remove = [verb:category, verb:name]
  for (let i = verbs.length - 1; i >= 0; i--) {
    const part_to_remove = verbs[i];
    if (part_to_remove[1] === verb_to_remove[1]) {
      verbs.splice(i, 1);
    }
  }
}

function check_verbs() {
  for (let v = verb_tabs.length - 1; v >= 0; v--) {
    verbs_cat_check(verb_tabs[v]);
  }
}

function verbs_cat_check(cat) {
  let tabCat = cat;
  if (cat.indexOf('.') !== -1) {
    const splitName = cat.split('.');
    if (split_admin_tabs && splitName[0] === 'Admin') tabCat = splitName[1];
    else tabCat = splitName[0];
  }
  let verbs_in_cat = 0;
  let verbcat = '';
  if (!verb_tabs.includes(tabCat)) {
    removeStatusTab(tabCat);
    return;
  }
  for (let v = 0; v < verbs.length; v++) {
    const part = verbs[v];
    verbcat = part[0];
    if (verbcat.indexOf('.') !== -1) {
      const splitName = verbcat.split('.');
      if (split_admin_tabs && splitName[0] === 'Admin') verbcat = splitName[1];
      else verbcat = splitName[0];
    }
    if (verbcat !== tabCat || verbcat.trim() === '') {
    } else {
      verbs_in_cat = 1;
      break; // we only need one
    }
  }
  if (verbs_in_cat !== 1) {
    removeStatusTab(tabCat);
    if (current_tab === tabCat) tab_change('Status');
  }
}

function findVerbindex(name, verblist) {
  for (let i = 0; i < verblist.length; i++) {
    const part = verblist[i];
    if (part[1] === name) return i;
  }
}
function wipe_verbs() {
  verbs = [['', '']];
  verb_tabs = [];
  checkStatusTab(); // remove all empty verb tabs
}

function update_verbs() {
  wipe_verbs();
  Byond.sendMessage('Update-Verbs');
}

function SendTabsToByond() {
  let tabstosend = [];
  tabstosend = tabstosend.concat(permanent_tabs, verb_tabs);
  for (let i = 0; i < tabstosend.length; i++) {
    SendTabToByond(tabstosend[i]);
  }
}

function SendTabToByond(tab) {
  Byond.sendMessage('Send-Tabs', { tab: tab });
}

//Byond can't have this tab anymore since we're removing it
function TakeTabFromByond(tab) {
  Byond.sendMessage('Remove-Tabs', { tab: tab });
}

function spell_cat_check(cat) {
  let spells_in_cat = 0;
  let spellcat = '';
  for (let s = 0; s < spells.length; s++) {
    const spell = spells[s];
    spellcat = spell[0];
    if (spellcat === cat) {
      spells_in_cat++;
    }
  }
  if (spells_in_cat < 1) {
    removeStatusTab(cat);
  }
}

function tab_change(tab) {
  if (tab === current_tab) return;
  if (document.getElementById(current_tab))
    document.getElementById(current_tab).className = 'button'; // disable active on last button
  current_tab = tab;
  set_byond_tab(tab);
  if (document.getElementById(tab))
    document.getElementById(tab).className = 'button active'; // make current button active
  const spell_tabs_thingy = spell_tabs.includes(tab);
  const verb_tabs_thingy = verb_tabs.includes(tab);
  if (tab === 'Status') {
    draw_status();
  } else if (tab === 'MC') {
    draw_mc();
  } else if (spell_tabs_thingy) {
    draw_spells(tab);
  } else if (verb_tabs_thingy) {
    draw_verbs(tab);
  } else if (tab === 'Debug Stat Panel') {
    draw_debug();
  } else if (tab === 'Tickets') {
    draw_tickets();
  } else if (misc.has(tab)) {
    draw_misc(tab);
  } else if (tab === 'Examine') {
    draw_examine();
  } else if (tab === 'SDQL2') {
    draw_sdql2();
  } else if (tab === turfname) {
    draw_listedturf();
  } else {
    statcontentdiv.textContext = 'Loading...';
  }
  Byond.winset(Byond.windowId, {
    'is-visible': true,
  });
}

function set_byond_tab(tab) {
  Byond.sendMessage('Set-Tab', { tab: tab });
}

function draw_examine() {
  statcontentdiv.textContent = '';
  const div_content = document.createElement('div');
  for (let i = 0; i < examine.length; i++) {
    const parameter = document.createElement('p');
    const textList = examine[i].split('||');
    if (textList.length > 1) {
      for (let j = 0; j < textList.length; j++) {
        const spoilerText = document.createElement('span');
        if (j % 2) {
          spoilerText.className = 'spoiler';
        }
        spoilerText.innerHTML = textList[j];
        parameter.appendChild(spoilerText);
      }
    } else {
      parameter.innerHTML = examine[i];
    }
    div_content.appendChild(parameter);
  }
  const images = div_content.querySelectorAll('img');
  for (let i = 0; i < images.length; i++) {
    images[i].addEventListener('error', iconError);
  }
  document.getElementById('statcontent').appendChild(div_content);
}

function draw_debug() {
  statcontentdiv.textContent = '';
  const wipeverbstabs = document.createElement('div');
  const link = document.createElement('a');
  link.onclick = () => {
    wipe_verbs();
  };
  link.textContent = 'Wipe All Verbs';
  wipeverbstabs.appendChild(link);
  document.getElementById('statcontent').appendChild(wipeverbstabs);
  const wipeUpdateVerbsTabs = document.createElement('div');
  const updateLink = document.createElement('a');
  updateLink.onclick = () => {
    update_verbs();
  };
  updateLink.textContent = 'Wipe and Update All Verbs';
  wipeUpdateVerbsTabs.appendChild(updateLink);
  document.getElementById('statcontent').appendChild(wipeUpdateVerbsTabs);
  const text = document.createElement('div');
  text.textContent = 'Verb Tabs:';
  document.getElementById('statcontent').appendChild(text);
  const table1 = document.createElement('table');
  for (let i = 0; i < verb_tabs.length; i++) {
    let part = verb_tabs[i];
    // Hide subgroups except admin subgroups if they are split
    if (verb_tabs[i].lastIndexOf('.') !== -1) {
      const splitName = verb_tabs[i].split('.');
      if (split_admin_tabs && splitName[0] === 'Admin') part = splitName[1];
      else continue;
    }
    const tr = document.createElement('tr');
    const td1 = document.createElement('td');
    td1.textContent = part;
    const a = document.createElement('a');
    a.onclick = ((part) => () => {
      removeStatusTab(part);
    })(part);
    a.textContent = ` Delete Tab ${part}`;
    td1.appendChild(a);
    tr.appendChild(td1);
    table1.appendChild(tr);
  }
  document.getElementById('statcontent').appendChild(table1);
  const header2 = document.createElement('div');
  header2.textContent = 'Verbs:';
  document.getElementById('statcontent').appendChild(header2);
  const table2 = document.createElement('table');
  for (let v = 0; v < verbs.length; v++) {
    const part2 = verbs[v];
    const trr = document.createElement('tr');
    const tdd1 = document.createElement('td');
    tdd1.textContent = part2[0];
    const tdd2 = document.createElement('td');
    tdd2.textContent = part2[1];
    trr.appendChild(tdd1);
    trr.appendChild(tdd2);
    table2.appendChild(trr);
  }
  document.getElementById('statcontent').appendChild(table2);
  const text3 = document.createElement('div');
  text3.textContent = 'Permanent Tabs:';
  document.getElementById('statcontent').appendChild(text3);
  const table3 = document.createElement('table');
  for (let i = 0; i < permanent_tabs.length; i++) {
    const part3 = permanent_tabs[i];
    const trrr = document.createElement('tr');
    const tddd1 = document.createElement('td');
    tddd1.textContent = part3;
    trrr.appendChild(tddd1);
    table3.appendChild(trrr);
  }
  document.getElementById('statcontent').appendChild(table3);
}
function draw_status() {
  if (!document.getElementById('Status')) {
    createStatusTab('Status');
    current_tab = 'Status';
  }
  statcontentdiv.textContent = '';
  for (let i = 0; i < status_tab_parts.length; i++) {
    if (status_tab_parts[i].trim() === '') {
      document
        .getElementById('statcontent')
        .appendChild(document.createElement('br'));
    } else {
      const div = document.createElement('div');
      div.textContent = status_tab_parts[i];
      div.className = 'status-info';
      document.getElementById('statcontent').appendChild(div);
    }
  }
  if (verb_tabs.length === 0 || !verbs) {
    Byond.command('Fix-Stat-Panel');
  }
}

function draw_mc() {
  const previousScroll = statcontentdiv.scrollTop;
  const previousWindowScroll = window.scrollY;
  const existingDetails = statcontentdiv.querySelector('.mc-details');
  if (existingDetails) mc_details_open = existingDetails.open;
  statcontentdiv.textContent = '';

  if (mc_metrics) {
    draw_mc_dashboard(mc_metrics);
  }

  const details = document.createElement('details');
  details.className = 'mc-details';
  details.open = mc_details_open;
  const summary = document.createElement('summary');
  summary.textContent = 'Detailed controller state';
  details.appendChild(summary);
  const table = document.createElement('table');
  table.className = 'mc-legacy-table';
  for (let i = 0; i < mc_tab_parts.length; i++) {
    const part = mc_tab_parts[i];
    const tr = document.createElement('tr');
    const td1 = document.createElement('td');
    td1.textContent = part[0];
    const td2 = document.createElement('td');
    if (part[2]) {
      const a = document.createElement('a');
      a.href = `byond://?_src_=vars;admin_token=${href_token};Vars=${part[2]}`;
      a.textContent = part[1];
      td2.appendChild(a);
    } else {
      td2.textContent = part[1];
    }
    tr.appendChild(td1);
    tr.appendChild(td2);
    table.appendChild(tr);
  }
  details.appendChild(table);
  statcontentdiv.appendChild(details);
  requestAnimationFrame(() => {
    statcontentdiv.scrollTop = previousScroll;
    window.scrollTo(0, previousWindowScroll);
  });
}

function mc_number(value, digits = 1) {
  const number = Number(value);
  return Number.isFinite(number) ? number.toFixed(digits) : '0.0';
}

function mc_metric_card(label, value, detail, severity = '') {
  const card = document.createElement('div');
  card.className = `mc-metric-card ${severity}`;
  const labelNode = document.createElement('div');
  labelNode.className = 'mc-metric-label';
  labelNode.textContent = label;
  const valueNode = document.createElement('div');
  valueNode.className = 'mc-metric-value';
  valueNode.textContent = value;
  const detailNode = document.createElement('div');
  detailNode.className = 'mc-metric-detail';
  detailNode.textContent = detail;
  card.append(labelNode, valueNode, detailNode);
  return card;
}

function mc_usage_severity(value) {
  if (value > 100) return 'critical';
  if (value > 75) return 'warning';
  return 'healthy';
}

function draw_mc_dashboard(metrics) {
  const dashboard = document.createElement('div');
  dashboard.className = 'mc-dashboard';

  const headline = document.createElement('div');
  headline.className = 'mc-card-grid';
  const current = Number(metrics.current_usage) || 0;
  const w30 = metrics.window_30s || {};
  headline.append(
    mc_metric_card('Current tick', `${mc_number(current)}%`, `${mc_number(current * metrics.tick_budget_ms / 100, 2)} ms of ${mc_number(metrics.tick_budget_ms, 1)} ms`, mc_usage_severity(current)),
    mc_metric_card('TPS', mc_number(w30.tps, 1), `${mc_number(metrics.target_tps, 0)} target`, Number(w30.tps) < Number(metrics.target_tps) * 0.95 ? 'warning' : 'healthy'),
    mc_metric_card('30s p99', `${mc_number(w30.p99)}%`, `max ${mc_number(w30.max)}%`, mc_usage_severity(Number(w30.p99))),
    mc_metric_card('Overruns', `${w30.overruns || 0}`, `${w30.samples || 0} ticks / 30s`, w30.overruns ? 'critical' : 'healthy'),
    mc_metric_card('Map send', `${mc_number(metrics.maptick)}%`, 'BYOND internal map work', mc_usage_severity(Number(metrics.maptick))),
    mc_metric_card('TiDi', `${mc_number(metrics.tidi)}%`, `avg ${mc_number(metrics.tidi_fast)} / ${mc_number(metrics.tidi_medium)} / ${mc_number(metrics.tidi_slow)}`),
  );
  headline.dataset.mcView = 'overview';
  dashboard.appendChild(headline);

  const navigation = document.createElement('div');
  navigation.className = 'mc-navigation';
  for (const [view, label] of [['overview', 'Overview'], ['ticks', 'Ticks'], ['subsystems', 'Subsystems'], ['outliers', 'Outliers'], ['runtime', 'Runtime']]) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `mc-nav-button${mc_view === view ? ' active' : ''}`;
    button.textContent = label;
    button.onclick = () => {
      mc_view = view;
      draw_mc();
    };
    navigation.appendChild(button);
  }
  dashboard.appendChild(navigation);

  const graphCard = document.createElement('section');
  graphCard.className = 'mc-panel';
  graphCard.dataset.mcView = 'ticks';
  const graphTitle = document.createElement('h3');
  graphTitle.textContent = 'Recent tick budget';
  const graphHint = document.createElement('span');
  graphHint.className = 'mc-panel-hint';
  graphHint.textContent = 'green <75% · amber 75–100% · red overrun';
  const graph = document.createElement('div');
  graph.className = 'mc-tick-graph';
  for (const rawValue of metrics.graph || []) {
    const value = Number(rawValue) || 0;
    const bar = document.createElement('div');
    bar.className = `mc-tick-bar ${mc_usage_severity(value)}`;
    bar.style.height = `${Math.max(1, Math.min(value, 200) / 2)}%`;
    bar.title = `${mc_number(value)}% (${mc_number(value * metrics.tick_budget_ms / 100, 2)} ms)`;
    graph.appendChild(bar);
  }
  const budgetLine = document.createElement('div');
  budgetLine.className = 'mc-budget-line';
  graph.appendChild(budgetLine);
  graphCard.append(graphTitle, graphHint, graph);
  dashboard.appendChild(graphCard);

  const windows = document.createElement('section');
  windows.className = 'mc-panel';
  windows.dataset.mcView = 'ticks';
  const windowsTitle = document.createElement('h3');
  windowsTitle.textContent = 'Tick distribution';
  const distributionTable = document.createElement('table');
  distributionTable.className = 'mc-performance-table';
  const header = document.createElement('tr');
  for (const text of ['Window', 'TPS', 'Average', 'p50', 'p95', 'p99', 'Maximum', 'Overruns', 'pctl n']) {
    const th = document.createElement('th');
    th.textContent = text;
    header.appendChild(th);
  }
  distributionTable.appendChild(header);
  for (const [label, windowData] of [['5 sec', metrics.window_5s], ['30 sec', metrics.window_30s], ['5 min', metrics.window_5m]]) {
    const row = document.createElement('tr');
    const values = [label, mc_number(windowData.tps, 1), `${mc_number(windowData.avg)}%`, `${mc_number(windowData.p50)}%`, `${mc_number(windowData.p95)}%`, `${mc_number(windowData.p99)}%`, `${mc_number(windowData.max)}%`, `${windowData.overruns || 0}`, `${windowData.percentile_samples || windowData.samples || 0}`];
    for (const value of values) {
      const cell = document.createElement('td');
      cell.textContent = value;
      row.appendChild(cell);
    }
    distributionTable.appendChild(row);
  }
  windows.append(windowsTitle, distributionTable);
  dashboard.appendChild(windows);

  const runtime = metrics.runtime || {};
  const runtimePanel = document.createElement('section');
  runtimePanel.className = 'mc-panel';
  runtimePanel.dataset.mcView = 'runtime';
  const runtimeTitle = document.createElement('h3');
  runtimeTitle.textContent = 'Runtime health';
  const runtimeGrid = document.createElement('div');
  runtimeGrid.className = 'mc-runtime-grid';
  const runtimeValues = [
    ['BYOND CPU', `${mc_number(runtime.cpu)}%`],
    ['Instances', Number(runtime.instances || 0).toLocaleString()],
    ['Clients', `${runtime.clients || 0}`],
    ['Timers', Number(runtime.timers || 0).toLocaleString()],
    ['Tick drift', mc_number(runtime.tick_drift, 2)],
    ['Sleep factor', mc_number(runtime.sleep_delta, 2)],
    ['Queue pressure', `${mc_number(runtime.queue_priority, 2)} + ${mc_number(runtime.queue_priority_background, 2)} bg`],
    ['Rust memory', `${mc_number(Number(runtime.rust_current_bytes) / 1048576, 1)} / ${mc_number(Number(runtime.rust_peak_bytes) / 1048576, 1)} MiB`],
  ];
  for (const [label, value] of runtimeValues) {
    const item = document.createElement('div');
    item.className = 'mc-runtime-item';
    const labelNode = document.createElement('span');
    labelNode.textContent = label;
    const valueNode = document.createElement('strong');
    valueNode.textContent = value;
    item.append(labelNode, valueNode);
    runtimeGrid.appendChild(item);
  }
  runtimePanel.append(runtimeTitle, runtimeGrid);
  dashboard.appendChild(runtimePanel);

  const subsystemPanel = document.createElement('section');
  subsystemPanel.className = 'mc-panel';
  subsystemPanel.dataset.mcView = 'subsystems';
  const subsystemTitle = document.createElement('h3');
  subsystemTitle.textContent = 'Subsystem pressure';
  subsystemPanel.appendChild(subsystemTitle);
  const sortedSubsystems = (metrics.subsystems || []).slice().sort((a, b) => (Number(b.usage) + Number(b.overrun)) - (Number(a.usage) + Number(a.overrun)));
  for (const subsystem of sortedSubsystems) {
    const usage = Number(subsystem.usage) || 0;
    const overrun = Number(subsystem.overrun) || 0;
    if (usage < 0.05 && overrun < 0.05) continue;
    const row = document.createElement('div');
    row.className = 'mc-subsystem-row';
    const name = document.createElement('a');
    name.className = 'mc-subsystem-name';
    name.href = `byond://?_src_=vars;admin_token=${href_token};Vars=${subsystem.ref}`;
    name.textContent = `[${subsystem.state || '-'}] ${subsystem.name}`;
    const track = document.createElement('div');
    track.className = 'mc-subsystem-track';
    const usedBar = document.createElement('div');
    usedBar.className = `mc-subsystem-used ${mc_usage_severity(usage)}`;
    usedBar.style.width = `${Math.min(usage, 100)}%`;
    track.appendChild(usedBar);
    if (overrun > 0) {
      const overrunBar = document.createElement('div');
      overrunBar.className = 'mc-subsystem-overrun';
      overrunBar.style.width = `${Math.min(overrun, 100)}%`;
      track.appendChild(overrunBar);
    }
    const value = document.createElement('span');
    value.className = 'mc-subsystem-value';
    value.textContent = `${mc_number(subsystem.cost, 2)} ms · ${mc_number(usage)}% · +${mc_number(overrun)}%`;
    row.append(name, track, value);
    subsystemPanel.appendChild(row);
  }
  dashboard.appendChild(subsystemPanel);

  const outliers = (metrics.outliers || []).slice().reverse();
  const outlierPanel = document.createElement('section');
  outlierPanel.className = 'mc-panel';
  outlierPanel.dataset.mcView = 'outliers';
  const outlierTitle = document.createElement('h3');
  outlierTitle.textContent = `Recent overruns (${outliers.length}/20 retained)`;
  outlierPanel.appendChild(outlierTitle);
  if (!outliers.length) {
    const empty = document.createElement('div');
    empty.className = 'mc-empty';
    empty.textContent = 'No tick overruns recorded.';
    outlierPanel.appendChild(empty);
  } else {
    for (const outlier of outliers) {
      const item = document.createElement('div');
      item.className = 'mc-outlier';
      const outlierId = `${outlier.world_time}-${outlier.usage}`;
      const heading = document.createElement('button');
      heading.type = 'button';
      heading.className = 'mc-outlier-heading';
      heading.textContent = `${mc_selected_outlier === outlierId ? '▾' : '▸'} t=${mc_number(outlier.world_time / 10, 1)}s · ${mc_number(outlier.usage)}% (+${mc_number(outlier.overrun)}%) · top: ${outlier.top_subsystem} ${mc_number(outlier.top_usage)}%`;
      heading.onclick = () => {
        mc_selected_outlier = mc_selected_outlier === outlierId ? null : outlierId;
        draw_mc();
      };
      item.appendChild(heading);
      if (mc_selected_outlier === outlierId) {
        const detail = document.createElement('div');
        detail.className = 'mc-outlier-breakdown';
        const breakdown = (outlier.breakdown || []).slice().sort((a, b) => Number(b.usage) - Number(a.usage));
        for (const entry of breakdown) {
          const row = document.createElement('div');
          row.className = 'mc-breakdown-row';
          const name = document.createElement('span');
          name.textContent = entry.name;
          const track = document.createElement('div');
          track.className = 'mc-breakdown-track';
          const bar = document.createElement('div');
          bar.className = `mc-breakdown-bar ${mc_usage_severity(Number(entry.usage))}`;
          bar.style.width = `${Math.min(Number(entry.usage) || 0, 100)}%`;
          track.appendChild(bar);
          const value = document.createElement('strong');
          value.textContent = `${mc_number(entry.usage)}%`;
          row.append(name, track, value);
          detail.appendChild(row);
        }
        const mapTick = document.createElement('div');
        mapTick.className = 'mc-outlier-note';
        mapTick.textContent = `BYOND map-send usage at capture: ${mc_number(outlier.maptick)}%`;
        detail.appendChild(mapTick);
        item.appendChild(detail);
      }
      outlierPanel.appendChild(item);
    }
  }
  dashboard.appendChild(outlierPanel);
  for (const panel of dashboard.querySelectorAll('[data-mc-view]')) {
    panel.hidden = panel.dataset.mcView !== mc_view;
  }
  statcontentdiv.appendChild(dashboard);
}

function remove_tickets() {
  if (tickets) {
    tickets = [];
    removePermanentTab('Tickets');
    if (current_tab === 'Tickets') tab_change('Status');
  }
  checkStatusTab();
}

function remove_sdql2() {
  if (sdql2) {
    sdql2 = [];
    removePermanentTab('SDQL2');
    if (current_tab === 'SDQL2') tab_change('Status');
  }
  checkStatusTab();
}

function iconError(e) {
  setTimeout(() => {
    if (current_tab !== turfname && current_tab !== 'Examine') {
      return;
    }
    const node = e.target;
    const current_attempts = Number(node.getAttribute('data-attempts')) || 0;
    if (current_attempts > imageRetryLimit) {
      return;
    }
    const src = node.src;
    node.src = null;
    node.src = `${src}#${current_attempts}`;
    node.setAttribute('data-attempts', current_attempts + 1);
  }, imageRetryDelay);
}

function draw_listedturf() {
  statcontentdiv.textContent = '';
  const table = document.createElement('table');
  for (let i = 0; i < turfcontents.length; i++) {
    const part = turfcontents[i];
    if (storedimages[part[1]] == null && part[2]) {
      const img = document.createElement('img');
      img.src = part[2];
      img.id = part[1];
      storedimages[part[1]] = part[2];
      img.onerror = iconError;
      table.appendChild(img);
    } else {
      const img = document.createElement('img');
      img.onerror = iconError;
      img.src = storedimages[part[1]];
      img.id = part[1];
      table.appendChild(img);
    }
    const b = document.createElement('div');
    b.className = 'link';
    b.onmousedown = ((part) => {
      // The outer function is used to close over a fresh "part" variable,
      // rather than every onmousedown getting the "part" of the last entry.
      return (e) => {
        e.preventDefault();
        const params = { src: part[1] };
        switch (e.button) {
          case 1:
            params.statpanel_item_click = 'middle';
            break;
          case 2:
            params.statpanel_item_click = 'right';
            break;
          default:
            params.statpanel_item_click = 'left';
        }
        if (e.shiftKey) {
          params.statpanel_item_shiftclick = 1;
        }
        if (e.ctrlKey) {
          params.statpanel_item_ctrlclick = 1;
        }
        if (e.altKey) {
          params.statpanel_item_altclick = 1;
        }
        Byond.topic(params);
      };
    })(part);
    b.textContent = part[0];
    table.appendChild(b);
    table.appendChild(document.createElement('br'));
  }
  statcontentdiv.appendChild(table);
}

function remove_listedturf() {
  removePermanentTab(turfname);
  checkStatusTab();
  if (current_tab === turfname) {
    tab_change('Status');
  }
}

function remove_mc() {
  removePermanentTab('MC');
  if (current_tab === 'MC') {
    tab_change('Status');
  }
}

function draw_sdql2() {
  statcontentdiv.textContent = '';
  const table = document.createElement('table');
  for (let i = 0; i < sdql2.length; i++) {
    const part = sdql2[i];
    const tr = document.createElement('tr');
    const td1 = document.createElement('td');
    td1.textContent = part[0];
    const td2 = document.createElement('td');
    if (part[2]) {
      const a = document.createElement('a');
      a.href = `byond://?src=${part[2]};statpanel_item_click=left`;
      a.textContent = part[1];
      td2.appendChild(a);
    } else {
      td2.textContent = part[1];
    }
    tr.appendChild(td1);
    tr.appendChild(td2);
    table.appendChild(tr);
  }
  document.getElementById('statcontent').appendChild(table);
}

function draw_tickets() {
  statcontentdiv.textContent = '';
  const table = document.createElement('table');
  if (!tickets) {
    return;
  }
  for (let i = 0; i < tickets.length; i++) {
    const part = tickets[i];
    const tr = document.createElement('tr');
    const td1 = document.createElement('td');
    td1.textContent = part[0];
    const td2 = document.createElement('td');
    if (part[2]) {
      const a = document.createElement('a');
      a.href = `byond://?_src_=holder;admin_token=${href_token};ahelp=${part[2]};ahelp_action=ticket;statpanel_item_click=left;action=ticket`;
      a.textContent = part[1];
      td2.appendChild(a);
    } else if (part[3]) {
      const a = document.createElement('a');
      a.href = `byond://?src=${part[3]};statpanel_item_click=left`;
      a.textContent = part[1];
      td2.appendChild(a);
    } else {
      td2.textContent = part[1];
    }
    tr.appendChild(td1);
    tr.appendChild(td2);
    table.appendChild(tr);
  }
  document.getElementById('statcontent').appendChild(table);
}

function draw_misc(tab) {
  statcontentdiv.textContent = '';
  const table = document.createElement('table');
  table.className = 'elemcontainer';
  const data = misc.get(tab);
  if (!data) {
    return;
  }
  for (let i = 0; i < data.length; i++) {
    const tr = document.createElement('tr');
    const part = data[i];

    const td1 = document.createElement('td');
    if (part[0]) {
      td1.className = 'elem';
      td1.textContent = part[0];
    }

    let td2 = null;
    if (part[1] && storedimages[part[1]] == null && part[2]) {
      td2 = document.createElement('td');
      const img = document.createElement('img');
      img.src = part[2];
      img.id = part[1];
      storedimages[part[1]] = part[2];
      td2.appendChild(img);
    } else if (part[1]) {
      td2 = document.createElement('td');
      const img = document.createElement('img');
      img.src = storedimages[part[1]];
      img.id = part[1];
      td2.appendChild(img);
    }
    let td3 = null;
    const b = document.createElement('div');
    if (part[4]) {
      b.className = 'linkelem';
      b.onmousedown = ((part) => {
        // The outer function is used to close over a fresh "part" variable,
        // rather than every onmousedown getting the "part" of the last entry.
        return (e) => {
          e.preventDefault();
          const params = { src: part[4] };
          switch (e.button) {
            case 1:
              params.statpanel_item_click = 'middle';
              break;
            case 2:
              params.statpanel_item_click = 'right';
              break;
            default:
              params.statpanel_item_click = 'left';
          }
          if (e.shiftKey) {
            params.statpanel_item_shiftclick = 1;
          }
          if (e.ctrlKey) {
            params.statpanel_item_ctrlclick = 1;
          }
          if (e.altKey) {
            params.statpanel_item_altclick = 1;
          }
          Byond.topic(params);
        };
      })(part);
    }
    if (part[3]) {
      td3 = document.createElement('td');
      b.textContent = part[3];
      td3.appendChild(b);
    }
    if (!td2 && !td3) {
      td1.className = 'elem_span3';
      td1.colSpan += 2;
    } else if (!td2) {
      td1.className = 'elem_span2';
      td1.colSpan += 1;
    } else if (!td3) {
      td2.colSpan += 1;
    }
    tr.appendChild(td1);
    if (td2) {
      tr.appendChild(td2);
    }
    if (td3) {
      tr.appendChild(td3);
    }
    table.appendChild(tr);
  }
  document.getElementById('statcontent').appendChild(table);
}

function draw_spells(cat) {
  statcontentdiv.textContent = '';
  const table = document.createElement('table');
  for (let i = 0; i < spells.length; i++) {
    const part = spells[i];
    if (part[0] !== cat) continue;
    const tr = document.createElement('tr');
    const td1 = document.createElement('td');
    td1.textContent = part[1];
    const td2 = document.createElement('td');
    if (part[3]) {
      const a = document.createElement('a');
      a.href = `byond://?src=${part[3]};statpanel_item_click=left`;
      a.textContent = part[2];
      td2.appendChild(a);
    } else {
      td2.textContent = part[2];
    }
    tr.appendChild(td1);
    tr.appendChild(td2);
    table.appendChild(tr);
  }
  document.getElementById('statcontent').appendChild(table);
}

function make_verb_onclick(command) {
  return () => {
    run_after_focus(() => {
      Byond.command(command);
    });
  };
}

function draw_verbs(cat) {
  statcontentdiv.textContent = '';
  const table = document.createElement('div');
  const additions = {}; // additional sub-categories to be rendered
  table.className = 'grid-container';
  sortVerbs();
  if (split_admin_tabs && cat.lastIndexOf('.') !== -1) {
    const splitName = cat.split('.');
    if (splitName[0] === 'Admin') cat = splitName[1];
  }
  verbs.reverse(); // sort verbs backwards before we draw
  for (let i = 0; i < verbs.length; ++i) {
    const part = verbs[i];
    let name = part[0];
    if (split_admin_tabs && name.lastIndexOf('.') !== -1) {
      const splitName = name.split('.');
      if (splitName[0] === 'Admin') name = splitName[1];
    }
    const command = part[1];
    const desc = part[2];

    if (
      command &&
      name.lastIndexOf(cat, 0) !== -1 &&
      (name.length === cat.length || name.charAt(cat.length) === '.')
    ) {
      const subCat = name.lastIndexOf('.') !== -1 ? name.split('.')[1] : null;
      if (subCat && !additions[subCat]) {
        const newTable = document.createElement('div');
        newTable.className = 'grid-container';
        additions[subCat] = newTable;
      }

      const a = document.createElement('a');
      a.href = '#';
      a.onclick = make_verb_onclick(command.replace(/\s/g, '-'));
      a.className = 'grid-item';
      a.title = desc || 'No description';
      const t = document.createElement('span');
      t.textContent = command;
      t.className = 'grid-item-text';
      a.appendChild(t);
      (subCat ? additions[subCat] : table).appendChild(a);
    }
  }

  // Append base table to view
  const content = document.getElementById('statcontent');
  content.appendChild(table);

  // Append additional sub-categories if relevant
  for (const cat in additions) {
    if (Object.hasOwn(additions, cat)) {
      // do addition here
      const header = document.createElement('h3');
      header.textContent = cat;
      content.appendChild(header);
      content.appendChild(additions[cat]);
    }
  }
}

function set_theme(which) {
  if (which === 'light' || which === 'vchatlight') {
    document.body.className = '';
    document.documentElement.className = 'light';
  } else if (which === 'dark' || which === 'vchatdark') {
    document.body.className = 'dark';
    document.documentElement.className = 'dark';
  }
}

function set_font_size(size) {
  document.body.style.setProperty('font-size', size);
}

function set_tabs_style(style) {
  if (style === 'default') {
    menu.classList.add('menu-wrap');
    menu.classList.remove('tabs-classic');
  } else if (style === 'classic') {
    menu.classList.add('menu-wrap');
    menu.classList.add('tabs-classic');
  } else if (style === 'scrollable') {
    menu.classList.remove('menu-wrap');
    menu.classList.remove('tabs-classic');
  }
}

function restoreFocus() {
  run_after_focus(() => {
    Byond.winset('map', {
      focus: true,
    });
  });
}

function getCookie(cname) {
  const name = `${cname}=`;
  const ca = document.cookie.split(';');
  for (let i = 0; i < ca.length; i++) {
    let c = ca[i];
    while (c.charAt(0) === ' ') c = c.substring(1);
    if (c.indexOf(name) === 0) {
      return decoder(c.substring(name.length, c.length));
    }
  }
  return '';
}

function add_verb_list(payload) {
  const to_add = payload; // list of a list with category and verb inside it
  to_add.sort(); // sort what we're adding
  for (let i = 0; i < to_add.length; i++) {
    const part = to_add[i];
    if (!part[0]) continue;
    let category = part[0];
    if (category.indexOf('.') !== -1) {
      const splitName = category.split('.');
      if (split_admin_tabs && splitName[0] === 'Admin') category = splitName[1];
      else category = splitName[0];
    }
    if (findVerbindex(part[1], verbs)) continue;
    if (verb_tabs.includes(category)) {
      verbs.push(part);
      if (current_tab === category) {
        draw_verbs(category); // redraw if we added a verb to the tab we're currently in
      }
    } else if (category) {
      verb_tabs.push(category);
      verbs.push(part);
      createStatusTab(category);
    }
  }
}

function init_spells() {
  let cat = '';
  for (let i = 0; i < spell_tabs.length; i++) {
    cat = spell_tabs[i];
    if (cat.length > 0) {
      verb_tabs.push(cat);
      createStatusTab(cat);
    }
  }
}

document.addEventListener('mouseup', restoreFocus);
document.addEventListener('keyup', restoreFocus);

if (!current_tab) {
  addPermanentTab('Status');
  tab_change('Status');
}

window.onload = () => {
  Byond.sendMessage('Update-Verbs');
};

Byond.subscribeTo('update_spells', (payload) => {
  spell_tabs = payload.spell_tabs;
  let do_update = false;
  if (spell_tabs.includes(current_tab)) {
    do_update = true;
  }
  init_spells();
  if (payload.actions) {
    spells = payload.actions;
    if (do_update) {
      draw_spells(current_tab);
    }
  } else {
    remove_spells();
  }
});

Byond.subscribeTo('remove_verb_list', (v) => {
  const to_remove = v;
  for (let i = 0; i < to_remove.length; i++) {
    remove_verb(to_remove[i]);
  }
  check_verbs();
  sortVerbs();
  if (verb_tabs.includes(current_tab)) draw_verbs(current_tab);
});

// passes a 2D list of (verbcategory, verbname) creates tabs and adds verbs to respective list
// example (IC, Say)
Byond.subscribeTo('init_verbs', (payload) => {
  wipe_verbs(); // remove all verb categories so we can replace them
  checkStatusTab(); // remove all status tabs
  verb_tabs = payload.panel_tabs;
  verb_tabs.sort(); // sort it
  let do_update = false;
  let cat = '';
  for (let i = 0; i < verb_tabs.length; i++) {
    cat = verb_tabs[i];
    createStatusTab(cat); // create a category if the verb doesn't exist yet
  }
  if (verb_tabs.includes(current_tab)) {
    do_update = true;
  }
  if (payload.verblist) {
    add_verb_list(payload.verblist);
    sortVerbs(); // sort them
    if (do_update) {
      draw_verbs(current_tab);
    }
  }
  SendTabsToByond();
});

Byond.subscribeTo('update_stat', (payload) => {
  status_tab_parts = [payload.ping_str];
  let parsed = payload.global_data;

  for (let i = 0; i < parsed.length; i++)
    if (parsed[i] != null) status_tab_parts.push(parsed[i]);

  parsed = payload.other_str;

  for (let i = 0; i < parsed.length; i++)
    if (parsed[i] != null) status_tab_parts.push(parsed[i]);

  if (current_tab === 'Status') {
    draw_status();
  } else if (current_tab === 'Debug Stat Panel') {
    draw_debug();
  }
});

Byond.subscribeTo('update_mc', (payload) => {
  mc_tab_parts = payload.mc_data;
  mc_metrics = payload.mc_metrics;
  mc_tab_parts.splice(0, 0, ['Location:', payload.coord_entry]);

  if (!verb_tabs.includes('MC')) {
    verb_tabs.push('MC');
  }

  createStatusTab('MC');

  if (current_tab === 'MC') {
    draw_mc();
  }
});

Byond.subscribeTo('remove_spells', () => {
  for (let s = 0; s < spell_tabs.length; s++) {
    removeStatusTab(spell_tabs[s]);
  }
});

Byond.subscribeTo('init_spells', () => {
  let cat = '';
  for (let i = 0; i < spell_tabs.length; i++) {
    cat = spell_tabs[i];
    if (cat.length > 0) {
      verb_tabs.push(cat);
      createStatusTab(cat);
    }
  }
});

Byond.subscribeTo('check_spells', () => {
  for (let v = 0; v < spell_tabs.length; v++) {
    spell_cat_check(spell_tabs[v]);
  }
});

Byond.subscribeTo('create_debug', () => {
  if (!document.getElementById('Debug Stat Panel')) {
    addPermanentTab('Debug Stat Panel');
  } else {
    removePermanentTab('Debug Stat Panel');
  }
});

Byond.subscribeTo('create_listedturf', (TN) => {
  remove_listedturf(); // remove the last one if we had one
  turfname = TN;
  addPermanentTab(turfname);
  tab_change(turfname);
});

Byond.subscribeTo('create_misc', (TN) => {
  addPermanentTab(TN);
});

Byond.subscribeTo('remove_misc', (TN) => {
  removePermanentTab(TN);
});

Byond.subscribeTo('remove_admin_tabs', () => {
  href_token = null;
  remove_mc();
  remove_tickets();
  remove_sdql2();
});

Byond.subscribeTo('update_listedturf', (TC) => {
  turfcontents = TC;
  if (current_tab === turfname) {
    draw_listedturf();
  }
});

Byond.subscribeTo('update_misc', (payload) => {
  const { TN, TC } = payload;
  const old = misc.get(TN);

  misc.set(TN, TC);

  if (current_tab === TN && JSON.stringify(old) !== JSON.stringify(TC)) {
    draw_misc(TN);
  }
});

Byond.subscribeTo('update_split_admin_tabs', (status) => {
  status = status === true;

  if (split_admin_tabs !== status) {
    if (split_admin_tabs === true) {
      removeStatusTab('Events');
      removeStatusTab('Fun');
      removeStatusTab('Game');
    }
    update_verbs();
  }
  split_admin_tabs = status;
});

Byond.subscribeTo('add_admin_tabs', (ht) => {
  href_token = ht;
  addPermanentTab('MC');
  addPermanentTab('Tickets');
});

Byond.subscribeTo('add_tickets_tabs', (ht) => {
  href_token = ht;
  addPermanentTab('Tickets');
});

Byond.subscribeTo('update_examine', (payload) => {
  examine = payload.EX;
  if (examine.length > 0 && !verb_tabs.includes('Examine')) {
    verb_tabs.push('Examine');
    addPermanentTab('Examine');
  }
  if (current_tab === 'Examine') {
    draw_examine();
  }
  if (payload.UPD) {
    tab_change('Examine');
  }
});

Byond.subscribeTo('update_sdql2', (S) => {
  sdql2 = S;
  if (sdql2.length > 0 && !verb_tabs.includes('SDQL2')) {
    verb_tabs.push('SDQL2');
    addPermanentTab('SDQL2');
  }
  if (current_tab === 'SDQL2') {
    draw_sdql2();
  }
});

Byond.subscribeTo('update_tickets', (T) => {
  tickets = T;
  if (!verb_tabs.includes('Tickets')) {
    verb_tabs.push('Tickets');
    addPermanentTab('Tickets');
  }
  if (current_tab === 'Tickets') {
    draw_tickets();
  }
});

Byond.subscribeTo('remove_listedturf', remove_listedturf);

Byond.subscribeTo('remove_sdql2', remove_sdql2);

Byond.subscribeTo('remove_mc', remove_mc);

Byond.subscribeTo('add_verb_list', add_verb_list);
