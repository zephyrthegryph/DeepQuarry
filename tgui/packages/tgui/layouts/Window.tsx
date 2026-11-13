/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import {
  type ComponentProps,
  type PropsWithChildren,
  type ReactNode,
  useContext,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import { UI_DISABLED, UI_INTERACTIVE } from 'tgui/constants';
import { type Box, Button, KeyListener } from 'tgui-core/components';
import type { KeyEvent } from 'tgui-core/events';
import { KEY_ALT } from 'tgui-core/keycodes';
import { type BooleanLike, classes } from 'tgui-core/react';
import { decodeHtmlEntities } from 'tgui-core/string';
import { useBackend } from '../backend';
import {
  dragStartHandler,
  growWindowHeight,
  type ResolvedWindowGeometry,
  recallWindowGeometry,
  resizeStartHandler,
  setWindowKey,
  setWindowPosition,
  storeWindowGeometry,
} from '../drag';
import { EmbeddedContext } from '../embedded';
import { suspendStart } from '../events/handlers/suspense';
import { parseFloatAt, underPointer } from '../floatPlacement';
import { createLogger } from '../logging';
import { profileStartup } from '../profiling/hooks';
import { profileTransition } from '../profiling/transitions';
import { claimReveal, isProfiling, revealWindow, traceAlpha } from '../reveal';
import { getStaticWindowGeometry } from '../windowGeometry';
import { resolveTheme, useConsoleScanlines } from './consoleTheme';
import { fitOverflow, measureNaturalBottom } from './fitWindow';
import { Layout } from './Layout';
import { TitleBar } from './TitleBar';

const logger = createLogger('Window');
const DEFAULT_SIZE: [number, number] = [400, 600];
let resetPositionSubscribed = false;

function parsePreappliedGeometry(geometry?: {
  pos?: string;
  size?: string;
}): ResolvedWindowGeometry | undefined {
  const size = geometry?.size?.match(/^(\d+)x(\d+)$/);
  const pos = geometry?.pos?.match(/^(-?\d+),(-?\d+)$/);
  if (!size || !pos) return;
  return {
    size: [Number(size[1]), Number(size[2])],
    pos: [Number(pos[1]), Number(pos[2])],
  };
}

let floatDoneSubscribed = false;

/** The column page finished a live drag of this window (it floated with the button down): its place is kept like any other drag's. */
function ensureFloatDoneSubscription(): void {
  if (floatDoneSubscribed) return;
  floatDoneSubscribed = true;
  Byond.subscribeTo('floatdone', () => {
    logger.log('live float drag done, storing geometry');
    storeWindowGeometry();
  });
}

function ensureResetPositionSubscription(): void {
  if (resetPositionSubscribed) return;
  resetPositionSubscribed = true;
  Byond.subscribeTo('resetposition', () => {
    setWindowPosition([0, 0]);
    storeWindowGeometry();
  });
}

type Props = Partial<{
  buttons: ReactNode;
  canClose: BooleanLike;
  height: number;
  theme: string;
  title: string;
  width: number;
  fitted: boolean;
  /** Grow the window until all of its content shows (see fitWindow.ts). */
  fitContent: boolean;
  scrollbars: boolean;
}> &
  PropsWithChildren;

/**
 * A tgui window. In its own native window it is the full frame (title bar,
 * geometry, reveal, resize); embedded in the right-hand column's page
 * (EmbeddedInterface) it is only its content, and the column's window manager
 * draws the frame, as it does for the chat and the stat panel.
 */
export function Window(props: Props) {
  return useContext(EmbeddedContext) ? (
    <EmbeddedWindow {...props} />
  ) : (
    <NativeWindow {...props} />
  );
}

function EmbeddedWindow(props: Props) {
  const { theme, children } = props;
  const { config } = useBackend();
  // No useConsoleScanlines: it sets a page-wide variable, and the column page keeps its own.
  const showDimmer =
    config.user &&
    (config.user.observer
      ? config.status < UI_DISABLED
      : config.status < UI_INTERACTIVE);
  const readOnly = !!config.user?.observer && config.status < UI_INTERACTIVE;
  return (
    <Layout
      className={classes([
        'Window',
        'Window--embedded',
        readOnly && 'Window--readonly',
      ])}
      theme={theme}
    >
      <div className="Window__rest">
        {children}
        {showDimmer && <div className="Window__dimmer" />}
      </div>
    </Layout>
  );
}

function NativeWindow(props: Props) {
  const {
    canClose = true,
    theme,
    title,
    children,
    buttons,
    width: requestedWidth,
    height: requestedHeight,
    fitted,
    fitContent,
    scrollbars = true,
  } = props;

  const { config, suspended, debug } = useBackend();
  useConsoleScanlines(resolveTheme(theme));
  const defaultGeometry = getStaticWindowGeometry(config?.interface?.name);
  const width = requestedWidth ?? defaultGeometry?.width;
  const height = requestedHeight ?? defaultGeometry?.height;

  // Native pooled shells are hidden by the server before their payload is sent,
  // so they can apply geometry in the first commit. Legacy windows retain the
  // defensive second commit after the browser itself has issued the hide.
  const [isReadyToRender, setIsReadyToRender] = useState(
    Boolean(config?.window?.native_shell),
  );

  // We need to set the window to be invisible before we can set its geometry
  // Otherwise, we get a flicker effect when the window is first rendered
  useLayoutEffect(() => {
    // Claim during the layout-effect phase, before the route wrapper's passive
    // effect can perform its no-geometry fallback reveal.
    claimReveal();
    profileTransition('layout-hide-start');
    if (config?.window?.native_shell) {
      traceAlpha(0, 'layout-hide');
      Byond.winset(Byond.windowId, { alpha: 0 });
    }
    Byond.winset(Byond.windowId, {
      'is-visible': false,
    });
    profileTransition('layout-hide-sent');
    if (!isReadyToRender) setIsReadyToRender(true);
  }, [config?.window?.native_shell]);

  useEffect(ensureFloatDoneSubscription, []);

  const { scale } = config?.window || false;
  // A float out of the column comes with one update (float_at); the next update clears it, and that must not cancel the
  // placement of the reveal already under way. Held here until a reveal uses it.
  const pendingFloat = useRef<string | null>(null);
  if (config.window?.float_at) {
    pendingFloat.current = config.window.float_at;
  }

  useLayoutEffect(() => {
    let cancelled = false;
    if (!suspended && isReadyToRender) {
      const updateGeometry = async () => {
        profileStartup('geometry_started', config.interface?.name);
        const options = {
          ...config.window,
          size: DEFAULT_SIZE,
        };

        if (width && height) {
          options.size = [width, height];
        }
        if (config.window?.key) {
          setWindowKey(config.window.key);
        }
        // Apply size/position BEFORE revealing — awaited so the window never
        // paints at default geometry first and then resizes (cold-open flicker).
        // try/finally: if the geometry recall throws, the window must STILL
        // reveal — the resume() failsafe only covers previously-suspended
        // windows, so a fresh window would otherwise stay invisible forever.
        let geometry: ResolvedWindowGeometry | undefined;
        try {
          if (!fitted) {
            geometry = await recallWindowGeometry(
              options,
              parsePreappliedGeometry(config.window?.preapplied_geometry),
            );
          }
        } catch (error) {
          logger.error('failed to resolve window geometry', error);
          geometry = options.size ? { size: options.size } : undefined;
        }
        if (cancelled) {
          return;
        }
        const float = pendingFloat.current;
        const kept = parseFloatAt(float)?.size ?? null;
        if (kept) {
          // It keeps the size it had in the column, not its saved or default floating size.
          logger.log(
            'floated from the dock keeping its size',
            kept,
            geometry?.size,
          );
          geometry = { ...geometry, size: kept };
        }
        const under = underPointer(float, geometry?.size);
        if (under) {
          // Pulled out of the dock: it opens under the pointer, as a popped-out chat does.
          geometry = { ...geometry, pos: under };
          logger.log('floated from the dock under the pointer', under);
        }
        profileStartup('geometry_finished', config.interface?.name);
        // Every floating reveal is traced (while profiling), not only a pull-out: a saved floating window at login comes this way too.
        floatTrace('reveal-start', {
          iface: config.interface?.name,
          at: float,
          under,
          geometry,
          screen: [window.screen.width, window.screen.height],
          dpr: window.devicePixelRatio,
        });
        const revealed = await revealWindow(
          config.window?.generation,
          geometry,
        );
        floatTrace('reveal-done', { revealed });
        void floatTraceNative();
        if (float) {
          pendingFloat.current = null;
          // Tells the column page this window is up, so a drag still going on moves it (wm/floated).
          Byond.sendMessage('wm/floated', { window: Byond.windowId });
        }
        if (under) {
          // Remembered, so the next geometry recall (float_at is sent once) keeps it there.
          storeWindowGeometry();
        }
        logger.log('set to visible');
      };

      Byond.winset(Byond.windowId, {
        'can-close': Boolean(canClose),
      });
      logger.log('mounting');

      updateGeometry();
    }
    return () => {
      cancelled = true;
      logger.log('unmounting');
    };
  }, [
    canClose,
    config.interface?.name,
    config.window?.generation,
    config.window?.key,
    config.window?.locked,
    fitted,
    height,
    isReadyToRender,
    scale,
    suspended,
    width,
  ]);

  const restRef = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const rest = restRef.current;
    if (!fitContent || !rest || suspended) {
      return;
    }
    const fit = () => {
      const root =
        rest.querySelector<HTMLElement>('.Window__contentPadding') ?? rest;
      const grow = fitOverflow(measureNaturalBottom(root), window.innerHeight);
      if (grow > 0) {
        growWindowHeight(grow);
      }
    };
    fit();
    const observer = new ResizeObserver(fit);
    observer.observe(rest);
    for (const child of Array.from(rest.children)) {
      observer.observe(child);
    }
    return () => observer.disconnect();
  }, [fitContent, suspended, isReadyToRender]);

  const fancy = config.window?.fancy;
  const dockable = !!config.window?.dockable;

  // Determine when to show dimmer
  const showDimmer =
    config.user &&
    (config.user.observer
      ? config.status < UI_DISABLED
      : config.status < UI_INTERACTIVE);

  // A ghost's view of an op's window is read-only (F3): the server refuses every ui_act from an observer, and the one shared place that shows it is
  // here: every button, input and dropdown in the window renders disabled (Window.scss, .Window--readonly).
  const readOnly = !!config.user?.observer && config.status < UI_INTERACTIVE;

  return suspended ? null : (
    <Layout
      className={classes(['Window', readOnly && 'Window--readonly'])}
      theme={theme}
    >
      {!fitted && (
        <TitleBar
          className="Window__titleBar"
          title={title || decodeHtmlEntities(config.title)}
          status={config.status}
          fancy={fancy}
          onDragStart={dragStartHandler}
          onClose={suspendStart}
          canClose={canClose}
        >
          {buttons}
          {dockable && (
            <Button
              icon="table-columns"
              tooltip="Dock in the side panel"
              tooltipPosition="bottom-start"
              color="transparent"
              onClick={() => Byond.sendMessage('wm/dock')}
            />
          )}
        </TitleBar>
      )}
      <div
        ref={restRef}
        className={classes([
          'Window__rest',
          !fitted && 'Window__restwithTitlebar',
          debug.debugLayout && 'debug-layout',
        ])}
      >
        {!suspended && children}
        {showDimmer && <div className="Window__dimmer" />}
      </div>
      {fancy && scrollbars && (
        <>
          <div
            className="Window__resizeHandle__e"
            onMouseDown={resizeStartHandler(1, 0) as any}
          />
          <div
            className="Window__resizeHandle__s"
            onMouseDown={resizeStartHandler(0, 1) as any}
          />
          <div
            className="Window__resizeHandle__se"
            onMouseDown={resizeStartHandler(1, 1) as any}
          />
        </>
      )}
    </Layout>
  );
}

type ContentProps = Partial<{
  className: string;
  fitted: boolean;
  scrollable: boolean;
  vertical: boolean;
}> &
  ComponentProps<typeof Box> &
  PropsWithChildren;

function WindowContent(props: ContentProps) {
  const { className, fitted, children, ...rest } = props;
  const [altDown, setAltDown] = useState(false);

  useEffect(ensureResetPositionSubscription, []);

  const dragStartIfAltHeld = (event) => {
    if (altDown) {
      dragStartHandler(event);
    }
  };

  return (
    <Layout.Content
      onMouseDown={dragStartIfAltHeld}
      className={classes(['Window__content', className])}
      {...rest}
    >
      <KeyListener
        onKeyDown={(e: KeyEvent) => {
          if (KEY_ALT === e.code) {
            setAltDown(true);
            logger.log(`alt on ${altDown}`);
          }
        }}
        onKeyUp={(e: KeyEvent) => {
          if (KEY_ALT === e.code) {
            setAltDown(false);
            logger.log(`alt off ${altDown}`);
          }
        }}
      />

      {(fitted && children) || (
        <div className="Window__contentPadding">{children}</div>
      )}
    </Layout.Content>
  );
}

Window.Content = WindowContent;

/**
 * The window place that puts a screen point ("x,y", physical px) on the
 * middle of the window's titlebar, or null when there is no point.
 */
/** One step of a float's reveal, in the server's tgui log: a float that never shows is diagnosed from these. */
function floatTrace(step: string, detail: Record<string, unknown>): void {
  if (!isProfiling()) return;
  Byond.sendMessage('wm/log', {
    float: step,
    window: Byond.windowId,
    ...detail,
  });
}

/** What the client says the window is after the reveal, sampled so a later change shows (trace only: nothing acts on it). */
async function floatTraceNative(): Promise<void> {
  if (!isProfiling()) return;
  let elapsed = 0;
  for (const at of [0, 50, 500, 2000]) {
    await new Promise((resolve) => setTimeout(resolve, at - elapsed));
    elapsed = at;
    try {
      const state = await Byond.winget(Byond.windowId, [
        'is-visible',
        'alpha',
        'pos',
        'size',
        'is-minimized',
      ]);
      floatTrace('native-after-reveal', { after_ms: at, state });
    } catch (error) {
      floatTrace('native-query-failed', { error: String(error) });
    }
  }
}
