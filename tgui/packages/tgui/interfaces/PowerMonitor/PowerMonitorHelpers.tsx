import { memo } from 'react';
import { Box, ColorBox, Icon } from 'tgui-core/components';

export const AreaCharge = memo(
  (props: { charging: number; charge: number }) => {
    const { charging, charge } = props;
    return (
      <>
        <Icon
          width="18px"
          textAlign="center"
          name={
            (charging === 0 &&
              (charge > 50 ? 'battery-half' : 'battery-quarter')) ||
            (charging === 1 && 'bolt') ||
            (charging === 2 && 'battery-full') ||
            ''
          }
          color={
            (charging === 0 && (charge > 50 ? 'yellow' : 'red')) ||
            (charging === 1 && 'yellow') ||
            (charging === 2 && 'green')
          }
        />
        <Box inline width="36px" textAlign="right">
          {`${charge.toFixed()}%`}
        </Box>
      </>
    );
  },
);

export const AreaStatusColorBox = memo((props: { status: number }) => {
  const { status } = props;
  const power: boolean = Boolean(status & 2);
  const mode: boolean = Boolean(status & 1);
  const tooltipText: string = `${power ? 'On' : 'Off'} [${mode ? 'auto' : 'manual'}]`;
  // A native title is sufficient for a two-word status hint. A full floating-ui
  // Tooltip installs effects and positioning state; three of them per APC made a
  // large grid create hundreds of controllers on every Power Monitor update.
  return (
    <span title={tooltipText}>
      <ColorBox
        color={power ? 'good' : 'bad'}
        content={mode ? undefined : 'M'}
      />
    </span>
  );
});
