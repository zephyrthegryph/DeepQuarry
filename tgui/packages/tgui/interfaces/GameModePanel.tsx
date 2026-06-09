// Edit Game Mode admin panel — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type AntagTemplate = {
  id: string;
  count: number;
  cur_max: number;
};

type Data = {
  alive: BooleanLike;
  mode_name?: string;
  config_tag?: string;
  ert_enabled?: BooleanLike;
  respawn_allowed?: BooleanLike;
  shuttle_delay?: number;
  shuttle_auto_recall?: BooleanLike;
  event_modifier_moderate?: number;
  event_modifier_major?: number;
  autotraitor?: BooleanLike;
  antag_scaling_coeff?: number;
  core_antag_tags?: string[];
  antag_templates?: AntagTemplate[];
};

export const GameModePanel = () => {
  const { data, act } = useBackend<Data>();
  if (!data.alive) {
    return (
      <Window width={540} height={500} title="Edit Game Mode">
        <Window.Content>
          <Section>
            <Box italic color="bad">
              No game mode is currently active.
            </Box>
          </Section>
        </Window.Content>
      </Window>
    );
  }
  const {
    mode_name,
    config_tag,
    ert_enabled,
    respawn_allowed,
    shuttle_delay,
    shuttle_auto_recall,
    event_modifier_moderate,
    event_modifier_major,
    autotraitor,
    antag_scaling_coeff,
    core_antag_tags,
    antag_templates,
  } = data;
  return (
    <Window width={620} height={680} title="Edit Game Mode">
      <Window.Content scrollable>
        <Section title={`Current mode: ${mode_name}`}>
          <Box>
            <Button
              icon="info-circle"
              onClick={() => act('debug_antag', { id: 'self' })}
            >
              {config_tag}
            </Button>
          </Box>
        </Section>

        <Section title="Round Settings">
          <LabeledList>
            <LabeledList.Item label="Emergency Response Teams">
              <Button
                selected={!!ert_enabled}
                onClick={() => act('toggle', { key: 'ert' })}
              >
                {ert_enabled ? 'Enabled' : 'Disabled'}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Respawning">
              <Button
                selected={!!respawn_allowed}
                onClick={() => act('toggle', { key: 'respawn' })}
              >
                {respawn_allowed ? 'Allowed' : 'Disallowed'}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Shuttle delay multiplier">
              <Button onClick={() => act('set', { key: 'shuttle_delay' })}>
                {shuttle_delay}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Shuttle auto-recall">
              <Button
                selected={!!shuttle_auto_recall}
                onClick={() => act('toggle', { key: 'shuttle_recall' })}
              >
                {shuttle_auto_recall ? 'Enabled' : 'Disabled'}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Moderate event modifier">
              <Button
                onClick={() => act('set', { key: 'event_modifier_moderate' })}
              >
                {event_modifier_moderate || 'unset'}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Major event modifier">
              <Button
                onClick={() => act('set', { key: 'event_modifier_severe' })}
              >
                {event_modifier_major || 'unset'}
              </Button>
            </LabeledList.Item>
          </LabeledList>
        </Section>

        <Section title="Autotraitor">
          <Stack>
            <Stack.Item>
              <Button
                selected={!!autotraitor}
                onClick={() => act('toggle', { key: 'autotraitor' })}
              >
                {autotraitor ? 'Enabled' : 'Disabled'}
              </Button>
            </Stack.Item>
            {autotraitor ? (
              <Stack.Item>
                Scaling coeff:{' '}
                <Button onClick={() => act('set', { key: 'antag_scaling' })}>
                  {antag_scaling_coeff && antag_scaling_coeff > 0
                    ? antag_scaling_coeff
                    : 'unset (click to set)'}
                </Button>
              </Stack.Item>
            ) : null}
          </Stack>
        </Section>

        {core_antag_tags && core_antag_tags.length > 0 ? (
          <Section title="Core antag templates">
            {core_antag_tags.map((tag) => (
              <Button key={tag} onClick={() => act('debug_antag', { id: tag })}>
                {tag}
              </Button>
            ))}
          </Section>
        ) : null}

        <Section
          title="All antag templates"
          buttons={
            <Button
              icon="plus"
              color="good"
              onClick={() => act('add_antag_type')}
            >
              Add
            </Button>
          }
        >
          {!antag_templates || antag_templates.length === 0 ? (
            <EmptyState>None.</EmptyState>
          ) : (
            <Stack vertical>
              {antag_templates.map((a) => (
                <Stack.Item key={a.id}>
                  <Stack>
                    <Stack.Item grow>
                      <Button onClick={() => act('debug_antag', { id: a.id })}>
                        {a.id}
                      </Button>{' '}
                      <Box inline color="label">
                        ({a.count}/{a.cur_max})
                      </Box>
                    </Stack.Item>
                    <Stack.Item>
                      <Button
                        compact
                        color="bad"
                        icon="minus"
                        onClick={() => act('remove_antag_type', { id: a.id })}
                      />
                    </Stack.Item>
                  </Stack>
                </Stack.Item>
              ))}
            </Stack>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
