import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button } from 'tgui-core/components';

import type {
  XenoarchReplicatorActions,
  XenoarchReplicatorData,
} from './generated/XenoarchReplicator';

type Data = XenoarchReplicatorData;

export const XenoarchReplicator = (props) => {
  const { act, data } = useBackend<Data, XenoarchReplicatorActions>();

  const { tgui_construction = [] } = data;

  return (
    <Window theme="abductor" width={400} height={400}>
      <Window.Content scrollable>
        {tgui_construction.map((button, i) => (
          <Button
            key={button.key}
            color={button.background}
            icon={button.icon}
            iconColor={button.foreground}
            fontSize={4}
            onClick={() => act('construct', { key: button.key })}
          />
        ))}
      </Window.Content>
    </Window>
  );
};
