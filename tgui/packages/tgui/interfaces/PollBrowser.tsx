// Player poll browser — TGUI.
//
// Two screens in one window: a list of active polls, and a per-poll
// detail/voting screen. The DM side picks which screen to show based
// on `selected` being null or populated. All actions flow through
// tgui_act; there are no embedded byond:// hrefs.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Dropdown,
  Section,
  Stack,
  TextArea,
} from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type PollListEntry = {
  id: number;
  question: string;
};

type PollOption = {
  id: number;
  text: string;
};

type NumvalScalePoint = {
  value: string;
  label: string;
};

type NumvalOption = {
  id: number;
  text: string;
  min: number;
  max: number;
  scale: NumvalScalePoint[];
};

type VotedRating = {
  text: string;
  rating: string;
};

type Selected = {
  id: number;
  error: string | null;
  voted: BooleanLike;
  start_time?: string;
  end_time?: string;
  question?: string;
  poll_type?: 'OPTION' | 'TEXT' | 'NUMVAL' | 'MULTICHOICE';
  multi_max?: number;
  options?: PollOption[] | NumvalOption[];
  voted_option_id?: number | null;
  voted_options?: number[];
  vote_text?: string;
  voted_ratings?: VotedRating[];
};

type Data = {
  polls: PollListEntry[];
  selected: Selected | null;
};

export const PollBrowser = () => {
  const { data, act } = useBackend<Data>();
  const { polls, selected } = data;

  return (
    <Window width={560} height={560} title="Player Polls">
      <Window.Content scrollable>
        {selected ? (
          <PollDetail selected={selected} act={act} />
        ) : (
          <PollList polls={polls} act={act} />
        )}
      </Window.Content>
    </Window>
  );
};

const PollList = (props: {
  polls: PollListEntry[];
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { polls, act } = props;
  return (
    <Section
      title="Active Polls"
      buttons={
        <Button icon="rotate" onClick={() => act('refresh')}>
          Refresh
        </Button>
      }
    >
      {polls.length === 0 ? (
        <EmptyState>There are no active polls.</EmptyState>
      ) : (
        <Stack vertical>
          {polls.map((p) => (
            <Stack.Item key={p.id}>
              <Button fluid onClick={() => act('select', { id: p.id })}>
                {p.question}
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      )}
    </Section>
  );
};

const PollBody = (props: {
  selected: Selected;
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { selected, act } = props;
  switch (selected.poll_type) {
    case 'OPTION':
      return <OptionPoll selected={selected} act={act} />;
    case 'MULTICHOICE':
      return <MultiChoicePoll selected={selected} act={act} />;
    case 'TEXT':
      return <TextPoll selected={selected} act={act} />;
    case 'NUMVAL':
      return <NumvalPoll selected={selected} act={act} />;
    default:
      return (
        <EmptyState>Unsupported poll type: {selected.poll_type}.</EmptyState>
      );
  }
};

const PollDetail = (props: {
  selected: Selected;
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { selected, act } = props;
  const { id, error, question, start_time, end_time, poll_type, voted } =
    selected;

  return (
    <Section
      title={question ?? `Poll #${id}`}
      buttons={
        <Button icon="arrow-left" onClick={() => act('back')}>
          Back
        </Button>
      }
    >
      {error ? (
        <Box color="bad">{error}</Box>
      ) : (
        <>
          <Box mb={1} color="label">
            Runs from <b>{start_time}</b> until <b>{end_time}</b>.
          </Box>
          <PollBody selected={selected} act={act} />

          {voted ? (
            <Box mt={2} bold color="good">
              You have already responded to this poll.
            </Box>
          ) : null}
        </>
      )}
    </Section>
  );
};

const OptionPoll = (props: {
  selected: Selected;
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { selected, act } = props;
  const options = (selected.options as PollOption[]) ?? [];
  const [pick, setPick] = useState<number | null>(null);

  if (selected.voted) {
    return (
      <Stack vertical>
        {options.map((o) => (
          <Stack.Item key={o.id}>
            <Box bold={o.id === selected.voted_option_id}>
              {o.id === selected.voted_option_id ? '✓ ' : ''}
              {o.text}
            </Box>
          </Stack.Item>
        ))}
      </Stack>
    );
  }

  return (
    <>
      <Stack vertical>
        {options.map((o) => (
          <Stack.Item key={o.id}>
            <Button
              fluid
              selected={pick === o.id}
              onClick={() => setPick(o.id)}
            >
              {o.text}
            </Button>
          </Stack.Item>
        ))}
      </Stack>
      <Box mt={2}>
        <Button
          color="good"
          disabled={pick === null}
          onClick={() => {
            if (pick !== null) {
              act('vote_option', {
                pollid: selected.id,
                optionid: pick,
              });
            }
          }}
        >
          Vote
        </Button>
      </Box>
    </>
  );
};

const MultiChoicePoll = (props: {
  selected: Selected;
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { selected, act } = props;
  const options = (selected.options as PollOption[]) ?? [];
  const max = selected.multi_max ?? 1;
  const [picks, setPicks] = useState<number[]>([]);

  if (selected.voted) {
    const votedFor = selected.voted_options ?? [];
    return (
      <Stack vertical>
        {options.map((o) => (
          <Stack.Item key={o.id}>
            <Box bold={votedFor.includes(o.id)}>
              {votedFor.includes(o.id) ? '✓ ' : ''}
              {o.text}
            </Box>
          </Stack.Item>
        ))}
      </Stack>
    );
  }

  const toggle = (id: number) => {
    if (picks.includes(id)) {
      setPicks(picks.filter((x) => x !== id));
    } else if (picks.length < max) {
      setPicks([...picks, id]);
    }
  };

  return (
    <>
      <Box mb={1} color="label">
        Select up to {max} options.
      </Box>
      <Stack vertical>
        {options.map((o) => (
          <Stack.Item key={o.id}>
            <Button
              fluid
              selected={picks.includes(o.id)}
              onClick={() => toggle(o.id)}
            >
              {o.text}
            </Button>
          </Stack.Item>
        ))}
      </Stack>
      <Box mt={2}>
        <Button
          color="good"
          disabled={picks.length === 0}
          onClick={() =>
            act('vote_multi', {
              pollid: selected.id,
              optionids: picks,
            })
          }
        >
          Vote ({picks.length}/{max})
        </Button>
      </Box>
    </>
  );
};

const TextPoll = (props: {
  selected: Selected;
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { selected, act } = props;
  const [text, setText] = useState('');

  if (selected.voted) {
    return (
      <Box mt={1} preserveWhitespace>
        {selected.vote_text}
      </Box>
    );
  }

  return (
    <>
      <Box mb={1} color="label">
        Provide feedback below. English letters, numbers and the symbols . , ! ?
        : ; - are accepted.
      </Box>
      <TextArea
        height="180px"
        width="100%"
        value={text}
        onChange={(value) => setText(value)}
      />
      <Box mt={2}>
        <Button
          color="good"
          disabled={!text.trim()}
          onClick={() =>
            act('vote_text', {
              pollid: selected.id,
              replytext: text,
            })
          }
        >
          Submit
        </Button>{' '}
        <Button
          color="average"
          onClick={() => act('vote_text_abstain', { pollid: selected.id })}
        >
          Abstain
        </Button>
      </Box>
    </>
  );
};

const NumvalPoll = (props: {
  selected: Selected;
  act: (action: string, params?: Record<string, unknown>) => void;
}) => {
  const { selected, act } = props;

  // Hook must be called unconditionally before any early return.
  const [ratings, setRatings] = useState<Record<string, string>>({});

  if (selected.voted) {
    const votedRatings = selected.voted_ratings ?? [];
    return (
      <Stack vertical>
        {votedRatings.map((r, i) => (
          <Stack.Item key={i}>
            <Box bold>
              {r.text} — {r.rating}
            </Box>
          </Stack.Item>
        ))}
      </Stack>
    );
  }

  const options = (selected.options as NumvalOption[]) ?? [];

  return (
    <>
      <Stack vertical>
        {options.map((o) => {
          const current = ratings[String(o.id)] ?? '';
          const labels = o.scale.map((s) => s.label);
          const selectedLabel =
            o.scale.find((s) => s.value === current)?.label ?? '';
          return (
            <Stack.Item key={o.id}>
              <Box mb="2px">{o.text}</Box>
              <Dropdown
                options={labels}
                selected={selectedLabel}
                onSelected={(label: string) => {
                  const found = o.scale.find((s) => s.label === label);
                  if (found) {
                    setRatings({
                      ...ratings,
                      [String(o.id)]: found.value,
                    });
                  }
                }}
              />
            </Stack.Item>
          );
        })}
      </Stack>
      <Box mt={2}>
        <Button
          color="good"
          disabled={Object.keys(ratings).length === 0}
          onClick={() =>
            act('vote_numval', {
              pollid: selected.id,
              ratings,
            })
          }
        >
          Submit
        </Button>
      </Box>
    </>
  );
};
