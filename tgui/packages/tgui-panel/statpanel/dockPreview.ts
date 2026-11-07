import { previewBox } from '../layout/model';

const PREVIEW_ID = 'dock-preview';

/**
 * The dock preview in the stat panel (layout/preview from the chat page,
 * relayed as dock/preview): while the floating chat is dragged over the column
 * this outlines the part of the column the chat would take if dropped now.
 * `payload.side` is 'top' or 'bottom', null clears it.
 */
export function applyDockPreview(payload: unknown): void {
  const { side, share } = (payload ?? {}) as {
    side?: unknown;
    share?: unknown;
  };
  let node = document.getElementById(PREVIEW_ID);
  if (side !== 'top' && side !== 'bottom') {
    node?.remove();
    return;
  }
  if (!node) {
    node = document.createElement('div');
    node.id = PREVIEW_ID;
    Object.assign(node.style, {
      position: 'fixed',
      left: '0',
      right: '0',
      zIndex: '9999',
      pointerEvents: 'none',
      boxSizing: 'border-box',
      border: '3px dashed #8dc0ff',
      background: 'rgba(141, 192, 255, 0.22)',
      boxShadow: 'inset 0 0 18px rgba(141, 192, 255, 0.6)',
    });
    document.body.appendChild(node);
  }
  const box = previewBox(side, Number(share));
  node.style.top = `${box.top}%`;
  node.style.height = `${box.height}%`;
  console.log('statpanel: dock preview', { side, share, box });
}
