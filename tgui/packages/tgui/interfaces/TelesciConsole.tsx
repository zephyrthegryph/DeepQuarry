import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  AnimatedNumber,
  Box,
  Button,
  LabeledList,
  NoticeBox,
  NumberInput,
  Section,
} from 'tgui-core/components';
import type {
  TelesciConsoleActions,
  TelesciConsoleData,
} from './generated/TelesciConsole';

type Data = TelesciConsoleData;

export const TelesciConsole = (props) => {
  const { data } = useBackend<Data, TelesciConsoleActions>();

  const { noTelepad } = data;

  return (
    <Window width={400} height={450}>
      <Window.Content scrollable>
        {(noTelepad && <TelesciNoTelepadError />) || <TelesciConsoleContent />}
      </Window.Content>
    </Window>
  );
};

const TelesciNoTelepadError = (props) => {
  return (
    <Section title="Error" color="bad">
      No telepad located.
      <br />
      Please add telepad data.
    </Section>
  );
};

export const TelesciConsoleContent = (props) => {
  const { act, data } = useBackend<Data, TelesciConsoleActions>();

  const {
    insertedGps,
    rotation = 0,
    currentZ,
    cooldown = 0,
    crystalCount,
    maxCrystals,
    maxPossibleDistance,
    maxAllowedDistance = 0,
    distance = 0,
    tempMsg,
    sectorOptions = [],
    lastTeleData,
  } = data;

  const sectors = [...sectorOptions].sort((a, b) => a - b);

  return (
    <Section
      title="Telepad Controls"
      buttons={
        <Button
          icon="eject"
          disabled={!insertedGps}
          onClick={() => act('ejectGPS')}
        >
          Eject GPS
        </Button>
      }
    >
      <NoticeBox info>
        {(cooldown && (
          <Box>
            Telepad is recharging. Please wait
            <AnimatedNumber value={cooldown} /> seconds.
          </Box>
        )) || <Box>{tempMsg}</Box>}
      </NoticeBox>
      <LabeledList>
        <LabeledList.Item label="Bearing">
          <NumberInput
            fluid
            tickWhileDragging
            value={rotation}
            format={(v) => `${v}°`}
            step={1}
            minValue={-900}
            maxValue={900}
            onChange={(val) => act('setrotation', { val: val })}
          />
        </LabeledList.Item>
        <LabeledList.Item label="Distance">
          <NumberInput
            fluid
            tickWhileDragging
            value={distance}
            format={(v) => `${v}/${maxAllowedDistance} m`}
            minValue={0}
            maxValue={maxAllowedDistance}
            step={1}
            stepPixelSize={4}
            onChange={(val) => act('setdistance', { val: val })}
          />
        </LabeledList.Item>
        <LabeledList.Item label="Sector">
          {sectors.map((z) => (
            <Button
              key={z}
              icon="check-circle"
              selected={currentZ === z}
              onClick={() => act('setz', { setz: z })}
            >
              {z}
            </Button>
          ))}
        </LabeledList.Item>
        <LabeledList.Item label="Controls">
          <Button icon="share" iconRotation={-90} onClick={() => act('send')}>
            Send
          </Button>
          <Button icon="share" iconRotation={90} onClick={() => act('receive')}>
            Receive
          </Button>
          <Button icon="sync" iconRotation={90} onClick={() => act('recal')}>
            Recalibrate
          </Button>
        </LabeledList.Item>
      </LabeledList>
      {(lastTeleData && (
        <Section mt={1}>
          <LabeledList>
            <LabeledList.Item label="Telepad Location">
              {lastTeleData.src_x}, {lastTeleData.src_y}
            </LabeledList.Item>
            <LabeledList.Item label="Distance">
              {lastTeleData.distance}m
            </LabeledList.Item>
            <LabeledList.Item label="Transit Time">
              {lastTeleData.time} secs
            </LabeledList.Item>
          </LabeledList>
        </Section>
      )) || <Section mt={1}>No teleport data found.</Section>}
      <Section>
        Crystals: {crystalCount} / {maxCrystals}
      </Section>
    </Section>
  );
};
