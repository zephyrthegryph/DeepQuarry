import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Section } from 'tgui-core/components';
import type {
  EscapePodBerthConsoleActions,
  EscapePodBerthConsoleData,
} from './generated/EscapePodBerthConsole';
import {
  EscapePodControls,
  EscapePodStatus,
} from './EmbeddedController/EmbeddedControllerHelpers';

/**
 * These are the least airlock-like UIs here, but they're "close enough".
 * Replaces escape_pod_berth_console.tmpl
 */
const EscapePodBerthConsoleContent = () => {
  const { data } = useBackend<
    EscapePodBerthConsoleData,
    EscapePodBerthConsoleActions
  >();

  const { exterior_status, docking_status, armed, override_enabled } = data;

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
      </Section>
    </>
  );
};

export const EscapePodBerthConsole = () => (
  <Window width={500} height={400}>
    <Window.Content>
      <EscapePodBerthConsoleContent />
    </Window.Content>
  </Window>
);
