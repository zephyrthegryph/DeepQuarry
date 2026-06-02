// DQAdd — Cyborg module + chassis picker (Looks tab, robot mode).
//
// Trigger row shows the current Module + Chassis with the chassis thumbnail.
// Clicking Change opens a fullscreen modal overlay (matching SpeciesPicker)
// with a Module selector at the top and a grid of chassis cards showing each
// chassis's actual sprite thumbnail.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Box, Button, Dropdown, LabeledList, Stack } from 'tgui-core/components';
import { ColorizedImage } from '../helper_components';
import type { EditorProps } from './index';

type Data = {
  module: string;
  chassis: string;
};

type Static = {
  all_modules: string[];
  chassis_by_module: Record<string, string[]>;
  chassis_thumbs: Record<string, { icon: string; icon_state: string }>;
};

const send = (
  act: ReturnType<typeof useBackend>['act'],
  action: string,
  params: Record<string, unknown>,
) => act('dq_editor_action', { editor: 'robot_chassis', action, params });

export const RobotChassisPicker = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as Data;
  const s = (staticData ?? {}) as Static;
  const [open, setOpen] = useState(false);

  const allModules = s.all_modules ?? [];
  const chassisOptions: string[] = d.module
    ? (s.chassis_by_module?.[d.module] ?? [])
    : [];
  const thumbs = s.chassis_thumbs ?? {};
  const currentThumb = d.chassis ? thumbs[d.chassis] : undefined;

  const moduleOpts = [
    { value: '', displayText: '— Choose a module —' },
    ...allModules.map((m) => ({ value: m, displayText: m })),
  ];
  const currentModuleLabel =
    moduleOpts.find((o) => o.value === (d.module ?? ''))?.displayText ??
    d.module;

  return (
    <>
      <LabeledList>
        <LabeledList.Item label="Department">
          <Dropdown
            fluid
            selected={d.module ?? ''}
            displayText={currentModuleLabel}
            options={moduleOpts}
            onSelected={(v) => send(act, 'set_module', { value: v })}
          />
        </LabeledList.Item>
        <LabeledList.Item label="Chassis">
          <Stack align="center">
            {currentThumb && (
              <Stack.Item>
                <ColorizedImage
                  iconRef={currentThumb.icon}
                  iconState={currentThumb.icon_state}
                  color="#ffffff"
                  size={48}
                />
              </Stack.Item>
            )}
            <Stack.Item grow style={{ minWidth: 0 }}>
              <Box
                bold
                style={{
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                }}
              >
                {d.chassis || 'No chassis chosen'}
              </Box>
            </Stack.Item>
            <Stack.Item>
              <Button
                icon="pen"
                disabled={!d.module}
                onClick={() => setOpen(true)}
              >
                Change
              </Button>
            </Stack.Item>
          </Stack>
        </LabeledList.Item>
      </LabeledList>
      <Box mt={0.5} italic fontSize="0.82em" color="label">
        Picking these in chargen skips the popup that normally appears when you
        spawn as a cyborg.
      </Box>
      {open && (
        <ChassisPickerModal
          allModules={allModules}
          chassisOptions={chassisOptions}
          thumbs={thumbs}
          selectedModule={d.module ?? ''}
          selectedChassis={d.chassis ?? ''}
          moduleOpts={moduleOpts}
          currentModuleLabel={currentModuleLabel}
          onSelectModule={(v) => send(act, 'set_module', { value: v })}
          onSelectChassis={(v) => {
            send(act, 'set_chassis', { value: v });
            setOpen(false);
          }}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
};

type ModalProps = {
  allModules: string[];
  chassisOptions: string[];
  thumbs: Record<string, { icon: string; icon_state: string }>;
  selectedModule: string;
  selectedChassis: string;
  moduleOpts: { value: string; displayText: string }[];
  currentModuleLabel: string;
  onSelectModule: (v: string) => void;
  onSelectChassis: (v: string) => void;
  onClose: () => void;
};

const ChassisPickerModal = ({
  chassisOptions,
  thumbs,
  selectedModule,
  selectedChassis,
  moduleOpts,
  currentModuleLabel,
  onSelectModule,
  onSelectChassis,
  onClose,
}: ModalProps) => (
  <Box
    style={{
      position: 'fixed',
      inset: 0,
      zIndex: 1000,
      background: 'rgba(0,0,0,0.85)',
      display: 'flex',
      flexDirection: 'column',
      padding: '12px',
    }}
  >
    <Box
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '8px',
        marginBottom: '8px',
      }}
    >
      <Box bold fontSize="1.1em" style={{ marginRight: 'auto' }}>
        Choose a Cyborg Chassis
      </Box>
      <Box style={{ minWidth: '220px' }}>
        <Dropdown
          fluid
          selected={selectedModule}
          displayText={currentModuleLabel}
          options={moduleOpts}
          onSelected={(v) => onSelectModule(v)}
        />
      </Box>
      <Button icon="xmark" color="bad" onClick={onClose}>
        Close
      </Button>
    </Box>
    {!selectedModule ? (
      <Box
        style={{
          flex: 1,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: 'rgba(255,255,255,0.5)',
          fontSize: '1em',
        }}
      >
        Pick a module above to see the chassis options.
      </Box>
    ) : (
      <Box
        style={{
          flex: 1,
          minHeight: 0,
          overflowY: 'auto',
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))',
          gap: '8px',
          alignContent: 'start',
        }}
      >
        <ChassisCard
          name=""
          label="— Default chassis —"
          thumb={undefined}
          isSelected={!selectedChassis}
          onClick={() => onSelectChassis('')}
        />
        {chassisOptions.map((name) => (
          <ChassisCard
            key={name}
            name={name}
            label={name}
            thumb={thumbs[name]}
            isSelected={name === selectedChassis}
            onClick={() => onSelectChassis(name)}
          />
        ))}
      </Box>
    )}
  </Box>
);

const ChassisCard = ({
  label,
  thumb,
  isSelected,
  onClick,
}: {
  name: string;
  label: string;
  thumb?: { icon: string; icon_state: string };
  isSelected: boolean;
  onClick: () => void;
}) => (
  <Box
    onClick={onClick}
    style={{
      cursor: 'pointer',
      padding: '8px',
      borderRadius: '4px',
      background: isSelected
        ? 'rgba(52,152,219,0.22)'
        : 'rgba(255,255,255,0.04)',
      border: isSelected
        ? '1px solid rgba(52,152,219,0.7)'
        : '1px solid rgba(255,255,255,0.08)',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: '4px',
      minHeight: '120px',
    }}
  >
    <Box
      style={{
        flex: 1,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '64px',
      }}
    >
      {thumb ? (
        <ColorizedImage
          iconRef={thumb.icon}
          iconState={thumb.icon_state}
          color="#ffffff"
          size={64}
        />
      ) : (
        <Box color="label" fontSize="0.8em">
          (default)
        </Box>
      )}
    </Box>
    <Box
      bold
      fontSize="0.9em"
      style={{
        textAlign: 'center',
        width: '100%',
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        whiteSpace: 'nowrap',
      }}
    >
      {label}
    </Box>
  </Box>
);
