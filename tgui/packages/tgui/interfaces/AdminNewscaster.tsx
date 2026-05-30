// Admin Newscaster — structured TGUI for the multi-screen news editor.
// Photo previews (browse_rsc tmp_photo.png) are not rendered — TGUI assets
// would need to be wired up; for now we show a "(photo attached)" notice.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Stack } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Channel = {
  ref: string;
  name: string;
  author: string;
  locked: BooleanLike;
  censored: BooleanLike;
  is_admin_channel: BooleanLike;
};

type Message = {
  ref: string;
  title: string;
  body: string;
  author: string;
  time_stamp: string;
  has_image: BooleanLike;
};

type WantedIssue = {
  author: string;
  body: string;
  backup_author: string;
  has_image: BooleanLike;
};

type Data = {
  screen: number;
  signature: string;
  company_name: string;
  has_wanted: BooleanLike;
  channel: Channel | null;
  message: Message | null;
  channels: Channel[];
  channel_messages: Message[];
  wanted_issue: WantedIssue | null;
};

type ActFn = (a: string, p?: Record<string, any>) => void;

const BackButton = (props: { act: ActFn; target?: number }) => (
  <Button
    icon="chevron-left"
    onClick={() => props.act('set_screen', { screen: props.target ?? 0 })}
  >
    Back
  </Button>
);

const Screen0 = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <>
      <Section title="Admin Newscaster">
        <Box mb={1}>
          Welcome to the admin newscaster. Add, edit and censor every news piece
          on the network. Feeds entered here are uneditable and treated as
          official by other units.
        </Box>
        {data.has_wanted ? (
          <Button onClick={() => act('view_wanted')} icon="user-secret">
            Read Wanted Issue
          </Button>
        ) : null}
      </Section>
      <Section title="Actions">
        <Stack vertical>
          <Stack.Item>
            <Button fluid onClick={() => act('create_channel')} icon="plus">
              Create Feed Channel
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button fluid onClick={() => act('view_channels')} icon="list">
              View Feed Channels
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button fluid onClick={() => act('create_story')} icon="pen">
              Submit new Feed Story
            </Button>
          </Stack.Item>
        </Stack>
      </Section>
      <Section title="Feed Security">
        <Stack vertical>
          <Stack.Item>
            <Button fluid onClick={() => act('menu_wanted')}>
              {data.has_wanted ? 'Manage' : 'Publish'} Wanted Issue
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button fluid onClick={() => act('menu_censor_story')}>
              Censor Feed Stories
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button fluid onClick={() => act('menu_censor_channel')}>
              Mark Feed Channel with {data.company_name} D-Notice
            </Button>
          </Stack.Item>
        </Stack>
      </Section>
      <Section
        title="Signature"
        buttons={
          <Button compact onClick={() => act('set_signature')} icon="pen">
            Change
          </Button>
        }
      >
        <Box color="good">{data.signature}</Box>
      </Section>
    </>
  );
};

const Screen1 = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section
      title="Station Feed Channels"
      buttons={
        <>
          <Button onClick={() => act('refresh')} icon="rotate-right">
            Refresh
          </Button>{' '}
          <BackButton act={act} />
        </>
      }
    >
      {data.channels.length === 0 ? (
        <EmptyState>No active channels found…</EmptyState>
      ) : (
        <Stack vertical>
          {data.channels.map((c) => (
            <Stack.Item key={c.ref}>
              <Button
                fluid
                color={c.is_admin_channel ? 'good' : undefined}
                onClick={() => act('show_channel', { ref: c.ref })}
              >
                <Box bold inline>
                  {c.name}
                </Box>
                {c.censored ? (
                  <Box inline ml={1} color="bad">
                    ***
                  </Box>
                ) : null}
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      )}
    </Section>
  );
};

const Screen2 = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section
      title="Creating new Feed Channel"
      buttons={<BackButton act={act} />}
    >
      <LabeledList>
        <LabeledList.Item label="Channel Name">
          <Button onClick={() => act('set_channel_name')}>
            {data.channel?.name || '(unset)'}
          </Button>
        </LabeledList.Item>
        <LabeledList.Item label="Channel Author">
          <Box inline color="good">
            {data.signature}
          </Box>{' '}
          <Button compact onClick={() => act('set_signature')} icon="pen">
            Change
          </Button>
        </LabeledList.Item>
        <LabeledList.Item label="Accepts Public Feeds">
          <Button onClick={() => act('set_channel_lock')}>
            {data.channel?.locked ? 'No' : 'Yes'}
          </Button>
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        <Button
          color="good"
          icon="paper-plane"
          onClick={() => act('submit_new_channel')}
        >
          Submit
        </Button>
      </Box>
    </Section>
  );
};

const Screen3 = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section
      title="Creating new Feed Message"
      buttons={<BackButton act={act} />}
    >
      <LabeledList>
        <LabeledList.Item label="Receiving Channel">
          <Button onClick={() => act('set_channel_receiving')}>
            {data.channel?.name || '(unset)'}
          </Button>
        </LabeledList.Item>
        <LabeledList.Item label="Message Author">
          <Box color="good">{data.signature}</Box>
        </LabeledList.Item>
        <LabeledList.Item label="Message Body">
          <Button onClick={() => act('set_new_message')}>
            {data.message?.body || '(unset)'}
          </Button>
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        <Button
          color="good"
          icon="paper-plane"
          onClick={() => act('submit_new_message')}
        >
          Submit
        </Button>
      </Box>
    </Section>
  );
};

const InfoScreen = (props: {
  data: Data;
  act: ActFn;
  title: string;
  body: string;
  color?: string;
  back_target?: number;
}) => {
  const { act, title, body, color, back_target } = props;
  return (
    <Section title={title}>
      <Box color={color} mb={1}>
        {body}
      </Box>
      <Button onClick={() => act('set_screen', { screen: back_target ?? 0 })}>
        Return
      </Button>
    </Section>
  );
};

const Screen6 = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section title="Error">
      <Box color="bad" bold mb={1}>
        ERROR: Could not submit Feed story to Network.
      </Box>
      {data.channel?.name === '' ? (
        <Box color="bad">Invalid receiving channel name.</Box>
      ) : null}
      {!data.message?.body || data.message.body === '[REDACTED]' ? (
        <Box color="bad">Invalid message body.</Box>
      ) : null}
      <Box mt={1}>
        <Button onClick={() => act('set_screen', { screen: 3 })}>Return</Button>
      </Box>
    </Section>
  );
};

const Screen7 = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section title="Error">
      <Box color="bad" bold mb={1}>
        ERROR: Could not submit Feed Channel to Network.
      </Box>
      {!data.channel?.name || data.channel.name === '[REDACTED]' ? (
        <Box color="bad">Invalid channel name.</Box>
      ) : null}
      <Box mt={1}>
        <Button onClick={() => act('set_screen', { screen: 2 })}>Return</Button>
      </Box>
    </Section>
  );
};

const ChannelMessages = (props: {
  data: Data;
  act: ActFn;
  back_target?: number;
}) => {
  const { data, act, back_target } = props;
  return (
    <Section
      title={data.channel?.name ?? '(no channel)'}
      buttons={
        <Box color="label" italic>
          created by {data.channel?.author}
        </Box>
      }
    >
      {data.channel?.censored ? (
        <Box color="bad" bold mb={1}>
          ATTENTION: This channel has been deemed as threatening to the welfare
          of the station, and marked with a {data.company_name} D-Notice. No
          further feed story additions are allowed while the D-Notice is in
          effect.
        </Box>
      ) : data.channel_messages.length === 0 ? (
        <EmptyState>No feed messages found in channel…</EmptyState>
      ) : (
        <Stack vertical>
          {data.channel_messages.map((m, i) => (
            <Stack.Item key={m.ref}>
              <Box bold>{m.title || `Story #${i + 1}`}</Box>
              <Box ml={1}>{m.body}</Box>
              {m.has_image ? (
                <Box ml={1} italic color="label">
                  (photo attached)
                </Box>
              ) : null}
              <Box ml={1} color="label" italic mt="2px">
                Story by {m.author} — {m.time_stamp}
              </Box>
            </Stack.Item>
          ))}
        </Stack>
      )}
      <Box mt={1}>
        <Button onClick={() => act('refresh')} icon="rotate-right">
          Refresh
        </Button>{' '}
        <Button onClick={() => act('set_screen', { screen: back_target ?? 1 })}>
          Back
        </Button>
      </Box>
    </Section>
  );
};

const ChannelPicker = (props: {
  data: Data;
  act: ActFn;
  title: string;
  description?: string;
  action: string;
  back_target?: number;
}) => {
  const { data, act, title, description, action, back_target } = props;
  return (
    <Section
      title={title}
      buttons={
        <Button onClick={() => act('set_screen', { screen: back_target ?? 0 })}>
          Back
        </Button>
      }
    >
      {description ? (
        <Box color="label" mb={1} italic>
          {description}
        </Box>
      ) : null}
      {data.channels.length === 0 ? (
        <EmptyState>No feed channels found active…</EmptyState>
      ) : (
        <Stack vertical>
          {data.channels.map((c) => (
            <Stack.Item key={c.ref}>
              <Button fluid onClick={() => act(action, { ref: c.ref })}>
                {c.name}
                {c.censored ? (
                  <Box ml={1} inline color="bad">
                    ***
                  </Box>
                ) : null}
              </Button>
            </Stack.Item>
          ))}
        </Stack>
      )}
    </Section>
  );
};

const Screen12 = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section
      title={data.channel?.name ?? '(no channel)'}
      buttons={
        <Button
          onClick={() => act('set_screen', { screen: 10 })}
          icon="chevron-left"
        >
          Back
        </Button>
      }
    >
      <Box mb={1}>
        Author:{' '}
        <Box inline color="bad">
          {data.channel?.author}
        </Box>{' '}
        <Button
          compact
          onClick={() =>
            data.channel &&
            act('censor_channel_author', { ref: data.channel.ref })
          }
        >
          {data.channel?.author === '[REDACTED]'
            ? 'Undo Author Censorship'
            : 'Censor Channel Author'}
        </Button>
      </Box>
      {data.channel_messages.length === 0 ? (
        <EmptyState>No feed messages found in channel…</EmptyState>
      ) : (
        <Stack vertical>
          {data.channel_messages.map((m) => (
            <Stack.Item key={m.ref}>
              <Box>{m.body}</Box>
              <Box ml={1} color="label" italic>
                Story by {m.author}
              </Box>
              <Box ml={1} mt="2px">
                <Button
                  compact
                  onClick={() => act('censor_story_body', { ref: m.ref })}
                >
                  {m.body === '[REDACTED]'
                    ? 'Undo story censorship'
                    : 'Censor story'}
                </Button>{' '}
                <Button
                  compact
                  onClick={() => act('censor_story_author', { ref: m.ref })}
                >
                  {m.author === '[REDACTED]'
                    ? 'Undo Author Censorship'
                    : 'Censor message Author'}
                </Button>
              </Box>
            </Stack.Item>
          ))}
        </Stack>
      )}
    </Section>
  );
};

const Screen13 = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  return (
    <Section
      title={data.channel?.name ?? '(no channel)'}
      buttons={
        <Button
          onClick={() => act('set_screen', { screen: 11 })}
          icon="chevron-left"
        >
          Back
        </Button>
      }
    >
      <Box mb={1}>
        Channel messages listed below. If dangerous to the station,{' '}
        <Button
          compact
          onClick={() =>
            data.channel && act('toggle_d_notice', { ref: data.channel.ref })
          }
        >
          Bestow a D-Notice upon the channel
        </Button>
        .
      </Box>
      {data.channel?.censored ? (
        <Box color="bad" bold>
          ATTENTION: This channel has been deemed as threatening to the welfare
          of the station, and marked with a {data.company_name} D-Notice. No
          further feed story additions are allowed while the D-Notice is in
          effect.
        </Box>
      ) : data.channel_messages.length === 0 ? (
        <EmptyState>No feed messages found…</EmptyState>
      ) : (
        <Stack vertical>
          {data.channel_messages.map((m) => (
            <Stack.Item key={m.ref}>
              <Box>{m.body}</Box>
              <Box ml={1} color="label" italic>
                Story by {m.author}
              </Box>
            </Stack.Item>
          ))}
        </Stack>
      )}
    </Section>
  );
};

const Screen14 = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  const wanted_already = !!data.has_wanted;
  const end_param = wanted_already ? 2 : 1;
  return (
    <Section title="Wanted Issue Handler" buttons={<BackButton act={act} />}>
      {wanted_already ? (
        <Box italic color="label" mb={1}>
          A wanted issue is already in Feed Circulation. You can edit or cancel
          it below.
        </Box>
      ) : null}
      <LabeledList>
        <LabeledList.Item label="Criminal Name">
          <Button onClick={() => act('set_wanted_name')}>
            {data.message?.author || '(unset)'}
          </Button>
        </LabeledList.Item>
        <LabeledList.Item label="Description">
          <Button onClick={() => act('set_wanted_desc')}>
            {data.message?.body || '(unset)'}
          </Button>
        </LabeledList.Item>
        <LabeledList.Item label={wanted_already ? 'Created by' : 'Prosecutor'}>
          <Box color="good">
            {wanted_already ? data.wanted_issue?.backup_author : data.signature}
          </Box>
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        <Button
          color="good"
          onClick={() => act('submit_wanted', { end_param })}
          icon={wanted_already ? 'pen' : 'paper-plane'}
        >
          {wanted_already ? 'Edit Issue' : 'Submit'}
        </Button>{' '}
        {wanted_already ? (
          <Button color="bad" icon="trash" onClick={() => act('cancel_wanted')}>
            Take down Issue
          </Button>
        ) : null}
      </Box>
    </Section>
  );
};

const Screen18 = (props: { data: Data; act: ActFn }) => {
  const { data, act } = props;
  const W = data.wanted_issue;
  return (
    <Section
      title="STATIONWIDE WANTED ISSUE"
      buttons={<BackButton act={act} />}
    >
      {!W ? (
        <EmptyState>No wanted issue.</EmptyState>
      ) : (
        <>
          <Box italic color="label" mb={1}>
            Submitted by {W.backup_author}
          </Box>
          <LabeledList>
            <LabeledList.Item label="Criminal">{W.author}</LabeledList.Item>
            <LabeledList.Item label="Description">{W.body}</LabeledList.Item>
            <LabeledList.Item label="Photo">
              {W.has_image ? '(photo attached)' : 'None'}
            </LabeledList.Item>
          </LabeledList>
        </>
      )}
    </Section>
  );
};

export const AdminNewscaster = () => {
  const { data, act } = useBackend<Data>();
  const s = data.screen;
  return (
    <Window width={680} height={680} title="Admin Newscaster">
      <Window.Content scrollable>
        {s === 0 ? <Screen0 data={data} act={act} /> : null}
        {s === 1 ? <Screen1 data={data} act={act} /> : null}
        {s === 2 ? <Screen2 data={data} act={act} /> : null}
        {s === 3 ? <Screen3 data={data} act={act} /> : null}
        {s === 4 ? (
          <InfoScreen
            data={data}
            act={act}
            title="Submission OK"
            body={`Feed story successfully submitted to ${data.channel?.name ?? ''}.`}
            color="good"
          />
        ) : null}
        {s === 5 ? (
          <InfoScreen
            data={data}
            act={act}
            title="Channel Created"
            body={`Feed Channel ${data.channel?.name ?? ''} created successfully.`}
            color="good"
          />
        ) : null}
        {s === 6 ? <Screen6 data={data} act={act} /> : null}
        {s === 7 ? <Screen7 data={data} act={act} /> : null}
        {s === 9 ? (
          <ChannelMessages data={data} act={act} back_target={1} />
        ) : null}
        {s === 10 ? (
          <ChannelPicker
            data={data}
            act={act}
            title={`${data.company_name} Feed Censorship Tool`}
            description="Total deletion of a Feed Story is not possible. Users attempting to view a censored feed will see [REDACTED]."
            action="pick_censor_channel"
            back_target={0}
          />
        ) : null}
        {s === 11 ? (
          <ChannelPicker
            data={data}
            act={act}
            title={`${data.company_name} D-Notice Handler`}
            description="A D-Notice will render a channel unable to be updated, without deleting feed stories it contains."
            action="pick_d_notice"
            back_target={0}
          />
        ) : null}
        {s === 12 ? <Screen12 data={data} act={act} /> : null}
        {s === 13 ? <Screen13 data={data} act={act} /> : null}
        {s === 14 ? <Screen14 data={data} act={act} /> : null}
        {s === 15 ? (
          <InfoScreen
            data={data}
            act={act}
            title="Wanted Issue Submitted"
            body={`Wanted issue for ${data.message?.author ?? ''} is now in Network Circulation.`}
            color="good"
          />
        ) : null}
        {s === 16 ? (
          <Section title="Error">
            <Box color="bad" bold mb={1}>
              ERROR: Wanted Issue rejected by Network.
            </Box>
            {!data.message?.author || data.message.author === '[REDACTED]' ? (
              <Box color="bad">Invalid name for person wanted.</Box>
            ) : null}
            {!data.message?.body || data.message.body === '[REDACTED]' ? (
              <Box color="bad">Invalid description.</Box>
            ) : null}
            <Box mt={1}>
              <BackButton act={act} />
            </Box>
          </Section>
        ) : null}
        {s === 17 ? (
          <InfoScreen
            data={data}
            act={act}
            title="Wanted Issue Deleted"
            body="Wanted Issue successfully deleted from Circulation."
            color="good"
          />
        ) : null}
        {s === 18 ? <Screen18 data={data} act={act} /> : null}
        {s === 19 ? (
          <InfoScreen
            data={data}
            act={act}
            title="Wanted Issue Edited"
            body={`Wanted issue for ${data.message?.author ?? ''} successfully edited.`}
            color="good"
          />
        ) : null}
      </Window.Content>
    </Window>
  );
};
