import { Box } from 'tgui-core/components';
import type { TradeStanding as Standing } from './types';

const signed = (value: number) => `${value > 0 ? '+' : ''}${value}%`;

const effectColor = (value: number) =>
  value > 0 ? 'good' : value < 0 ? 'bad' : 'label';

/** The three standing layers (station, department, trader) and what each does to a trader's prices. */
export const TradeStanding = (props: { standing: Standing }) => {
  const { standing } = props;
  return (
    <Box>
      {standing.layers.map((layer) => (
        <Box key={layer.layer}>
          {layer.label}: {layer.tier} ({layer.standing}){' '}
          <Box as="span" color={effectColor(layer.effect)}>
            {signed(layer.effect)}
          </Box>
        </Box>
      ))}
      <Box bold color={effectColor(standing.effect)}>
        Net: {signed(standing.effect)} in the station&apos;s favour on what it
        buys and sells
      </Box>
    </Box>
  );
};
