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
} from 'react';
import { backendStateAtom } from './events/store';
import { LoadingScreen } from './interfaces/common/LoadingScreen';
import { Window } from './layouts';

// Lazy context: every interface ENTRY module is emitted as its own async chunk and
// only fetched when an interface of that name is actually opened. `.keys()` is still
// resolved synchronously at build time (the context map is static; only the *load*
// is deferred), so we keep the original chompstation→root path-fallback search.
//
// The regex matches ONLY routable entry shapes — `./Name.(tsx|jsx)`,
// `./Name/index.(tsx|jsx)`, and the `./chompstation/` variants (exactly what the
// path-builders below request). Nested submodules (e.g. `./PreferencesMenu/preferences/X.tsx`,
// everything under `./deepquarry/`) are deliberately excluded so they bundle INTO the
// entry chunk that statically imports them, making each interface chunk self-contained.
// That's what lets the DM side ship one chunk per opened interface with no dependency
// closure to track.
const requireInterface = require.context(
  './interfaces',
  true,
  /^\.\/(?!.*\.test\.)(chompstation\/)?[^/]+(\/index)?\.(tsx?|jsx?)$/,
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
      return <RoutingErrorWindow type="unknown" name={this.props.name} />;
    }
    return this.props.children;
  }
}

export function RoutedComponent() {
  const { suspended, config, debug } = useAtomValue(backendStateAtom);

  if (suspended) {
    return <SuspendedWindow />;
  }
  if (config.refreshing) {
    return <RefreshingWindow />;
  }

  if (process.env.NODE_ENV !== 'production') {
    if (debug.kitchenSink) {
      const KitchenSink = lazy(async () => {
        const mod = await import('./debug/KitchenSink');
        return { default: mod.KitchenSink };
      });
      return (
        <Suspense fallback={<RefreshingWindow />}>
          <KitchenSink />
        </Suspense>
      );
    }
  }

  const name = config?.interface?.name;
  if (!name) {
    return <RoutingErrorWindow type="notFound" name="(undefined)" />;
  }

  const Component = getRoutedComponent(name);

  return (
    <RouteErrorBoundary name={name}>
      <Suspense fallback={<RefreshingWindow />}>
        <Component />
      </Suspense>
    </RouteErrorBoundary>
  );
}
