/**
 * The DQ list row: one full-width console button per choice (a `> name` row
 * with an optional key or value at its end), or, with `blocked`, a greyed
 * row that says why it cannot be chosen. The right-click menu's rows.
 * Styles: tgui/styles/dq/list-row.scss.
 */

import type { ReactNode } from 'react';
import { classes } from 'tgui-core/react';

type Props = {
  children: ReactNode;
  /** At the row's end: a key binding, a count, a value. */
  trailing?: ReactNode;
  /** Hover text. */
  title?: string;
  onClick?: () => void;
  /** The row cannot be chosen; the reason, if any, follows its name. */
  blocked?: boolean;
  reason?: string;
  className?: string;
};

export function ListRow(props: Props) {
  const { children, trailing, title, onClick, blocked, reason, className } =
    props;
  if (blocked) {
    return (
      <div
        className={classes(['DqListRow', 'DqListRow--blocked', className])}
        title={title}
      >
        {children}
        {!!reason && <span className="DqListRow__reason">{reason}</span>}
      </div>
    );
  }
  return (
    <button
      type="button"
      className={classes(['DqListRow', className])}
      title={title}
      onClick={onClick}
    >
      <span>{children}</span>
      {trailing !== undefined && trailing !== null && trailing !== '' && (
        <span className="DqListRow__trailing">{trailing}</span>
      )}
    </button>
  );
}

/** A column of list rows with the console spacing. */
export function ListRows(props: { children: ReactNode; className?: string }) {
  return (
    <div className={classes(['DqListRows', props.className])}>
      {props.children}
    </div>
  );
}
