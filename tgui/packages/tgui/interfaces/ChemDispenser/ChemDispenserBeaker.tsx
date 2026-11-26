import { useBackend } from 'tgui/backend';
import { Label } from 'tgui/components/Label';
import { Button, Section, Stack } from 'tgui-core/components';
import { BeakerContents } from '../common/BeakerContents';
import type { ChemDispenserActions } from '../generated/ChemDispenser';
import type { Data } from './types';

export const ChemDispenserBeaker = (props) => {
  const { act, data } = useBackend<Data, ChemDispenserActions>();
  const {
    isBeakerLoaded,
    beakerCurrentVolume,
    beakerMaxVolume,
    beakerContents = [],
    recipes,
    recordingRecipe,
  } = data;

  const recording = !!recordingRecipe;
  const recordedContents =
    recording &&
    recordingRecipe.map((r) => ({
      id: r.id,
      name: r.id.replace(/_/, ' '),
      volume: r.amount,
      contaminant: false,
    }));

  return (
    <Section
      title={recording ? 'Virtual Beaker' : 'Beaker'}
      fill
      scrollable
      buttons={
        <Stack>
          <Stack.Item>
            {!!isBeakerLoaded && (
              <Label inline mr={2}>
                {beakerCurrentVolume} / {beakerMaxVolume} units
              </Label>
            )}
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="eject"
              disabled={!isBeakerLoaded}
              onClick={() => act('ejectBeaker')}
            >
              Eject
            </Button>
          </Stack.Item>
        </Stack>
      }
    >
      <BeakerContents
        beakerLoaded={recordedContents || isBeakerLoaded}
        beakerContents={recordedContents || beakerContents}
      />
    </Section>
  );
};
