/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { createUuid } from 'tgui-core/uuid';

import { MESSAGE_TYPE_INTERNAL, MESSAGE_TYPES } from './constants';
import type { Page, SerializedMessage } from './types';

export function canPageAcceptType(page: Page, type: string): boolean {
  return type.startsWith(MESSAGE_TYPE_INTERNAL) || page.acceptedTypes[type];
}

export function typeIsImportant(type: string): boolean {
  let isImportant = false;
  for (const typeDef of MESSAGE_TYPES) {
    if (typeDef.type === type && typeDef.important) {
      isImportant = true;
      break;
    }
  }
  return isImportant;
}

export function adminPageOnly(page: Page): boolean {
  let adminTab = true;
  let checked = 0;
  for (const typeDef of MESSAGE_TYPES) {
    if (
      page.acceptedTypes[typeDef.type] &&
      !(!!typeDef.important || !!typeDef.admin)
    ) {
      adminTab = false;
      break;
    }
    if (page.acceptedTypes[typeDef.type] && !typeDef.important) {
      checked++;
    }
  }
  return checked > 0 && adminTab;
}

export function canStoreType(
  storedTypes: Record<string, boolean>,
  type: string,
) {
  return storedTypes[type];
}

export function createPage(obj: Record<string, unknown> = {}): Page {
  const acceptedTypes = {};

  for (const typeDef of MESSAGE_TYPES) {
    acceptedTypes[typeDef.type] = !!typeDef.important;
  }

  return {
    isMain: false,
    id: createUuid(),
    name: 'New Tab',
    acceptedTypes,
    unreadCount: 0,
    hideUnreadCount: false,
    createdAt: Date.now(),
    ...obj,
  };
}

export function createMainPage(): Page {
  const acceptedTypes = {};
  for (const typeDef of MESSAGE_TYPES) {
    acceptedTypes[typeDef.type] = true;
  }
  return createPage({
    id: 'main',
    isMain: true,
    name: 'Main',
    acceptedTypes,
  });
}

export function createMessage(
  payload: Record<string, unknown>,
): SerializedMessage {
  return {
    createdAt: Date.now(),
    ...payload,
  } as SerializedMessage;
}

export function serializeMessage(
  message: SerializedMessage,
  archive = false,
): SerializedMessage {
  let archiveM = '';
  if (archive && message.node && typeof message.node !== 'string') {
    archiveM = message.node.outerHTML.replace(/(?:\r\n|\r|\n)/g, '<br>');
  }
  return {
    type: message.type,
    text: message.text,
    html: archive ? archiveM : message.html,
    times: message.times,
    createdAt: message.createdAt,
    roundId: message.roundId,
  };
}

export function isSameMessage(
  a: SerializedMessage,
  b: SerializedMessage,
): boolean {
  return (
    (typeof a.text === 'string' && a.text === b.text) ||
    (typeof a.html === 'string' && a.html === b.html)
  );
}

/**
 * A reordered tab list, or null when it is not a permutation of `pages`. Any
 * tab may move, the main one included; the order is saved with the pages.
 */
export function reorderedPages(
  pages: string[],
  order: string[],
): string[] | null {
  if (order.length !== pages.length) return null;
  const seen = new Set(order);
  if (seen.size !== pages.length || pages.some((id) => !seen.has(id))) {
    return null;
  }
  return order;
}

/** Whether `page` shows a message of `type`: the renderer's own test (an admin-only page may hide important messages). */
export function pageShowsType(
  page: Page,
  type: string,
  hideImportantInAdminTab: boolean,
): boolean {
  return (
    canPageAcceptType(page, type) &&
    !(adminPageOnly(page) && typeIsImportant(type) && hideImportantInAdminTab)
  );
}

/**
 * New unread counts per page id for a processed batch. A message counts as
 * unread on a page that shows it only when the player has not already seen it:
 * one the tab being viewed showed (scrolled to the bottom) is seen everywhere.
 * While the viewed tab is scrolled up, its own new messages count on it alone.
 */
export function unreadAfterBatch(
  pages: readonly string[],
  pagesById: Record<string, Page>,
  currentPageId: string,
  scrollTracking: boolean,
  countByType: Record<string, number>,
  hideImportantInAdminTab: boolean,
): Record<string, number> {
  const current = pagesById[currentPageId];
  const added: Record<string, number> = {};
  for (const pageId of pages) {
    const page = pagesById[pageId];
    if (!page) continue;
    let count = 0;
    for (const type in countByType) {
      if (!pageShowsType(page, type, hideImportantInAdminTab)) continue;
      const shownOnCurrent =
        !!current && pageShowsType(current, type, hideImportantInAdminTab);
      if (pageId === currentPageId) {
        if (scrollTracking) continue;
      } else if (shownOnCurrent) {
        // The player has it in front of them on the viewed tab (or will, when they scroll down there).
        continue;
      }
      count += countByType[type];
    }
    if (count > 0) added[pageId] = count;
  }
  return added;
}
