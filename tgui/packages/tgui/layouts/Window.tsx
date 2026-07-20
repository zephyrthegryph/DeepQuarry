/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import {
  type ComponentProps,
  type PropsWithChildren,
  type ReactNode,
  useLayoutEffect,
  useState,
} from 'react';
import { UI_DISABLED, UI_INTERACTIVE } from 'tgui/constants';
import { type Box, KeyListener } from 'tgui-core/components';
import type { KeyEvent } from 'tgui-core/events';
import { KEY_ALT } from 'tgui-core/keycodes';
import { type BooleanLike, classes } from 'tgui-core/react';
import { decodeHtmlEntities } from 'tgui-core/string';
import { useBackend } from '../backend';
import {
  dragStartHandler,
  type ResolvedWindowGeometry,
  recallWindowGeometry,
  resizeStartHandler,
  setWindowKey,
  setWindowPosition,
  storeWindowGeometry,
} from '../drag';
import { suspendStart } from '../events/handlers/suspense';
import { createLogger } from '../logging';
import { profileStartup } from '../profiling/hooks';
import { profileTransition } from '../profiling/transitions';
import { claimReveal, revealWindow } from '../reveal';
import { Layout } from './Layout';
import { TitleBar } from './TitleBar';

const logger = createLogger('Window');
const DEFAULT_SIZE: [number, number] = [400, 600];

type Props = Partial<{
  buttons: ReactNode;
  canClose: BooleanLike;
  height: number;
  theme: string;
  title: string;
  width: number;
  fitted: boolean;
  scrollbars: boolean;
}> &
  PropsWithChildren;

export function Window(props: Props) {
  const {
    canClose = true,
    theme,
    title,
    children,
    buttons,
    width,
    height,
    fitted,
    scrollbars = true,
  } = props;

  const { config, suspended, debug } = useBackend();

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
      Byond.winset(Byond.windowId, { alpha: 0 });
    }
    Byond.winset(Byond.windowId, {
      'is-visible': false,
    });
    profileTransition('layout-hide-sent');
    if (!isReadyToRender) setIsReadyToRender(true);
  }, [config?.window?.native_shell]);

  const { scale } = config?.window || false;

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
            geometry = await recallWindowGeometry(options);
          }
        } catch (error) {
          logger.error('failed to resolve window geometry', error);
          geometry = options.size ? { size: options.size } : undefined;
        }
        if (cancelled) {
          return;
        }
        profileStartup('geometry_finished', config.interface?.name);
        await revealWindow(config.window?.generation, geometry);
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

  const fancy = config.window?.fancy;

  // Determine when to show dimmer
  const showDimmer =
    config.user &&
    (config.user.observer
      ? config.status < UI_DISABLED
      : config.status < UI_INTERACTIVE);

  return suspended ? null : (
    <Layout className="Window" theme={theme}>
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
        </TitleBar>
      )}
      <div
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

  const dragStartIfAltHeld = (event) => {
    if (altDown) {
      dragStartHandler(event);
    }
  };

  Byond.subscribeTo('resetposition', (payload) => {
    setWindowPosition([0, 0]);
    storeWindowGeometry();
  });
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
