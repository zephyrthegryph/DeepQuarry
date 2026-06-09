// DQAdd — Fallback editor shown when an editor key has no matching React component in
// PREF_EDITORS. Visible warning + raw data dump so the gap is obvious in any environment.
// This should never be reachable in production once every /datum/preference_editor subtype
// has its component registered.

import { Box, NoticeBox, Section } from 'tgui-core/components';
import type { EditorProps } from './index';

export const PlaceholderEditor = ({ data }: EditorProps) => (
  <Section title="Editor missing">
    <NoticeBox danger>
      A composite editor was registered server-side but no React component is bound to its
      key in PREF_EDITORS. Add it to{' '}
      <code>tgui/packages/tgui/interfaces/deepquarry/PreferencesMenu/editors/index.ts</code>.
    </NoticeBox>
    <Box as="pre" style={{ overflow: 'auto', maxHeight: '20em' }}>
      {JSON.stringify(data, null, 2)}
    </Box>
  </Section>
);
