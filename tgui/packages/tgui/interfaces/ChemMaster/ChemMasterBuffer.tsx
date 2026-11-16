import { useBackend } from 'tgui/backend';
import { Label } from 'tgui/components/Label';
import { BeakerContents } from 'tgui/interfaces/common/BeakerContents';
import { modalOpen } from 'tgui/interfaces/common/ComplexModal';
import { Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { MixTransfer } from './MixTransfer';
import type { reagent } from './types';

export const ChemMasterBuffer = (props: {
  mode: BooleanLike;
  bufferReagents: reagent[];
}) => {
  const { act } = useBackend();
  const { mode, bufferReagents = [] } = props;
  return (
    <Section
      title="Buffer"
      buttons={
        <Stack>
          <Stack.Item>
            <Label>Transferring to</Label>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon={mode ? 'flask' : 'trash'}
              color={!mode && 'bad'}
              onClick={() => act('toggle')}
            >
              {mode ? 'Beaker' : 'Disposal'}
            </Button>
          </Stack.Item>
        </Stack>
      }
    >
      {bufferReagents.length > 0 ? (
        <>
          <MixTransfer
            action="remove"
            custom="removecustom"
            reagents={bufferReagents}
          />
          <BeakerContents
            beakerLoaded
            beakerContents={bufferReagents}
            buttons={(chemical, i) => (
              <Stack mb={i < bufferReagents.length - 1 && '2px'}>
                <Stack.Item>
                  <Button
                    mb="0"
                    onClick={() =>
                      modalOpen('analyze', {
                        idx: i + 1,
                        beaker: 0,
                      })
                    }
                  >
                    Analyze
                  </Button>
                </Stack.Item>
              </Stack>
            )}
          />
        </>
      ) : (
        <Label>Buffer is empty.</Label>
      )}
    </Section>
  );
};
