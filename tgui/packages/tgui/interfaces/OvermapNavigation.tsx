import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, LabeledList, Section } from 'tgui-core/components';

import { OvermapFlightData } from './common/Overmap';
import type {
  OvermapNavigationActions,
  OvermapNavigationData,
} from './generated/OvermapNavigation';

export const OvermapNavigation = () => {
  return (
    <Window width={380} height={530}>
      <Window.Content>
        <OvermapNavigationContent />
      </Window.Content>
    </Window>
  );
};

type Data = OvermapNavigationData;

export const OvermapNavigationContent = (props) => {
  const { act, data } = useBackend<Data, OvermapNavigationActions>();
  const { sector, s_x, s_y, sector_info, viewing } = data;
  return (
    <>
      <Section
        title="Current Location"
        buttons={
          <Button icon="eye" selected={viewing} onClick={() => act('viewing')}>
            Map View
          </Button>
        }
      >
        <LabeledList>
          <LabeledList.Item label="Current Location">{sector}</LabeledList.Item>
          <LabeledList.Item label="Coordinates">
            {s_x} : {s_y}
          </LabeledList.Item>
          <LabeledList.Item label="Additional Information">
            {sector_info}
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section title="Flight Data">
        <OvermapFlightData disableLimiterControls />
      </Section>
    </>
  );
};
