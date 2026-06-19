import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Button, Section } from 'tgui-core/components';

import type { Data } from './types';
import { downloadPrefs } from './VorePanelExportDownload';

export const VorePanelExport = () => {
  return (
    <Window width={790} height={560} theme="abstract">
      <Window.Content>
        <VorePanelExportContent />
      </Window.Content>
    </Window>
  );
};

const VorePanelExportContent = () => {
  const { data } = useBackend<Data>();

  return (
    <Section title="Vore Export Panel">
      <Section title="Export">
        <Button
          fluid
          icon="file-alt"
          onClick={() => downloadPrefs('.html', data)}
        >
          Export (HTML)
        </Button>
        <Button
          fluid
          icon="file-alt"
          onClick={() => downloadPrefs('.vrdb', data)}
        >
          Export (VRDB)
        </Button>
      </Section>
    </Section>
  );
};
