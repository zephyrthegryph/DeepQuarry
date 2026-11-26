/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { useAtomValue } from 'jotai';
import { Color } from 'tgui-core/color';
import { Box } from 'tgui-core/components';
import { gameAtom } from '../game/atoms';
import { ReconnectStatus } from '../reconnect';
import { useSettings } from '../settings/use-settings';
import { pingAtom } from './atoms';

export function PingIndicator(props) {
  const ping = useAtomValue(pingAtom);
  const game = useAtomValue(gameAtom);
  const { settings } = useSettings();
  const down = !!game.connectionLostAt || !!game.roundRestartedAt;
  const color = Color.lookup(ping.networkQuality, [
    new Color(220, 40, 40),
    new Color(220, 200, 40),
    new Color(60, 220, 40),
  ]).toString();

  const roundtrip = ping.roundtrip ? ping.roundtrip.toFixed() : '--';

  if (down && settings.showReconnectWarning) {
    return (
      <div className="Ping Ping--down">
        <Box className="Ping__indicator" />
        <ReconnectStatus restarting={!!game.roundRestartedAt} />
      </div>
    );
  }

  return (
    <div className="Ping">
      <Box className="Ping__indicator" backgroundColor={color} />
      {roundtrip}
    </div>
  );
}
