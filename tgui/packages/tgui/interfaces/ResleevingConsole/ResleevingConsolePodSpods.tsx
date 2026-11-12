import { resolveAsset } from 'tgui/assets';
import { useBackend } from 'tgui/backend';
import { Box, Button, Icon, Image } from 'tgui-core/components';
import type { ResleevingConsoleActions } from '../generated/ResleevingConsole';
import type { Data } from './types';

export const ResleevingConsolePodSpods = (props) => {
  const { act, data } = useBackend<Data, ResleevingConsoleActions>();
  const { spods, selected_printer } = data;

  if (spods?.length) {
    return spods.map((pod, i) => {
      const podAction = (
        <Button
          selected={selected_printer === pod.spod}
          icon={selected_printer === pod.spod && 'check'}
          mt="0.5rem"
          onClick={() =>
            act('selectprinter', {
              ref: pod.spod,
            })
          }
        >
          Select
        </Button>
      );

      return (
        <Box key={i} width="64px" textAlign="center" inline mr="0.5rem">
          <Image
            src={resolveAsset(`synthprinter${pod.busy ? '_working' : ''}.gif`)}
            style={{
              width: '100%',
            }}
          />
          <Box color="label">{pod.name}</Box>
          <Box bold color={pod.steel >= 15000 ? 'good' : 'bad'} inline>
            <Icon name={pod.steel >= 15000 ? 'circle' : 'circle-o'} />
            &nbsp;
            {pod.steel}
          </Box>
          <Box bold color={pod.glass >= 15000 ? 'good' : 'bad'} inline>
            <Icon name={pod.glass >= 15000 ? 'circle' : 'circle-o'} />
            &nbsp;
            {pod.glass}
          </Box>
          {podAction}
        </Box>
      );
    });
  }

  return '';
};
