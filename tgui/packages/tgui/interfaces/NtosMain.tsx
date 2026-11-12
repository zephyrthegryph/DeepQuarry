import { useBackend } from 'tgui/backend';
import { NtosWindow } from 'tgui/layouts';
import { Button, Section, Table } from 'tgui-core/components';
import type { NtosMainActions, NtosMainData } from './generated/NtosMain';

const PROGRAM_ICONS = {
  compconfig: 'cog',
  ntndownloader: 'download',
  filemanager: 'folder',
  smmonitor: 'radiation',
  alarmmonitor: 'bell',
  cardmod: 'id-card',
  arcade: 'gamepad',
  ntnrc_client: 'comment-alt',
  nttransfer: 'exchange-alt',
  powermonitor: 'plug',
  job_manage: 'address-book',
  crewmani: 'clipboard-list',
  robocontrol: 'robot',
  atmosscan: 'thermometer-half',
  shipping: 'tags',
};

export const NtosMain = (props) => {
  const { act, data } = useBackend<NtosMainData, NtosMainActions>();
  const {
    PC_device_theme: device_theme,
    programs,
    removable_media,
    login,
  } = data;
  return (
    <NtosWindow
      title={
        (device_theme === 'syndicate' && 'Syndix Main Menu') || 'NtOS Main Menu'
      }
      theme={device_theme}
      width={400}
      height={500}
    >
      <NtosWindow.Content scrollable>
        <Section
          title="User Login"
          buttons={
            <Button
              icon="eject"
              disabled={!login.IDName}
              onClick={() => act('PC_Eject_Disk', { name: 'ID' })}
            >
              Eject ID
            </Button>
          }
        >
          <Table>
            <Table.Row>
              <Table.Cell>ID Name: {login.IDName}</Table.Cell>
            </Table.Row>
            <Table.Row>
              <Table.Cell>Assignment: {login.IDJob}</Table.Cell>
            </Table.Row>
          </Table>
        </Section>
        {!!removable_media.length && (
          <Section title="Media Eject">
            <Table>
              {removable_media.map((device) => (
                <Table.Row key={device}>
                  <Table.Cell>
                    <Button
                      fluid
                      color="transparent"
                      icon="eject"
                      onClick={() => act('PC_Eject_Disk', { name: device })}
                    >
                      {device}
                    </Button>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table>
          </Section>
        )}
        <Section title="Programs">
          <Table>
            {programs.map((program) => (
              <Table.Row key={program.name}>
                <Table.Cell>
                  <Button
                    fluid
                    color="transparent"
                    icon={PROGRAM_ICONS[program.name] || 'window-maximize-o'}
                    onClick={() =>
                      act('PC_runprogram', {
                        name: program.name,
                      })
                    }
                  >
                    {program.desc}
                  </Button>
                </Table.Cell>
                <Table.Cell collapsing width="18px">
                  {!!program.running && (
                    <Button
                      color="transparent"
                      icon="times"
                      tooltip="Close program"
                      tooltipPosition="left"
                      onClick={() =>
                        act('PC_killprogram', {
                          name: program.name,
                        })
                      }
                    />
                  )}
                </Table.Cell>
                <Table.Cell collapsing width="18px">
                  <Button
                    color="transparent"
                    tooltip="Set Autorun"
                    tooltipPosition="left"
                    selected={program.autorun}
                    onClick={() =>
                      act('PC_setautorun', {
                        name: program.name,
                      })
                    }
                  >
                    AR
                  </Button>
                </Table.Cell>
              </Table.Row>
            ))}
          </Table>
        </Section>
      </NtosWindow.Content>
    </NtosWindow>
  );
};
