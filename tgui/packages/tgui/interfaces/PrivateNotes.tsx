// Private character notes — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';

type Data = {
  owner: string;
  notes: string;
};

export const PrivateNotes = () => {
  const { data, act } = useBackend<Data>();
  const { owner, notes } = data;
  return (
    <Window width={520} height={520} title={`Private Notes: ${owner}`}>
      <Window.Content scrollable>
        <Section
          title="Private Notes"
          buttons={
            <>
              <Button onClick={() => act('edit')} icon="pen">
                Edit
              </Button>{' '}
              <Button color="good" onClick={() => act('save')} icon="save">
                Save Character Preferences
              </Button>
            </>
          }
        >
          {notes ? (
            <Box preserveWhitespace>{notes}</Box>
          ) : (
            <EmptyState>(no notes yet — click Edit)</EmptyState>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
