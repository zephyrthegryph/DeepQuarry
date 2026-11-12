import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import type { BodyScannerActions } from '../generated/BodyScanner';
import { BodyScannerEmpty } from './BodyScannerEmpty';
import { BodyScannerMain } from './BodyScannerMain';
import type { Data, occupant } from './types';

export const BodyScanner = (props) => {
  const { data } = useBackend<Data, BodyScannerActions>();
  const { occupied, occupant = {} as occupant } = data;
  const body = occupied ? (
    <BodyScannerMain occupant={occupant} />
  ) : (
    <BodyScannerEmpty />
  );
  return (
    <Window width={690} height={600}>
      <Window.Content scrollable className="Layout__content--flexColumn">
        {body}
      </Window.Content>
    </Window>
  );
};
6;
