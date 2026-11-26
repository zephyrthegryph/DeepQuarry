// OOC character notes — structured TGUI. Anyone can view; only the owner can edit.

import { useBackend } from 'tgui/backend';
import { FormattedText } from 'tgui/dq';
import { Window } from 'tgui/layouts';
import { Box, Button, Section, Stack } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';
import type { OocNotesActions, OocNotesData } from './generated/OocNotes';

type SectionDef = {
  title: string;
  field: 'ooc_favs' | 'ooc_likes' | 'ooc_maybes' | 'ooc_dislikes';
  edit_action: 'edit_favs' | 'edit_likes' | 'edit_maybes' | 'edit_dislikes';
  color?: string;
};

const SECTIONS: SectionDef[] = [
  { title: 'Favourites', field: 'ooc_favs', edit_action: 'edit_favs' },
  { title: 'Likes', field: 'ooc_likes', edit_action: 'edit_likes' },
  { title: 'Maybes', field: 'ooc_maybes', edit_action: 'edit_maybes' },
  { title: 'Dislikes', field: 'ooc_dislikes', edit_action: 'edit_dislikes' },
];

export const OocNotes = () => {
  const { data, act } = useBackend<OocNotesData, OocNotesActions>();
  const { owner, is_owner, ooc_notes, ooc_style } = data;
  return (
    <Window width={680} height={620} title={`OOC Notes: ${owner}`}>
      <Window.Content scrollable>
        <Section
          title="OOC Notes"
          buttons={
            <>
              <Button onClick={() => act('print')} icon="print">
                Print to chat
              </Button>{' '}
              {is_owner ? (
                <>
                  <Button onClick={() => act('edit_notes')} icon="pen">
                    Edit
                  </Button>{' '}
                  <Button
                    onClick={() => act('toggle_style')}
                    icon="table-columns"
                  >
                    {ooc_style ? 'Lists' : 'Fields'}
                  </Button>{' '}
                  <Button color="good" onClick={() => act('save')} icon="save">
                    Save Character Preferences
                  </Button>
                </>
              ) : null}
            </>
          }
        >
          {ooc_notes ? (
            <Box>
              <FormattedText text={ooc_notes} markers={data.markers} />
            </Box>
          ) : (
            <EmptyState>(none)</EmptyState>
          )}
        </Section>
        <Stack
          fill
          vertical={!ooc_style}
          // when in "fields" mode (ooc_style=true) lay out the sections in a row.
        >
          {SECTIONS.map((s) => {
            const text = data[s.field];
            if (!text && !is_owner) {
              return null;
            }
            return (
              <Stack.Item grow key={s.field}>
                <Section
                  title={s.title}
                  buttons={
                    is_owner ? (
                      <Button
                        onClick={() => act(s.edit_action)}
                        icon="pen"
                        compact
                      >
                        Edit
                      </Button>
                    ) : null
                  }
                >
                  {text ? (
                    <Box>
                      <FormattedText text={text} markers={data.markers} />
                    </Box>
                  ) : (
                    <EmptyState>(none)</EmptyState>
                  )}
                </Section>
              </Stack.Item>
            );
          })}
        </Stack>
      </Window.Content>
    </Window>
  );
};
