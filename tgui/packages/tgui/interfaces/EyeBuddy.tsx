// Eye Buddy press camera / bodycam — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, LabeledList, Section } from 'tgui-core/components';
import type { BooleanLike } from 'tgui-core/react';
import { EmptyState } from './common/EmptyState';

type Data = {
  channel: string;
  video_on: BooleanLike;
  audio_on: BooleanLike;
  showing_name: string | null;
  frequency: string;
};

export const EyeBuddy = () => {
  const { data, act } = useBackend<Data>();
  const { channel, video_on, audio_on, showing_name, frequency } = data;
  return (
    <Window width={440} height={300} title="Eye Buddy">
      <Window.Content>
        <Section title="Eye Buddy">
          <LabeledList>
            <LabeledList.Item label="Channel">
              <Button onClick={() => act('set_channel')} icon="pen">
                {channel}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Video">
              <Button
                selected={!!video_on}
                color={video_on ? 'good' : 'bad'}
                onClick={() => act('toggle_video')}
              >
                {video_on ? 'On' : 'Off'}
              </Button>
            </LabeledList.Item>
            {showing_name ? (
              <LabeledList.Item label="Showing">
                <EmptyState>{showing_name}</EmptyState>
              </LabeledList.Item>
            ) : null}
            <LabeledList.Item label="Mic">
              <Button
                selected={!!audio_on}
                color={audio_on ? 'good' : 'bad'}
                onClick={() => act('toggle_audio')}
              >
                {audio_on ? 'On' : 'Off'}
              </Button>
            </LabeledList.Item>
            <LabeledList.Item label="Frequency">{frequency}</LabeledList.Item>
          </LabeledList>
        </Section>
      </Window.Content>
    </Window>
  );
};
