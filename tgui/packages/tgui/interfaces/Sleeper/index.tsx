import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import type { SleeperActions } from '../generated/Sleeper';
import { SleeperEmpty } from './SleeperEmpty';
import { SleeperMain } from './SleeperMain';
import type { Data } from './types';

export const Sleeper = (props) => {
  const { data } = useBackend<Data, SleeperActions>();
  const { hasOccupant } = data;
  const body = hasOccupant ? <SleeperMain /> : <SleeperEmpty />;
  return (
    <Window width={550} height={760}>
      <Window.Content scrollable className="Layout__content--flexColumn">
        {body}
      </Window.Content>
    </Window>
  );
};
