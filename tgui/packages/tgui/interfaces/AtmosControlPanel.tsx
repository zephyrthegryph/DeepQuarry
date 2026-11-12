import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, LabeledList, Section, Table } from 'tgui-core/components';
import type {
  AtmosControlPanelActions,
  AtmosControlPanelData,
} from './generated/AtmosControlPanel';
import { Label } from 'tgui/components/Label';

type Data = AtmosControlPanelData;

export const AtmosControlPanel = (props) => {
  const { act, data } = useBackend<Data, AtmosControlPanelActions>();
  const {
    excited_groups = [],
    active_size,
    hotspots_size,
    excited_size,
    conducting_size,
    frozen,
    show_all,
    fire_count,
    display_max,
    showing_user,
  } = data;

  return (
    <Window title="Atmospherics Debug" width={640} height={560}>
      <Window.Content scrollable>
        <Section title="Subsystem">
          <LabeledList>
            <LabeledList.Item label="Times fired">
              {fire_count}
            </LabeledList.Item>
            <LabeledList.Item label="Active turfs">
              {active_size}
            </LabeledList.Item>
            <LabeledList.Item label="Excited groups">
              {excited_size}
            </LabeledList.Item>
            <LabeledList.Item label="Hotspots">
              {hotspots_size}
            </LabeledList.Item>
            <LabeledList.Item label="Superconducting">
              {conducting_size}
            </LabeledList.Item>
          </LabeledList>
          <Box mt={1}>
            <Button
              icon={frozen ? 'play' : 'pause'}
              color={frozen ? 'good' : 'bad'}
              content={frozen ? 'Processing paused' : 'Processing running'}
              onClick={() => act('toggle-freeze')}
            />
            <Button
              icon="eye"
              selected={show_all}
              content="Show all groups"
              onClick={() => act('toggle_show_all')}
            />
            <Button
              icon="highlighter"
              selected={showing_user}
              content="Overlay on me"
              onClick={() => act('toggle_user_display')}
            />
          </Box>
        </Section>
        <Section title="Excited groups">
          {excited_groups.length === 0 ? (
            <Label>No excited groups.</Label>
          ) : (
            <Table>
              <Table.Row header>
                <Table.Cell>Area</Table.Cell>
                <Table.Cell collapsing>Size</Table.Cell>
                <Table.Cell collapsing>Breakdown</Table.Cell>
                <Table.Cell collapsing>Dismantle</Table.Cell>
                {!!display_max && <Table.Cell collapsing>Max share</Table.Cell>}
                <Table.Cell collapsing>Actions</Table.Cell>
              </Table.Row>
              {excited_groups.map((group) => (
                <Table.Row key={group.group}>
                  <Table.Cell>{group.area}</Table.Cell>
                  <Table.Cell collapsing>{group.size}</Table.Cell>
                  <Table.Cell collapsing>{group.breakdown}</Table.Cell>
                  <Table.Cell collapsing>{group.dismantle}</Table.Cell>
                  {!!display_max && (
                    <Table.Cell collapsing>{group.max_share}</Table.Cell>
                  )}
                  <Table.Cell collapsing>
                    <Button
                      icon="location-arrow"
                      tooltip="Jump to"
                      onClick={() =>
                        act('move-to-target', { spot: group.jump_to })
                      }
                    />
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
