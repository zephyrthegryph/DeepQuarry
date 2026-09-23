import { Box, LabeledList, ProgressBar, Section } from 'tgui-core/components';

import {
  DiagnosisFindingsSection,
  DiagnosisVitalsSection,
} from '../common/Diagnosis';
import { stats } from './constants';
import type { occupant } from './types';

export const OperatingComputerPatient = (props: { occupant: occupant }) => {
  const { occupant } = props;
  return (
    <>
      <Section title="Patient">
        <LabeledList>
          <LabeledList.Item label="Name">{occupant.name}</LabeledList.Item>
          <LabeledList.Item label="Status" color={stats[occupant.stat][0]}>
            {stats[occupant.stat][1]}
          </LabeledList.Item>
          <LabeledList.Item label="Vitality">
            <ProgressBar
              minValue={0}
              maxValue={1}
              value={occupant.vitality / 100}
              ranges={{
                good: [0.5, Infinity],
                average: [0, 0.5],
                bad: [-Infinity, 0],
              }}
            />
          </LabeledList.Item>
          {occupant.bloodType ? (
            <LabeledList.Item label="Blood Type">
              {occupant.bloodType}
            </LabeledList.Item>
          ) : null}
        </LabeledList>
      </Section>
      <DiagnosisVitalsSection vitals={occupant.diagnosis.vitals} />
      <DiagnosisFindingsSection findings={occupant.diagnosis.findings} />
      <Section title="Current Procedure">
        {occupant.surgery?.length ? (
          <LabeledList>
            {occupant.surgery.map((limb) => (
              <LabeledList.Item key={limb.name} label={limb.name}>
                <LabeledList>
                  <LabeledList.Item label="Current State">
                    {limb.currentStage}
                  </LabeledList.Item>
                  <LabeledList.Item label="Possible Next Steps">
                    {limb.nextSteps.map((step) => (
                      <div key={step}>{step}</div>
                    ))}
                  </LabeledList.Item>
                </LabeledList>
              </LabeledList.Item>
            ))}
          </LabeledList>
        ) : (
          <Box color="label">No procedure ongoing.</Box>
        )}
      </Section>
    </>
  );
};
