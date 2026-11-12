import { useBackend } from 'tgui/backend';
import { Box, Collapsible, LabeledList } from 'tgui-core/components';
import type { MedicalRecordsActions } from '../generated/MedicalRecords';
import type { Data } from './types';
import { Label } from 'tgui/components/Label';

export const MedicalRecordsMedbots = (props) => {
  const { data } = useBackend<Data, MedicalRecordsActions>();
  const { medbots } = data;
  if (!medbots || medbots.length === 0) {
    return <Label>There are no Medbots.</Label>;
  }
  return medbots.map((medbot, i) => (
    <Collapsible key={i} open title={medbot.name}>
      <Box px="0.5rem">
        <LabeledList>
          <LabeledList.Item label="Location">
            {medbot.area || 'Unknown'} ({medbot.x}, {medbot.y})
          </LabeledList.Item>
          <LabeledList.Item label="Status">
            {medbot.on ? (
              <>
                <Box color="good">Online</Box>
                <Box mt="0.5rem">
                  {medbot.use_beaker
                    ? 'Reservoir: ' +
                      medbot.total_volume +
                      '/' +
                      medbot.maximum_volume
                    : 'Using internal synthesizer.'}
                </Box>
              </>
            ) : (
              <Box color="average">Offline</Box>
            )}
          </LabeledList.Item>
        </LabeledList>
      </Box>
    </Collapsible>
  ));
};
