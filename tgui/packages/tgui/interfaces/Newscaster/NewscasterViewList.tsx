import { useBackend } from 'tgui/backend';
import { Button, Section } from 'tgui-core/components';
import { decodeHtmlEntities } from 'tgui-core/string';
import type {
  NewscasterActions,
  NewscasterData,
} from '../generated/Newscaster';
import {
  NEWSCASTER_SCREEN_MAIN,
  NEWSCASTER_SCREEN_SELECTEDCHANNEL,
} from './constants';

export const NewscasterViewList = (props: {
  setScreen: React.Dispatch<React.SetStateAction<string>>;
}) => {
  const { act, data } = useBackend<NewscasterData, NewscasterActions>();

  const { channels } = data;

  const { setScreen } = props;

  return (
    <Section
      title="Station Feed Channels"
      buttons={
        <Button icon="undo" onClick={() => setScreen(NEWSCASTER_SCREEN_MAIN)}>
          Back
        </Button>
      }
    >
      {channels.map((channel) => (
        <Button
          fluid
          key={channel.name}
          icon="eye"
          color={channel.admin ? 'good' : channel.censored ? 'bad' : ''}
          onClick={() => {
            act('show_channel', { show_channel: channel.ref });
            setScreen(NEWSCASTER_SCREEN_SELECTEDCHANNEL);
          }}
        >
          {decodeHtmlEntities(channel.name)}
        </Button>
      ))}
    </Section>
  );
};
