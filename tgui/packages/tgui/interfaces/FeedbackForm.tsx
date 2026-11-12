// Server feedback form — TGUI.
//
// Lets a player draft and submit a feedback entry (topic + body) to the
// sqlite feedback store. Author can optionally be hashed for privacy.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';
import type {
  FeedbackFormActions,
  FeedbackFormData,
} from './generated/FeedbackForm';

export const FeedbackForm = () => {
  const { data, act } = useBackend<FeedbackFormData, FeedbackFormActions>();
  const {
    topic,
    body,
    hide_author,
    author_ckey,
    author_hashed,
    can_be_private,
    topics,
    max_length,
    cooldown_days,
  } = data;
  const length = body.length;

  return (
    <Window width={520} height={560} title="Server Feedback">
      <Window.Content scrollable>
        <Section title="Write Feedback">
          <Box mb={1}>
            Write some feedback for the server. HTML is not supported.
          </Box>
          <Box mb={1} color="label">
            Your feedback is currently {length}/{max_length} characters long.
          </Box>
        </Section>

        <Section title="Preview">
          <LabeledList>
            <LabeledList.Item label="Author">
              {can_be_private ? (
                <>
                  <Button
                    selected={!hide_author}
                    onClick={() => act('set_hide_author', { hide: 0 })}
                  >
                    {author_ckey} (Visible)
                  </Button>{' '}
                  <Button
                    selected={!!hide_author}
                    onClick={() => act('set_hide_author', { hide: 1 })}
                  >
                    Hashed
                  </Button>
                  {hide_author ? (
                    <Box mt="2px" color="label">
                      {author_hashed}
                    </Box>
                  ) : null}
                </>
              ) : (
                author_ckey
              )}
            </LabeledList.Item>
            <LabeledList.Item label="Topic">
              {topics.length > 1 ? (
                <Button onClick={() => act('choose_topic')}>{topic}</Button>
              ) : (
                topic
              )}
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1} preserveWhitespace>
            {body ? body : <EmptyState>[Feedback goes here...]</EmptyState>}
          </Box>
          <Box mt={1}>
            <Button icon="pen" onClick={() => act('edit_body')}>
              Edit
            </Button>
          </Box>
        </Section>

        <Section>
          {cooldown_days ? (
            <Box mb={1} italic color="label">
              Please note that you will have to wait {cooldown_days} day
              {cooldown_days === 1 ? '' : 's'} before being able to write more
              feedback after submitting.
            </Box>
          ) : null}
          <Button color="good" disabled={!length} onClick={() => act('submit')}>
            Submit
          </Button>
        </Section>
      </Window.Content>
    </Window>
  );
};
