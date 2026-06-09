import { useBackend } from 'tgui/backend';
import {
  AnimatedNumber,
  Box,
  Button,
  LabeledList,
  Section,
  Stack,
} from 'tgui-core/components';

import { BAND_INFO, BAND_RANK, stats } from './constants';
import type { DamageBand, occupant } from './types';

export const BodyScannerMainOccupant = (props: { occupant: occupant }) => {
  const { act } = useBackend();
  const { occupant } = props;
  // Use the worst of (overall health band, worst scanner finding) so a
  // patient with severe brain bleeding still reads as "Critical" even if
  // their gross health % is fine. Triage cares about the worst thing on
  // the scan, not the average.
  const healthBand = (occupant.healthBand as DamageBand) ?? 'uninjured';
  const worstFinding = (occupant.worstFinding as DamageBand) ?? 'uninjured';
  const band: DamageBand =
    BAND_RANK[worstFinding] > BAND_RANK[healthBand] ? worstFinding : healthBand;
  const info = BAND_INFO[band];
  // Customise the wording for the overall-health row so it doesn't read
  // as "moderate injury" generically — the damage panel + per-organ
  // rows already cover specific injuries.
  const healthWord =
    band === 'uninjured'
      ? 'Stable'
      : band === 'minor'
        ? 'Lightly injured'
        : band === 'moderate'
          ? 'Significantly injured'
          : band === 'severe'
            ? 'Critically injured'
            : 'Failing';
  return (
    <Section
      title="Occupant"
      buttons={
        <Stack>
          <Stack.Item>
            <Button icon="user-slash" onClick={() => act('ejectify')}>
              Eject
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button icon="print" onClick={() => act('print_p')}>
              Print Report
            </Button>
          </Stack.Item>
        </Stack>
      }
    >
      <LabeledList>
        <LabeledList.Item label="Name">{occupant.name}</LabeledList.Item>
        <LabeledList.Item label="Species">{occupant.species}</LabeledList.Item>
        <LabeledList.Item label="Condition" color={info.color}>
          {healthWord}
        </LabeledList.Item>
        <LabeledList.Item label="Status" color={stats[occupant.stat][0]}>
          {stats[occupant.stat][1]}
        </LabeledList.Item>
        <LabeledList.Item label="Temperature">
          <AnimatedNumber
            value={occupant.bodyTempC}
            format={(value) => value.toFixed()}
          />
          &deg;C,&nbsp;
          <AnimatedNumber
            value={occupant.bodyTempF}
            format={(value) => value.toFixed()}
          />
          &deg;F
        </LabeledList.Item>
        <LabeledList.Item label="Blood Volume">
          <AnimatedNumber
            value={occupant.blood.volume}
            format={(value) => value.toFixed()}
          />
          u&nbsp;(
          <AnimatedNumber
            value={occupant.blood.percent}
            format={(value) => value.toFixed()}
          />
          %)
        </LabeledList.Item>
        <LabeledList.Item label="Weight">
          {`${(occupant.weight / 2.20463).toFixed(1)}kg, `}
          {`${occupant.weight.toFixed()}lbs`}
        </LabeledList.Item>
        {occupant.paralysisSeconds > 0 ? (
          <LabeledList.Item label="Paralysis" color="average">
            <Box inline>{occupant.paralysisSeconds}s remaining</Box>
          </LabeledList.Item>
        ) : null}
      </LabeledList>
    </Section>
  );
};
