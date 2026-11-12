import { Section, Stack } from 'tgui-core/components';
import { capitalize } from 'tgui-core/string';
import { sanitizeText } from '../../../../sanitize';
import type { CatalogData } from '../../types';

export const WikiCatalogPage = (props: { catalog: CatalogData }) => {
  const { catalog } = props;

  return (
    <Section fill scrollable title={capitalize(catalog.name)}>
      <Stack vertical fill>
        <Stack.Item grow>
          {/** biome-ignore lint/security/noDangerouslySetInnerHtml: Internal catalog pages */}
          <div
            dangerouslySetInnerHTML={{ __html: sanitizeText(catalog.desc) }}
          />
        </Stack.Item>
      </Stack>
    </Section>
  );
};
