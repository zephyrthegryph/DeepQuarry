// DQAdd — Renders a single category page: list of groups, each containing widgets and
// editors interleaved by sort_order. Single-column LabeledList — predictable, fits any
// reasonable window width, no horizontal overflow.
//
// Groups with `collapsed: true` from the server render as collapsed-by-default Sections
// that the user can expand. Used for niche content (records, OOC notes, PAI, NIF, etc).

import { useEffect, useState } from 'react';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';
import { getEditor } from './editors';
import { PrefWidget } from './PrefWidget';
import type { PrefCategory, PrefGroup, PrefGroupItem, PrefWidgetItem } from './types';

type Props = {
  page: PrefCategory;
  staticData?: Record<string, Record<string, unknown>>;
  /// When true, this page hosts a full-height editor (e.g. loadout). Skip the default
  /// `mb` spacing and propagate `height: 100%` so the editor can use the entire
  /// available column.
  fillHeight?: boolean;
};

const titleCase = (s: string) =>
  s.replace(/(^|[_\s])([a-z])/g, (_, sep, ch) => (sep ? ' ' : '') + ch.toUpperCase());

export const CategoryPage = ({ page, staticData, fillHeight }: Props) => (
  <Box style={fillHeight ? { height: '100%' } : undefined}>
    {page.groups.map((group, gi) => (
      <GroupBlock
        key={`${gi}-${group.group}`}
        group={group}
        staticData={staticData}
        fillHeight={fillHeight}
      />
    ))}
  </Box>
);

const GroupBlock = ({
  group,
  staticData,
  fillHeight,
}: {
  group: PrefGroup;
  staticData?: Record<string, Record<string, unknown>>;
  fillHeight?: boolean;
}) => {
  const widgets = group.items.filter(
    (i): i is PrefWidgetItem => i.type === 'widget',
  );
  const editors = group.items.filter((i) => i.type === 'editor');
  const hasTitle = !!group.group;
  const isCollapsible = hasTitle && !!group.collapsed;
  // Track the *server-declared* default so a later state change (server flips a group
  // from collapsed → expanded due to a constraint or other condition) re-applies.
  // Without resync, the local state captures only the initial mount value.
  const [expanded, setExpanded] = useState<boolean>(!isCollapsible);
  useEffect(() => {
    setExpanded(!isCollapsible);
  }, [isCollapsible]);

  // Bare-frame mode: no group title and no widgets — just render the editors directly.
  if (!hasTitle && widgets.length === 0) {
    return (
      <Box
        mb={fillHeight ? 0 : 1}
        style={fillHeight ? { height: '100%' } : undefined}
      >
        {editors.map((item, idx) => (
          <EditorBlock
            key={`editor:${item.key}-${idx}`}
            item={item}
            staticData={staticData}
          />
        ))}
      </Box>
    );
  }

  return (
    <Section
      title={hasTitle ? titleCase(group.group) : null}
      mb={1}
      buttons={
        isCollapsible ? (
          <Button
            icon={expanded ? 'chevron-up' : 'chevron-down'}
            onClick={() => setExpanded((v) => !v)}
          >
            {expanded ? 'Collapse' : 'Expand'}
          </Button>
        ) : null
      }
    >
      {!expanded && (
        <Box italic color="label" fontSize="0.9em">
          {widgets.length + editors.length} item
          {widgets.length + editors.length === 1 ? '' : 's'} hidden — click
          Expand to view.
        </Box>
      )}
      {expanded && (
        <>
          {widgets.length > 0 && (
            <LabeledList>
              {widgets.map((item) => (
                <LabeledList.Item
                  key={item.key}
                  label={item.label ?? titleCase(item.key)}
                >
                  <PrefWidget item={item} />
                </LabeledList.Item>
              ))}
            </LabeledList>
          )}
          {editors.map((item, idx) => (
            <Box
              key={`editor:${item.key}-${idx}`}
              mt={widgets.length > 0 ? 1 : 0}
            >
              <EditorBlock item={item} staticData={staticData} />
            </Box>
          ))}
        </>
      )}
    </Section>
  );
};

const EditorBlock = ({
  item,
  staticData,
}: {
  item: PrefGroupItem;
  staticData?: Record<string, Record<string, unknown>>;
}) => {
  if (item.type !== 'editor') return null;
  const Editor = getEditor(item.key);
  return <Editor data={item.data} staticData={staticData?.[item.key]} />;
};
