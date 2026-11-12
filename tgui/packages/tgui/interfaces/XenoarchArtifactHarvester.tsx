import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  ProgressBar,
  Section,
} from 'tgui-core/components';
import type {
  XenoarchArtifactHarvesterActions,
  XenoarchArtifactHarvesterData,
} from './generated/XenoarchArtifactHarvester';
import { Label } from 'tgui/components/Label';

type Data = XenoarchArtifactHarvesterData;

type battery = NonNullable<Data['info']['inserted_battery']>;

export const XenoarchArtifactHarvester = (props) => {
  const { act, data } = useBackend<Data, XenoarchArtifactHarvesterActions>();

  const { no_scanner, harvesting, inserted_battery } = data.info ?? {
    no_scanner: true,
    harvesting: 0,
    inserted_battery: null,
  };

  return (
    <Window width={450} height={200}>
      <Window.Content>
        {(no_scanner && (
          <Box color="bad">Warning: No scanner detected.</Box>
        )) || (
          <Section>
            {(harvesting > 0 && (
              <Box>
                <Label textAlign="center" mb={1}>
                  Please wait. Harvesting in progress.
                </Label>
                <ArtHarvestBatteryProgress
                  inserted_battery={inserted_battery}
                />
                <Button
                  mt={1}
                  fluid
                  icon="stop"
                  onClick={() => act('stopharvest')}
                >
                  Stop Early
                </Button>
              </Box>
            )) ||
              (harvesting < 0 && (
                <Box>
                  <Label textAlign="center" mb={1}>
                    Please wait. Energy dump in progress.
                  </Label>
                  <ArtHarvestBatteryProgress
                    inserted_battery={inserted_battery}
                  />
                  <Button
                    mt={1}
                    fluid
                    icon="stop"
                    onClick={() => act('stopharvest')}
                  >
                    Stop Early
                  </Button>
                </Box>
              )) ||
              (inserted_battery && (
                <Box>
                  <LabeledList>
                    <LabeledList.Item label="Name">
                      {inserted_battery.name}
                    </LabeledList.Item>
                    <LabeledList.Item label="Charge">
                      <ArtHarvestBatteryProgress
                        inserted_battery={inserted_battery}
                      />
                    </LabeledList.Item>
                    <LabeledList.Item label="Energy Signature ID">
                      {inserted_battery.artifact_id}
                    </LabeledList.Item>
                  </LabeledList>
                  <Button
                    mt={1}
                    fluid
                    icon="eject"
                    onClick={() => act('ejectbattery')}
                  >
                    Eject Battery
                  </Button>
                  <Button fluid icon="bolt" onClick={() => act('drainbattery')}>
                    Drain Battery
                  </Button>
                  <Button fluid icon="star" onClick={() => act('harvest')}>
                    Begin Harvest
                  </Button>
                </Box>
              )) || <Box color="bad">No battery inserted.</Box>}
          </Section>
        )}
      </Window.Content>
    </Window>
  );
};

const ArtHarvestBatteryProgress = (props: {
  inserted_battery: battery | null;
}) => {
  const { inserted_battery } = props;

  if (!inserted_battery) {
    return <Box color="bad">No battery inserted.</Box>;
  }

  return (
    <ProgressBar
      minValue={0}
      value={inserted_battery.stored_charge}
      maxValue={inserted_battery.capacity}
    />
  );
};
