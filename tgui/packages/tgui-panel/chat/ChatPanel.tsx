/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { useAtom, useAtomValue } from 'jotai';
import { useEffect, useRef } from 'react';
import { Button } from 'tgui-core/components';
import {
  chatPagesRecordAtom,
  currentPageIdAtom,
  scrollTrackingAtom,
} from './atoms';
import { chatRenderer } from './renderer';
import type { Page } from './types';

type Props = {
  fontSize?: string;
  lineHeight: string | number;
};

export function ChatPanel(props: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const scrollTracking = useAtomValue(scrollTrackingAtom);
  // Page stuff
  const currentPageId = useAtomValue(currentPageIdAtom);
  const [pagesRecord, setPagesRecord] = useAtom(chatPagesRecordAtom);

  /** Mounts the renderer */
  useEffect(() => {
    if (ref.current) {
      chatRenderer.mount(ref.current);
    }
  }, []);

  /**
   * Keeps a pinned chat at the newest line while the window is resized. A
   * plain DOM write once per frame: no state, no render, no measuring.
   */
  useEffect(() => {
    let frame = 0;
    const stick = () => {
      frame = 0;
      if (chatRenderer.scrollTracking) {
        chatRenderer.scrollToBottom();
      }
    };
    const onResize = () => {
      if (!frame) {
        frame = requestAnimationFrame(stick);
      }
    };
    window.addEventListener('resize', onResize, { passive: true });
    return () => {
      window.removeEventListener('resize', onResize);
      if (frame) {
        cancelAnimationFrame(frame);
      }
    };
  }, []);

  /** Resets unread count when scroll tracking is enabled */
  useEffect(() => {
    if (scrollTracking) {
      const draft: Page = {
        ...pagesRecord[currentPageId],
        unreadCount: 0,
      };

      setPagesRecord({
        ...pagesRecord,
        [currentPageId]: draft,
      });
    }
  }, [scrollTracking]);

  /** Updates the style of the chat panel */
  useEffect(() => {
    chatRenderer.assignStyle({
      width: '100%',
      'max-width': '100%',
      // pre-wrap alone keeps an unbroken run of characters (a URL, a pasted
      // string) on one line, which widens the pane past the window.
      'overflow-wrap': 'anywhere',
      'white-space': 'pre-wrap',
      'font-size': props.fontSize,
      'line-height': props.lineHeight,
    });
  }, [props.fontSize, props.lineHeight]);

  return <div className="Chat" ref={ref} />;
}

/**
 * The button that jumps back to the newest line. Rendered by the panel inside
 * the message area (outside the scrolling content), so it floats over the
 * messages and never over the input row below them.
 */
export function ScrollToBottom() {
  const scrollTracking = useAtomValue(scrollTrackingAtom);
  if (scrollTracking) {
    return null;
  }
  return (
    <Button
      className="Chat__scrollButton"
      icon="arrow-down"
      onClick={() => chatRenderer.scrollToBottom()}
    >
      Scroll to bottom
    </Button>
  );
}
