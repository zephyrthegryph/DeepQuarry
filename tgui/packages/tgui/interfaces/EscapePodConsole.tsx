import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Box, Button, Section } from 'tgui-core/components';
import type {
  EscapePodConsoleActions,
  EscapePodConsoleData,
} from './generated/EscapePodConsole';
import {
  EscapePodControls,
  EscapePodStatus,
} from './EmbeddedController/EmbeddedControllerHelpers';

/**
 * These are the least airlock-like UIs here, but they're "close enough".
 * Replaces escape_pod_console.tmpl
 */
const EscapePodConsoleContent = () => {
  const { act, data } = useBackend<
    EscapePodConsoleData,
    EscapePodConsoleActions
  >();

  const {
    exterior_status,
    docking_status,
    override_enabled,
    armed,
    can_force,
  } = data;

  return (
    <>
      <EscapePodStatus
        exterior_status={exterior_status}
        docking_status={docking_status}
        armed={armed}
      />
      <Section title="Controls">
        <EscapePodControls
          docking_status={docking_status}
          override_enabled={override_enabled}
        />
        <Box>
          <Button
            icon="exclamation-triangle"
            disabled={armed}
            color={armed ? 'bad' : 'average'}
            onClick={() => act('manual_arm')}
          >
            ARM
          </Button>
          <Button
            icon="exclamation-triangle"
            disabled={!can_force}
            color="bad"
            onClick={() => act('force_launch')}
          >
            MANUAL EJECT
          </Button>
        </Box>
      </Section>
    </>
  );
};

export const EscapePodConsole = () => (
  <Window width={500} height={400}>
    <Window.Content>
      <EscapePodConsoleContent />
    </Window.Content>
  </Window>
);
