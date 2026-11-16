import { useBackend } from 'tgui/backend';
import { Label } from 'tgui/components/Label';
import { BeakerContents } from 'tgui/interfaces/common/BeakerContents';
import { modalOpen } from 'tgui/interfaces/common/ComplexModal';
import { Button, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { MixTransfer } from './MixTransfer';
import type { reagent } from './types';

export const ChemMasterBeaker = (props: {
  beaker: BooleanLike;
  beakerReagents: reagent[];
  bufferNonEmpty: BooleanLike;
}) => {
  const { act } = useBackend();
  const { beaker, beakerReagents, bufferNonEmpty } = props;

  const headerButton = bufferNonEmpty ? (
    <Button.Confirm
      icon="eject"
      disabled={!beaker}
      onClick={() => act('eject')}
    >
      Eject and Clear Buffer
    </Button.Confirm>
  ) : (
    <Button icon="eject" disabled={!beaker} onClick={() => act('eject')}>
      Eject and Clear Buffer
    </Button>
  );

  return (
    <Section title="Beaker" buttons={headerButton}>
      {beaker ? (
        <>
          <MixTransfer
            action="add"
            custom="addcustom"
            reagents={beakerReagents}
          />
          <BeakerContents
            beakerLoaded
            beakerContents={beakerReagents}
            buttons={(chemical: reagent, i: number) => (
              <Stack mb={i < beakerReagents.length - 1 && '2px'}>
                <Stack.Item>
                  <Button
                    mb="0"
                    onClick={() =>
                      modalOpen('analyze', {
                        idx: i + 1,
                        beaker: 1,
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
        <Label>No beaker loaded.</Label>
      )}
    </Section>
  );
};
