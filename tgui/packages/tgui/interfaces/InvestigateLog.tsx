// Admin Investigate log viewer — structured TGUI.

import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Section } from 'tgui-core/components';
import { EmptyState } from './common/EmptyState';
import { HtmlRenderer } from './common/HtmlRenderer';

type Data = {
  subject: string;
  log_text: string;
};

export const InvestigateLog = () => {
  const { data } = useBackend<Data>();
  const { subject, log_text } = data;
  return (
    <Window width={720} height={620} title={`Investigate: ${subject}`}>
      <Window.Content scrollable>
        <Section title={`Investigate: ${subject}`}>
          {log_text ? (
            <HtmlRenderer html={log_text} />
          ) : (
            <EmptyState>(empty log)</EmptyState>
          )}
        </Section>
      </Window.Content>
    </Window>
  );
};
