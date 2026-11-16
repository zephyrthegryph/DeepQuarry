import { Label } from 'tgui/components/Label';
import { Box, Stack } from 'tgui-core/components';

export const formatUnits = (a) => `${a} unit${a === 1 ? '' : 's'}`;

/**
 * Displays a beaker's contents. A row flagged `contaminant` is an impurity: drawn
 * grey (the server lists them after the real chemicals).
 * @property {object} props
 */
export const BeakerContents = (props) => {
  const { beakerLoaded, beakerContents = [], buttons } = props;
  return (
    <Box>
      {(!beakerLoaded && <Label>No beaker loaded.</Label>) ||
        (beakerContents.length === 0 && <Label>Beaker is empty.</Label>)}
      {beakerContents.map((chemical, i) => (
        <Box key={i} width="100%">
          <Stack align="center" justify="space-between">
            <Stack.Item color={chemical.contaminant ? 'grey' : 'label'}>
              {formatUnits(chemical.volume)} of {chemical.name}
            </Stack.Item>
            {!!buttons && <Stack.Item>{buttons(chemical, i)}</Stack.Item>}
          </Stack>
        </Box>
      ))}
    </Box>
  );
};
