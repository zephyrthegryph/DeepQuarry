import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  NoticeBox,
  ProgressBar,
  Section,
} from 'tgui-core/components';
import type { AiRestorerActions, AiRestorerData } from './generated/AiRestorer';

type Data = AiRestorerData;

export const AiRestorer = () => {
  return (
    <Window width={370} height={360}>
      <Window.Content scrollable>
        <AiRestorerContent />
      </Window.Content>
    </Window>
  );
};

export const AiRestorerContent = (props) => {
  const { act, data } = useBackend<Data, AiRestorerActions>();
  const { AI_present, error, name, laws, isDead, restoring, health } = data;
  return (
    <>
      {error && <NoticeBox textAlign="center">{error}</NoticeBox>}
      {!!AI_present && (
        <Section
          title={name}
          buttons={
            <Box inline bold color={isDead ? 'bad' : 'good'}>
              {isDead ? 'Nonfunctional' : 'Functional'}
            </Box>
          }
        >
          <LabeledList>
            <LabeledList.Item label="Integrity">
              <ProgressBar
                value={health}
                minValue={0}
                maxValue={100}
                ranges={{
                  good: [70, Infinity],
                  average: [50, 70],
                  bad: [-Infinity, 50],
                }}
              />
            </LabeledList.Item>
          </LabeledList>
          {!!restoring && (
            <Box bold textAlign="center" fontSize="20px" color="good" mt={1}>
              RECONSTRUCTION IN PROGRESS
            </Box>
          )}
          <Button
            fluid
            icon="plus"
            disabled={restoring}
            mt={1}
            onClick={() => act('PRG_beginReconstruction')}
          >
            Begin Reconstruction
          </Button>
          <Section title="Laws">
            {laws.map((law) => (
              <Box key={law} className="candystripe">
                {law}
              </Box>
            ))}
          </Section>
        </Section>
      )}
    </>
  );
};
