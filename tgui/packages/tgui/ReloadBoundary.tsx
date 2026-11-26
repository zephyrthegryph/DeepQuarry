import { Component, type ErrorInfo, Fragment, type ReactNode } from 'react';
import { Button } from 'tgui-core/components';
import { errorText, reportUiError } from './errors';

/** A second failure this soon after a reload shows the error screen; a later one is a new first failure. */
export const RELOAD_FAILS_WITHIN_MS = 1000;

type Props = {
  /** Named in the report and the error screen. */
  name: string;
  /** A new value starts over (another interface, another view). */
  resetKey?: string;
  /** Runs before an automatic or manual reload: drop anything that would fail the same way. */
  onReload?: () => void;
  /** The error screen, in place of the default. */
  renderError?: (message: string, reload: () => void) => ReactNode;
  children: ReactNode;
};

type State = {
  failed: boolean;
  screen: string | null;
  mount: number;
  key: string | undefined;
};

/**
 * Every tgui window's content, floating or docked, sits in one of these. A crash reloads the content once; failing again within a
 * second of that shows the error screen, with the error's text and a Reload button.
 */
export class ReloadBoundary extends Component<Props, State> {
  state: State = {
    failed: false,
    screen: null,
    mount: 0,
    key: this.props.resetKey,
  };

  private reloadedAt: number | null = null;

  static getDerivedStateFromError(): Partial<State> {
    return { failed: true };
  }

  static getDerivedStateFromProps(props: Props, state: State) {
    if (props.resetKey === state.key) return null;
    return { failed: false, screen: null, key: props.resetKey };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    const { name } = this.props;
    console.error(`"${name}" failed`, error, info);
    const now = Date.now();
    const failedAgain =
      this.reloadedAt !== null &&
      now - this.reloadedAt <= RELOAD_FAILS_WITHIN_MS;
    reportUiError({
      kind: error?.name === 'ChunkLoadError' ? 'chunk' : 'render',
      name,
      error,
      component: info?.componentStack,
      outcome: failedAgain ? 'error-screen' : 'retried',
    });
    if (failedAgain) {
      this.setState({ screen: errorText(error) });
    } else {
      this.reload();
    }
  }

  reload = () => {
    this.reloadedAt = Date.now();
    this.props.onReload?.();
    this.setState((state) => ({
      failed: false,
      screen: null,
      mount: state.mount + 1,
    }));
  };

  render() {
    const { screen, failed, mount } = this.state;
    const { name, renderError, children } = this.props;
    if (screen !== null) {
      return renderError ? (
        renderError(screen, this.reload)
      ) : (
        <ErrorScreen name={name} message={screen} reload={this.reload} />
      );
    }
    if (failed) return null;
    return <Fragment key={mount}>{children}</Fragment>;
  }
}

export function ErrorScreen(props: {
  name: string;
  message: string;
  reload: () => void;
}) {
  const { name, message, reload } = props;
  return (
    <div style={{ padding: '8px', color: 'var(--color-bad, #d33)' }}>
      <div>
        {name} failed: {message}
      </div>
      <Button onClick={reload}>Reload</Button>
    </div>
  );
}
