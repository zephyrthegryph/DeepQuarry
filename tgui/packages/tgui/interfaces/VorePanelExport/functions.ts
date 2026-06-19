import type { BooleanLike } from 'tgui-core/react';
import type { EmoteEntry } from './types';

// Escape backend-supplied free text before interpolating it into the
// exported HTML document. Without this, player-authored belly names,
// descriptions, messages, etc. would be a stored-XSS vector when the
// generated .html file is opened in a browser.
export function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Validate a backend-supplied color string before interpolating it into a
// `style="color:..."` attribute. Only allow #hex codes and simple CSS named
// colors (letters) so the value can't break out of the style context.
const COLOR_PATTERN = /^(#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})|[a-zA-Z]+)$/;
export function sanitizeColor(value: unknown): string | null {
  const str = String(value ?? '').trim();
  return COLOR_PATTERN.test(str) ? str : null;
}

export function formatListItems(
  items: {
    label: string;
    value: string | string[] | BooleanLike;
    formatter?: (val: boolean) => string;
    suffix?: string;
  }[],
): string {
  let result = '';
  items.forEach(({ label, value, formatter, suffix = '' }) => {
    // Formatter output is trusted (hardcoded spans). Raw values are escaped
    // by the caller before reaching here (untrusted backend free text) or
    // are already trusted HTML produced by the Get* helpers, so they are
    // interpolated as-is.
    const displayValue = formatter
      ? formatter(!!value)
      : Array.isArray(value)
        ? value.join(', ')
        : value;
    result += `<li class="list-group-item">${label}: ${displayValue}${suffix}</li>`;
  });
  return result;
}

export function formatListMessages(
  id: string,
  messages: string[] | null,
  isActive = false,
): string {
  const activeClass = isActive ? 'show active' : '';
  let result = `<div class="tab-pane fade ${activeClass}" id="${id}" role="messagesTabpanel">`;
  messages?.forEach((msg) => {
    result += `${escapeHtml(msg)}<br>`;
  });
  result += '</div>';
  return result;
}

export function formatListEmotes(sections: EmoteEntry[]): string {
  let result = '';
  sections.forEach(({ label, messages }) => {
    if (!messages?.length) return;
    result += `<details><summary>${label}:</summary><p>`;
    messages.forEach((msg) => {
      result += `${escapeHtml(msg)}<br>`;
    });
    result += '</p></details><br>';
  });
  return result;
}

export function getYesNo(val: boolean): string {
  return val
    ? '<span style="color: green;">Yes</span>'
    : '<span style="color: red;">No</span>';
}
