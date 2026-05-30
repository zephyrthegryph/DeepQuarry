// Edit Memory admin panel — structured TGUI.
//
// Replaces the legacy HTML body that mind.edit_memory used to ship.
// Each objective row, antag template row, and ambition / role / memory
// edit becomes a typed React component.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';
import { HtmlRenderer } from './common/HtmlRenderer';

type Objective = {
  ref: string;
  num: number;
  text: string;
  completed: BooleanLike;
};

type AntagBlock = {
  id: string;
  role_text: string;
  is_antagonist: BooleanLike;
  has_locations: BooleanLike;
  extra_html: string;
};

type Data = {
  alive: BooleanLike;
  name?: string;
  real_name?: string | null;
  key?: string;
  synced?: BooleanLike;
  assigned_role?: string;
  ambitions?: string;
  memory?: string;
  objectives?: Objective[];
  antag_blocks?: AntagBlock[];
};

export const EditMemoryPanel = () => {
  const { data, act } = useBackend<Data>();
  if (!data.alive) {
    return (
      <Window width={600} height={500} title="Edit Memory">
        <Window.Content>
          <Section>
            <Box italic color="bad">
              Mind no longer exists.
            </Box>
          </Section>
        </Window.Content>
      </Window>
    );
  }
  const {
    name,
    real_name,
    key,
    synced,
    assigned_role,
    ambitions,
    memory,
    objectives,
    antag_blocks,
  } = data;
  return (
    <Window width={640} height={720} title={`Edit Memory: ${name ?? ''}`}>
      <Window.Content scrollable>
        <Section title={name}>
          {real_name ? (
            <Box color="label">(currently controlling {real_name})</Box>
          ) : null}
          <LabeledList>
            <LabeledList.Item label="Key">
              {key}
              <Box inline color={synced ? 'good' : 'bad'} ml={1}>
                ({synced ? 'synced' : 'not synced'})
              </Box>
            </LabeledList.Item>
            <LabeledList.Item label="Assigned Role">
              {assigned_role}{' '}
              <Button compact onClick={() => act('edit_role')}>
                Edit
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Memory">
              <Box mr={1} preserveWhitespace>
                {memory || (
                  <Box inline italic color="label">
                    (none)
                  </Box>
                )}
              </Box>
              <Button compact onClick={() => act('edit_memory')}>
                Edit
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Ambitions">
              <Box mr={1} preserveWhitespace>
                {ambitions || (
                  <Box inline italic color="label">
                    (none)
                  </Box>
                )}
              </Box>
              <Button compact onClick={() => act('edit_ambitions')}>
                Edit
              </Button>
            </LabeledList.Item>
          </LabeledList>
        </Section>

        <Section
          title="Objectives"
          buttons={
            <>
              <Button icon="plus" onClick={() => act('obj_add')}>
                Add
              </Button>{' '}
              <Button icon="bullhorn" onClick={() => act('obj_announce')}>
                Announce
              </Button>
            </>
          }
        >
          {!objectives || objectives.length === 0 ? (
            <EmptyState>None.</EmptyState>
          ) : (
            <Stack vertical>
              {objectives.map((o) => (
                <Stack.Item key={o.ref}>
                  <Stack>
                    <Stack.Item width="36px" color="label">
                      #{o.num}
                    </Stack.Item>
                    <Stack.Item grow>
                      <Box color={o.completed ? 'good' : 'bad'}>{o.text}</Box>
                    </Stack.Item>
                    <Stack.Item>
                      <Button
                        compact
                        icon={o.completed ? 'check' : 'times'}
                        selected={!!o.completed}
                        onClick={() =>
                          act('obj_toggle_complete', { ref: o.ref })
                        }
                      >
                        {o.completed ? 'Complete' : 'Incomplete'}
                      </Button>{' '}
                      <Button
                        compact
                        color="bad"
                        icon="trash"
                        onClick={() => act('obj_delete', { ref: o.ref })}
                      />
                    </Stack.Item>
                  </Stack>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>

        <Section title="Factions / Special Roles">
          <Stack vertical>
            {(antag_blocks ?? []).map((block) => (
              <Stack.Item key={block.id}>
                <Stack>
                  <Stack.Item grow>
                    <Box bold>{block.role_text}</Box>
                    {block.extra_html ? (
                      <Box mt="2px">
                        <HtmlRenderer
                          html={block.extra_html}
                          act={act}
                          forwardTopic
                        />
                      </Box>
                    ) : null}
                  </Stack.Item>
                  <Stack.Item>
                    {block.is_antagonist ? (
                      <>
                        <Button
                          compact
                          color="bad"
                          icon="minus"
                          onClick={() => act('antag_remove', { id: block.id })}
                        />{' '}
                        <Button
                          compact
                          icon="briefcase"
                          onClick={() => act('antag_equip', { id: block.id })}
                        >
                          Equip
                        </Button>{' '}
                        {block.has_locations ? (
                          <Button
                            compact
                            icon="map-marker"
                            onClick={() =>
                              act('antag_move_to_spawn', { id: block.id })
                            }
                          >
                            Move to spawn
                          </Button>
                        ) : null}
                      </>
                    ) : (
                      <Button
                        compact
                        color="good"
                        icon="plus"
                        onClick={() => act('antag_add', { id: block.id })}
                      >
                        Add
                      </Button>
                    )}
                  </Stack.Item>
                </Stack>
              </Stack.Item>
            ))}
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};
