import type { ComponentProps } from 'react';
import { LabeledList, ProgressBar } from 'tgui-core/components';

type Props = ComponentProps<typeof ProgressBar> & {
  /** The row's label. */
  label: string;
};

/**
 * A labelled gauge row: a LabeledList item holding one ProgressBar. Takes the bar's props
 * (value, minValue, maxValue, ranges, color, children) beside the label, so a window states
 * only what the gauge reads.
 */
export function StatBar(props: Props) {
  const { label, ...bar } = props;
  return (
    <LabeledList.Item label={label}>
      <ProgressBar {...bar} />
    </LabeledList.Item>
  );
}
