/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { useAtomValue } from 'jotai';
import {
  Component,
  type ComponentType,
  type ErrorInfo,
  lazy,
  type ReactNode,
  Suspense,
  useEffect,
} from 'react';
import { backendStateAtom } from './events/store';
import { LoadingScreen } from './interfaces/common/LoadingScreen';
import { LobbyMenu } from './interfaces/LobbyMenu';
import { MediaPlayer } from './interfaces/MediaPlayer';
import { Window } from './layouts';
import { revealIfUnclaimed } from './reveal';

// EAGER interfaces — kept in the main bundle, never lazy-split. These are the
// interfaces the DM side opens with `open(preinitialized = TRUE)` (the lobby menu
// and the media player): persistent windows shown at login on a manually-initialized
// window. That open path doesn't re-initialize and can deliver its "update" before a
// lazily-fetched chunk has arrived, so a split version renders empty (just the Layout
// background). Bundling them eagerly removes the chunk-fetch dependency entirely.
// Resolved by name below, BEFORE the lazy context.
const EAGER_INTERFACES: Record<string, ComponentType<any>> = {
  LobbyMenu,
  MediaPlayer,
};

// Lazy context: every interface ENTRY module is emitted as its own async chunk and
// only fetched when an interface of that name is actually opened. `.keys()` is still
// resolved synchronously at build time (the context map is static; only the *load*
// is deferred), so we keep the original chompstation→root path-fallback search.
//
// The regex matches ONLY routable entry shapes — `./Name.(tsx|jsx)`,
// `./Name/index.(tsx|jsx)`, and the `./chompstation/` variants (exactly what the
// path-builders below request) — and EXCLUDES the eager interfaces above so they
// aren't also emitted as (unused) chunks. Nested submodules (e.g.
// `./PreferencesMenu/preferences/X.tsx`, everything under `./deepquarry/`) are
// excluded too, so they bundle INTO the entry chunk that statically imports them,
// making each interface chunk self-contained (one chunk per opened interface, no
// dependency closure for the DM side to track).
const requireInterface = require.context(
  './interfaces',
  true,
  /^\.\/(?!.*\.test\.)(?!(?:chompstation\/)?(?:LobbyMenu|MediaPlayer)(?:\/index)?\.(?:tsx?|jsx?)$)(chompstation\/)?[^/]+(\/index)?\.(tsx?|jsx?)$/,
  'lazy',
);

const availableKeys = new Set<string>(requireInterface.keys());

type RoutingErrorProps = {
  type: 'notFound' | 'missingExport' | 'unknown';
  name: string;
};

export function RoutingErrorWindow(props: RoutingErrorProps) {
  const { type, name } = props;

  return (
    <Window>
      <Window.Content scrollable>
        {type === 'notFound' && (
          <div>
            Interface <b>{name}</b> was not found.
          </div>
        )}
        {type === 'missingExport' && (
          <div>
            Interface <b>{name}</b> is missing an export.
          </div>
        )}
        {type === 'unknown' && <div>An unknown error has occurred.</div>}
      </Window.Content>
    </Window>
  );
}

// Displays an empty Window with scrollable content
function SuspendedWindow() {
  return (
    <Window>
      <Window.Content scrollable />
    </Window>
  );
}

// Displays a loading screen with a spinning icon. Doubles as the Suspense
// fallback shown for the brief moment an interface's chunk is being fetched.
function RefreshingWindow() {
  return (
    <Window title="Loading">
      <Window.Content>
        <LoadingScreen />
      </Window.Content>
    </Window>
  );
}

const pathBuilders: Array<(name: string) => string> = [
  // chompstation/ is searched first for fork-only interfaces.
  (name) => `./chompstation/${name}.tsx`,
  (name) => `./chompstation/${name}.jsx`,
  (name) => `./chompstation/${name}/index.tsx`,
  (name) => `./chompstation/${name}/index.jsx`,
  // Root interfaces (canonical location for all non-chompstation-only UIs).
  (name) => `./${name}.tsx`,
  (name) => `./${name}.jsx`,
  (name) => `./${name}/index.tsx`,
  (name) => `./${name}/index.jsx`,
];

// Resolve an interface name to its context module id (synchronous — keys are known
// at build time), honoring the same precedence as the old eager loader.
function resolveInterfacePath(name: string): string | null {
  for (const build of pathBuilders) {
    const path = build(name);
    if (availableKeys.has(path)) {
      return path;
    }
  }
  return null;
}

// Cache the lazy component per interface name so React.lazy's identity is stable
// across re-renders (otherwise React would unmount/remount and re-fetch every time).
const componentCache = new Map<string, ComponentType>();

function getRoutedComponent(name: string): ComponentType {
  // Eager interfaces are in the main bundle — return them directly, no lazy/Suspense.
  const eager = EAGER_INTERFACES[name];
  if (eager) {
    return eager;
  }

  const cached = componentCache.get(name);
  if (cached) {
    return cached;
  }

  const path = resolveInterfacePath(name);
  let Routed: ComponentType;

  if (!path) {
    Routed = () => <RoutingErrorWindow type="notFound" name={name} />;
  } else {
    Routed = lazy(async () => {
      const esModule = await requireInterface(path);
      const Resolved = esModule[name];
      if (!Resolved) {
        return {
          default: () => <RoutingErrorWindow type="missingExport" name={name} />,
        };
      }
      return { default: Resolved };
    });
  }

  componentCache.set(name, Routed);
  return Routed;
}

// Interfaces that manage their own window visibility (they winset is-visible
// themselves) and must NOT be auto-revealed by RevealWindow. Currently just the
// Tooltip — a transparent overlay shown/hidden by Tooltip.tsx based on hover state;
// revealing it on mount would flash its host element as an empty box over the map.
const SELF_MANAGED = new Set<string>(['Tooltip']);

// Route-level fallback reveal, run the moment the real interface content mounts
// (AFTER its lazy chunk has loaded). It reveals only interfaces that do NOT manage
// their own geometry — Pane-based UIs, the error/refreshing windows, and any
// interface not rooted in <Window>. A <Window> interface claims the reveal in its
// own effect (which fires first, child-before-parent) and reveals itself only
// after applying geometry, so revealIfUnclaimed() here stands down for it — that's
// what prevents the cold-open flash of the window at default size before it
// resizes. resume() (events/handlers/update.ts) keeps a delayed failsafe reveal.
function RevealWindow({ children }: { children: ReactNode }) {
  useEffect(() => {
    revealIfUnclaimed();
  }, []);
  return <>{children}</>;
}

// Catches errors thrown while loading or rendering a routed interface — most
// importantly a failed chunk fetch (e.g. the async chunk hadn't reached the BYOND
// cache yet) — and shows the standard error window instead of a blank page.
type RouteBoundaryProps = { name: string; children: ReactNode };
type RouteBoundaryState = { hasError: boolean };

class RouteErrorBoundary extends Component<
  RouteBoundaryProps,
  RouteBoundaryState
> {
  constructor(props: RouteBoundaryProps) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(): RouteBoundaryState {
    return { hasError: true };
  }

  componentDidUpdate(prevProps: RouteBoundaryProps) {
    // Reset when routing to a different interface so a prior failure doesn't
    // pin the error window for the next, unrelated interface.
    if (prevProps.name !== this.props.name && this.state.hasError) {
      this.setState({ hasError: false });
    }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // Surface to the console (picked up by the tgui logging/error pipeline). This is
    // the path a failed chunk fetch lands on, so make it visible rather than silent.
    console.error(`Interface "${this.props.name}" failed to load:`, error, info);
  }

  render() {
    if (this.state.hasError) {
      // Reveal the error window — the failed content never mounted to reveal itself.
      return (
        <RevealWindow>
          <RoutingErrorWindow type="unknown" name={this.props.name} />
        </RevealWindow>
      );
    }
    return this.props.children;
  }
}

export function RoutedComponent() {
  const { suspended, config, debug } = useAtomValue(backendStateAtom);

  // Suspended → render an empty window and DON'T reveal it (it should stay hidden).
  if (suspended) {
    return <SuspendedWindow />;
  }
  if (config.refreshing) {
    return (
      <RevealWindow>
        <RefreshingWindow />
      </RevealWindow>
    );
  }

  if (process.env.NODE_ENV !== 'production') {
    if (debug.kitchenSink) {
      const KitchenSink = lazy(async () => {
        const mod = await import('./debug/KitchenSink');
        return { default: mod.KitchenSink };
      });
      return (
        <Suspense fallback={null}>
          <RevealWindow>
            <KitchenSink />
          </RevealWindow>
        </Suspense>
      );
    }
  }

  const name = config?.interface?.name;
  if (!name) {
    return (
      <RevealWindow>
        <RoutingErrorWindow type="notFound" name="(undefined)" />
      </RevealWindow>
    );
  }

  const Component = getRoutedComponent(name);

  // The Suspense fallback is null (not a <Window>): while the interface chunk loads,
  // nothing is rendered and the host window stays as the DM left it (hidden for pooled
  // windows). The window is revealed by <RevealWindow> only once the real content
  // mounts — except for SELF_MANAGED interfaces (Tooltip), which winset their own
  // is-visible and must not be auto-revealed (doing so flashes an empty overlay box).
  const content = (
    <RouteErrorBoundary name={name}>
      <Suspense fallback={null}>
        {SELF_MANAGED.has(name) ? (
          <Component />
        ) : (
          <RevealWindow>
            <Component />
          </RevealWindow>
        )}
      </Suspense>
    </RouteErrorBoundary>
  );

  return content;
}
