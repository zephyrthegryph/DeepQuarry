/**
 * Layout checks run in the preview page (tools/tgui_preview/check.ts). Each finding names the rule, an element
 * path and a short detail; `markFindings` outlines the offenders so a screenshot shows them.
 */
export type Finding = {
  rule: string;
  detail: string;
  path: string;
  box: [number, number, number, number];
};

const CONTROL =
  '.Button, .Tab, .Input, .NumberInput, .Dropdown__control, .Slider, .Checkbox';
const TEXTY =
  '.Button, .Tab, .Dropdown__selected-text, .LabeledList__row > .LabeledList__cell:first-child, .Section__titleText, .NoticeBox';
// A row is label, value, optional buttons (the label cell carries no stable class of its own).
const LABEL_CELL = '.LabeledList__cell:first-child';
const VALUE_CELL = '.LabeledList__cell:nth-child(2)';

function visible(el: Element): boolean {
  const r = el.getBoundingClientRect();
  if (r.width < 1 || r.height < 1) return false;
  const cs = getComputedStyle(el);
  return (
    cs.display !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0'
  );
}

function path(el: Element): string {
  const parts: string[] = [];
  let cur: Element | null = el;
  while (cur && parts.length < 4 && cur.tagName !== 'BODY') {
    const cls = (cur.getAttribute('class') ?? '')
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .join('.');
    parts.unshift(cur.tagName.toLowerCase() + (cls ? `.${cls}` : ''));
    cur = cur.parentElement;
  }
  return parts.join(' > ');
}

function box(el: Element): Finding['box'] {
  const r = el.getBoundingClientRect();
  return [
    Math.round(r.left),
    Math.round(r.top),
    Math.round(r.width),
    Math.round(r.height),
  ];
}

/** The union rect of an element's text nodes, or null when it has no text. */
function textRect(el: Element): DOMRect | null {
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  let rect: DOMRect | null = null;
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (!n.textContent?.trim()) continue;
    const range = document.createRange();
    range.selectNodeContents(n);
    const r = range.getBoundingClientRect();
    if (r.width < 1) continue;
    rect = rect
      ? new DOMRect(
          Math.min(rect.left, r.left),
          Math.min(rect.top, r.top),
          Math.max(rect.right, r.right) - Math.min(rect.left, r.left),
          Math.max(rect.bottom, r.bottom) - Math.min(rect.top, r.top),
        )
      : r;
  }
  return rect;
}

/** How many lines the element's own text runs over. */
function textLineCount(el: Element): number {
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  const tops: number[] = [];
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (!n.textContent?.trim()) continue;
    const range = document.createRange();
    range.selectNodeContents(n);
    for (const r of Array.from(range.getClientRects())) {
      if (r.width >= 1) tops.push(r.top + r.height / 2);
    }
  }
  tops.sort((a, b) => a - b);
  let lines = tops.length ? 1 : 0;
  for (let i = 1; i < tops.length; i++) {
    if (tops[i] - tops[i - 1] > 6) lines++;
  }
  return lines;
}

function inScope(el: Element): boolean {
  return !!el.closest('.Window') && !el.closest('.TitleBar');
}

export function alignmentFindings(): Finding[] {
  const out: Finding[] = [];
  const add = (rule: string, el: Element, detail: string) =>
    out.push({ rule, detail, path: path(el), box: box(el) });
  const root = document.querySelector('.Window');
  if (!root) return out;

  // 1. Text clipped or running past its box, and controls past the window edge.
  for (const el of Array.from(root.querySelectorAll(TEXTY))) {
    if (!inScope(el) || !visible(el)) continue;
    const cs = getComputedStyle(el);
    if (cs.display === 'table-cell') continue;
    if (cs.textOverflow === 'ellipsis') {
      if (el.scrollWidth > el.clientWidth + 1)
        add(
          'truncated',
          el,
          `text cut with an ellipsis (${el.scrollWidth}px in ${el.clientWidth}px)`,
        );
      continue;
    }
    if (el.scrollWidth > el.clientWidth + 1) {
      add(
        'overflow',
        el,
        `scrollWidth ${el.scrollWidth} > clientWidth ${el.clientWidth}`,
      );
    }
  }
  // Anything that hides its overflow while its content runs past the edge is clipping text or a control.
  for (const el of Array.from(root.querySelectorAll('*'))) {
    if (!inScope(el) || !visible(el)) continue;
    const cs = getComputedStyle(el);
    if (cs.overflowX !== 'hidden' && cs.overflowX !== 'clip') continue;
    const ownText = Array.from(el.childNodes).some(
      (n) => n.nodeType === 3 && n.textContent?.trim(),
    );
    if (!ownText) continue;
    if (
      cs.textOverflow === 'ellipsis' ||
      el.matches(
        '.ProgressBar, .Tabs, .Window, .Layout, .Layout__content, .Section__content',
      )
    )
      continue;
    if (el.scrollWidth > el.clientWidth + 2) {
      add('clipped', el, `content ${el.scrollWidth}px in ${el.clientWidth}px`);
    }
  }
  // A text field shows its whole placeholder or value.
  const ruler = document.createElement('canvas').getContext('2d');
  for (const input of Array.from(
    root.querySelectorAll('input.Input, input.Input__input, textarea'),
  )) {
    if (!inScope(input) || !visible(input) || !ruler) continue;
    const field = input as HTMLInputElement;
    const cs = getComputedStyle(field);
    ruler.font = `${cs.fontStyle} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
    const text = field.value || field.placeholder;
    if (!text) continue;
    const room =
      field.clientWidth -
      parseFloat(cs.paddingLeft) -
      parseFloat(cs.paddingRight);
    if (ruler.measureText(text).width > room + 1) {
      add(
        'field-cut',
        field,
        `"${text}" needs ${Math.round(ruler.measureText(text).width)}px of ${Math.round(room)}px`,
      );
    }
  }
  const vw = window.innerWidth;
  for (const el of Array.from(root.querySelectorAll(`${CONTROL}, .Section`))) {
    if (!inScope(el) || !visible(el)) continue;
    const r = el.getBoundingClientRect();
    if (r.right > vw + 1 || r.left < -1) {
      add(
        'offscreen',
        el,
        `x ${Math.round(r.left)}..${Math.round(r.right)} of ${vw}`,
      );
    }
  }

  // 2. Overlapping sibling controls.
  for (const parent of Array.from(root.querySelectorAll('*'))) {
    if (!inScope(parent)) continue;
    const kids = Array.from(parent.children).filter((c) => {
      if (!c.matches(CONTROL) || !visible(c)) return false;
      const p = getComputedStyle(c).position;
      return p !== 'absolute' && p !== 'fixed';
    });
    for (let i = 0; i < kids.length; i++) {
      for (let j = i + 1; j < kids.length; j++) {
        const a = kids[i].getBoundingClientRect();
        const b = kids[j].getBoundingClientRect();
        const w = Math.min(a.right, b.right) - Math.max(a.left, b.left);
        const h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
        if (w > 2 && h > 2) {
          add(
            'overlap',
            kids[j],
            `overlaps ${path(kids[i])} by ${Math.round(w)}x${Math.round(h)}`,
          );
        }
      }
    }
  }

  // 3. Buttons on one row: same height and bottom.
  for (const parent of Array.from(root.querySelectorAll('*'))) {
    if (!inScope(parent)) continue;
    const btns = Array.from(parent.children).filter(
      (c) =>
        c.matches('.Button') &&
        visible(c) &&
        getComputedStyle(c).display.startsWith('inline'),
    );
    if (btns.length < 2) continue;
    const rows = new Map<number, Element[]>();
    for (const b of btns) {
      const r = b.getBoundingClientRect();
      const key = Math.round((r.top + r.height / 2) / 6);
      rows.set(key, [...(rows.get(key) ?? []), b]);
    }
    for (const row of rows.values()) {
      if (row.length < 2) continue;
      const hs = row.map((b) => b.getBoundingClientRect().height);
      const bs = row.map((b) => b.getBoundingClientRect().bottom);
      if (Math.max(...hs) - Math.min(...hs) > 1.5) {
        add('row-height', row[0], `heights ${hs.map(Math.round).join('/')}`);
      } else if (Math.max(...bs) - Math.min(...bs) > 1.5) {
        add('row-baseline', row[0], `bottoms ${bs.map(Math.round).join('/')}`);
      }
    }
  }

  // 3b. Full-width buttons stacked in one parent are spaced evenly.
  for (const parent of Array.from(root.querySelectorAll('*'))) {
    if (!inScope(parent)) continue;
    const stack = Array.from(parent.children).filter(
      (c) => c.matches('.Button--fluid') && visible(c),
    );
    if (stack.length < 3) continue;
    const rects = stack.map((b) => b.getBoundingClientRect());
    const gaps = rects
      .slice(1)
      .map((r, i) => Math.round(r.top - rects[i].bottom));
    // Only a plain vertical column counts: same left edge, each directly under the last.
    if (
      gaps.some((g) => g < 0 || g > 12) ||
      rects.some((r) => Math.abs(r.left - rects[0].left) > 1)
    )
      continue;
    if (Math.max(...gaps) - Math.min(...gaps) > 1) {
      add(
        'stack-gap',
        stack[0],
        `gaps between stacked buttons ${gaps.join('/')}`,
      );
    }
  }

  // 3c. In a flex row, a text item sits on the same centre line as the controls beside it.
  for (const row of Array.from(root.querySelectorAll('*'))) {
    if (!inScope(row)) continue;
    const rs = getComputedStyle(row);
    if (
      !rs.display.includes('flex') ||
      rs.flexDirection !== 'row' ||
      rs.flexWrap !== 'nowrap'
    )
      continue;
    const kids = Array.from(row.children).filter(visible);
    const controls = kids.filter((c) =>
      c.matches('.Button, .Input, .NumberInput, .Dropdown, .Slider'),
    );
    if (!controls.length) continue;
    for (const t of kids) {
      if (
        controls.includes(t) ||
        t.querySelector(
          '.Button, .Input, .NumberInput, .Dropdown, .Slider, .Stack',
        )
      )
        continue;
      if (
        !Array.from(t.childNodes).some(
          (n) => n.nodeType === 3 && n.textContent?.trim(),
        )
      )
        continue;
      const tr = textRect(t);
      if (!tr) continue;
      const tc = tr.top + tr.height / 2;
      for (const c of controls) {
        const cr = c.getBoundingClientRect();
        if (cr.height > 40 || cr.height < 8) continue;
        if (Math.abs(tc - (cr.top + cr.height / 2)) > 3.5) {
          add(
            'row-centre',
            t,
            `text centre ${Math.round(tc)} vs ${path(c)} centre ${Math.round(cr.top + cr.height / 2)}`,
          );
          break;
        }
      }
    }
  }

  // 3d. A horizontal tab bar fits on one row.
  for (const bar of Array.from(root.querySelectorAll('.Tabs--horizontal'))) {
    if (!inScope(bar) || !visible(bar)) continue;
    const tops = new Set(
      Array.from(bar.querySelectorAll(':scope > .Tab'))
        .filter(visible)
        .map((t) => Math.round(t.getBoundingClientRect().top / 4)),
    );
    if (tops.size > 1) add('tabs-wrap', bar, `${tops.size} rows of tabs`);
  }

  // 3e. A nested section stays inside the section around it (the parent clips what runs past its bottom edge).
  for (const sec of Array.from(root.querySelectorAll('.Section'))) {
    if (!inScope(sec) || !visible(sec)) continue;
    const outer = sec.parentElement?.closest('.Section');
    if (!outer || !visible(outer)) continue;
    const a = sec.getBoundingClientRect();
    const b = outer.getBoundingClientRect();
    // Content inside a scrolling section (or a window that scrolls) is scrolled, not spilled.
    const scroller = sec.parentElement?.closest('.Section--scrollable');
    if (scroller && (scroller === outer || outer.contains(scroller))) continue;
    if (scroller?.contains(outer)) continue;
    if (a.bottom > b.bottom + 1) {
      add(
        'section-overflow',
        sec,
        `section runs ${Math.round(a.bottom - b.bottom)}px past the bottom of the one around it`,
      );
    }
  }

  // 3g. Controls in a section's title bar stay inside the section's frame.
  for (const buttons of Array.from(
    root.querySelectorAll('.Section__buttons'),
  )) {
    const sec = buttons.closest('.Section');
    if (!sec || !inScope(buttons) || !visible(buttons)) continue;
    const sr = sec.getBoundingClientRect();
    for (const c of Array.from(
      buttons.querySelectorAll('.Button, .Input, .Dropdown, .NumberInput'),
    ).filter(visible)) {
      const r = c.getBoundingClientRect();
      if (r.right > sr.right - 2 || r.left < sr.left + 2 || r.top < sr.top) {
        add(
          'title-control-outside',
          c,
          `title-bar control x ${Math.round(r.left)}..${Math.round(r.right)} in section ${Math.round(sr.left)}..${Math.round(sr.right)}`,
        );
      }
    }
  }

  // 3h. A small group of buttons (a cell's actions) stays on one row.
  for (const group of Array.from(
    root.querySelectorAll('td, .Table__cell, .Section__buttons'),
  )) {
    if (!inScope(group) || !visible(group)) continue;
    const kids = Array.from(group.children).filter(visible);
    const btns = kids.filter(
      (c) =>
        c.matches('.Button') &&
        getComputedStyle(c).display.startsWith('inline'),
    );
    if (btns.length < 2 || btns.length > 5 || btns.length !== kids.length)
      continue;
    // Breaks put there on purpose, and a plain column of buttons, are layouts, not wraps.
    if (group.querySelector(':scope > br')) continue;
    const lefts = btns.map((b) => b.getBoundingClientRect().left);
    if (Math.max(...lefts) - Math.min(...lefts) < 2) continue;
    const tops = btns.map((b) => b.getBoundingClientRect().top);
    if (Math.max(...tops) - Math.min(...tops) > 8)
      add(
        'buttons-split',
        group,
        `${btns.length} buttons wrapped onto more than one row`,
      );
  }

  // 3i. A number field shows its value and unit on one line.
  for (const field of Array.from(
    root.querySelectorAll(
      '.NumberInput, .ProgressBar, .Dropdown__selected-text',
    ),
  )) {
    if (!inScope(field) || !visible(field)) continue;
    if (textLineCount(field) > 1)
      add(
        'field-wrap',
        field,
        `value wraps onto ${textLineCount(field)} lines`,
      );
  }

  // 3f. A short label stays on one line.
  for (const el of Array.from(root.querySelectorAll('*'))) {
    if (!inScope(el) || !visible(el)) continue;
    const own = Array.from(el.childNodes)
      .filter((n) => n.nodeType === 3)
      .map((n) => n.textContent ?? '')
      .join('')
      .trim();
    if (own.length < 3 || own.length > 14 || !own.includes(' ')) continue;
    if (el.closest('.Button, .Tab, .Tooltip, .LabeledControls')) continue;
    if (textLineCount(el) > 1)
      add('short-wrap', el, `"${own}" wraps onto ${textLineCount(el)} lines`);
  }

  // 4. LabeledList: label and value columns line up, first lines share a baseline.
  for (const list of Array.from(root.querySelectorAll('.LabeledList'))) {
    if (!inScope(list) || !visible(list)) continue;
    const rows = Array.from(list.querySelectorAll('tr')).filter(
      (r) => r.closest('.LabeledList') === list,
    );
    const labels = rows
      .map((r) => r.querySelector(`:scope > ${LABEL_CELL}`))
      .filter((e): e is Element => !!e && visible(e));
    const values = rows
      .map((r) => r.querySelector(`:scope > ${VALUE_CELL}`))
      .filter((e): e is Element => !!e && visible(e));
    for (const [name, els] of [
      ['label', labels],
      ['value', values],
    ] as const) {
      const ls = els.map((e) => Math.round(e.getBoundingClientRect().left));
      if (ls.length > 1 && Math.max(...ls) - Math.min(...ls) > 1) {
        add(
          'list-column',
          els[0],
          `${name} lefts ${[...new Set(ls)].join('/')}`,
        );
      }
    }
    for (const label of labels) {
      const value = label.parentElement?.querySelector(
        `:scope > ${VALUE_CELL}`,
      );
      // A tall value (a padded panel, several lines) positions its own text; only one-line values share the label's line.
      if (
        !value ||
        value.querySelector('.Button, .Input, .ProgressBar') ||
        value.getBoundingClientRect().height > 30
      )
        continue;
      const a = textRect(label);
      const b = textRect(value);
      if (a && b && Math.abs(a.top - b.top) > 3) {
        add(
          'list-baseline',
          label,
          `label text top ${Math.round(a.top)} vs value ${Math.round(b.top)}`,
        );
      }
    }
  }

  // 4b. Lists stacked directly on one another share one value column.
  const lists = Array.from(root.querySelectorAll('.LabeledList'))
    .filter((l) => inScope(l) && visible(l))
    .sort(
      (a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top,
    );
  const valueLeft = (l: Element) => {
    const v = l.querySelector(`tr > ${VALUE_CELL}`);
    return v ? Math.round(v.getBoundingClientRect().left) : null;
  };
  for (const a of lists) {
    const ar = a.getBoundingClientRect();
    for (const b of lists) {
      if (a === b || a.contains(b) || b.contains(a)) continue;
      const br = b.getBoundingClientRect();
      const gap = br.top - ar.bottom;
      const overlap = Math.min(ar.right, br.right) - Math.max(ar.left, br.left);
      if (gap < -5 || gap > 14 || overlap < Math.min(ar.width, br.width) * 0.6)
        continue;
      const la = valueLeft(a);
      const lb = valueLeft(b);
      if (la !== null && lb !== null && Math.abs(la - lb) > 1) {
        add(
          'list-stack',
          b,
          `value column ${lb} under a list whose values start at ${la}`,
        );
      }
    }
  }

  // 5. Icons centred in their button and with its text.
  for (const icon of Array.from(
    root.querySelectorAll('.Button .Icon, .Tab .Icon'),
  )) {
    const host = icon.closest('.Button, .Tab');
    if (!host || !inScope(host) || !visible(icon) || !visible(host)) continue;
    // A button laying out a Stack arranges its own rows; its icon is placed by that layout.
    if (host.querySelector('.Stack')) continue;
    const ir = icon.getBoundingClientRect();
    const hr = host.getBoundingClientRect();
    const ic = ir.top + ir.height / 2;
    if (Math.abs(ic - (hr.top + hr.height / 2)) > 2.5) {
      add(
        'icon-centre',
        host,
        `icon centre ${Math.round(ic)} vs button ${Math.round(hr.top + hr.height / 2)}`,
      );
    }
    const tr = textRect(host);
    // The label starts right after its icon with room between them.
    if (
      tr &&
      tr.left >= ir.right - 1 &&
      tr.left - ir.right < 2.5 &&
      !host.matches('.Button--icon-right')
    ) {
      add(
        'icon-gap',
        host,
        `icon touches its label (${Math.round(tr.left - ir.right)}px)`,
      );
    }
    if (tr && Math.abs(ic - (tr.top + tr.height / 2)) > 3) {
      add(
        'icon-text',
        host,
        `icon centre ${Math.round(ic)} vs text ${Math.round(tr.top + tr.height / 2)}`,
      );
    }
  }

  // 6. Wrapped tab and button labels.
  for (const el of Array.from(root.querySelectorAll('.Tab, .Button'))) {
    if (!inScope(el) || !visible(el)) continue;
    const cs = getComputedStyle(el);
    if (cs.whiteSpace === 'pre-wrap' || cs.whiteSpace === 'pre-line') continue;
    if (el.querySelector('.Stack')) continue;
    const lines = textLineCount(el);
    if (lines > 1) add('wrapped', el, `label wraps onto ${lines} lines`);
  }
  return out;
}

/** Outlines every finding's box in magenta. */
export function markFindings(findings: Finding[]): void {
  for (const f of findings) {
    const d = document.createElement('div');
    d.style.cssText = `position:fixed;left:${f.box[0] - 1}px;top:${f.box[1] - 1}px;width:${f.box[2] + 2}px;height:${f.box[3] + 2}px;outline:2px solid #f0f;z-index:99999;pointer-events:none`;
    d.title = `${f.rule}: ${f.detail}`;
    document.body.appendChild(d);
  }
}
