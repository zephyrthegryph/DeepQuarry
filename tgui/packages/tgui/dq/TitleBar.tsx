/**
 * The DQ title bar: a name, an optional subtitle line under it, row-end
 * content and an optional boxed close button, on a 2px bottom rule. The
 * right-click menu and the stat panel's Inspect tab wear it.
 * Styles: tgui/styles/dq/titlebar.scss.
 */

import type { ReactNode } from 'react';
import { classes } from 'tgui-core/react';

type Props = {
  title: ReactNode;
  subtitle?: ReactNode;
  /** Shows the close button. */
  onClose?: () => void;
  className?: string;
  /** Before the close button (small buttons, a status). */
  children?: ReactNode;
};

export function TitleBar(props: Props) {
  const { title, subtitle, onClose, className, children } = props;
  return (
    <div className={classes(['DqTitleBar', className])}>
      <div className="DqTitleBar__heading">
        <div className="DqTitleBar__title">{title}</div>
        {subtitle !== undefined && subtitle !== null && subtitle !== '' && (
          <div className="DqTitleBar__subtitle">{subtitle}</div>
        )}
      </div>
      {children}
      {onClose && <CloseButton onClick={onClose} />}
    </div>
  );
}

/** The boxed close button of a DQ title bar or floating panel. */
export function CloseButton(props: { onClick: () => void; title?: string }) {
  return (
    <button
      type="button"
      className="DqCloseButton"
      title={props.title ?? 'Close'}
      onClick={props.onClick}
    >
      ×
    </button>
  );
}
