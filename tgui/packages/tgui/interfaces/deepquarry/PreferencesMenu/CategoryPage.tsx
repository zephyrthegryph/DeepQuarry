// DQAdd — Renders a single category page.
//
// Layout strategy:
//  - Page level: CSS grid auto-fit minmax(380, 1fr). On the standard left pane
//    (~1100 px at the 3:1 Stack ratio) we get ~2-3 group panels per row.
//  - Major editors span all columns via `gridColumn: '1 / -1'`.
//  - Inside each group, widgets pack as a sub-grid auto-fit minmax(220, 1fr).
//  - Group containers are tight `fitted` Sections so the padding tax is paid
//    once at the page level, not nested at every group.
//  - No collapse/expand. Every group renders its content; long-form widgets
//    (longtext) have been compacted (TextArea height 3em) so they don't
//    dominate vertical space.

import { Box, Section } from 'tgui-core/components';
import { getEditor } from './editors';
import { labelForGroup, labelForKey } from './labels';
import { PrefWidget } from './PrefWidget';
import {
  editorAnchor,
  groupAnchor,
  highlightStyle,
  prefAnchor,
  useSearchHighlight,
} from './search';
import type {
  PrefCategory,
  PrefGroup,
  PrefGroupItem,
  PrefWidgetItem,
} from './types';

type Props = {
  page: PrefCategory;
  staticData?: Record<string, Record<string, unknown>>;
  values: Record<string, unknown>;
  editorData: Record<string, Record<string, unknown>>;
  /// When true, this page hosts a full-height editor (e.g. loadout). Skip the
  /// grid layout and let the editor own the container directly.
  fillHeight?: boolean;
};

/// Editors whose own UI is wide enough that a half-column grid cell can't
/// host them comfortably. Groups containing one of these get
/// `gridColumn: '1 / -1'` so they fill the full content width.
const FULL_WIDTH_EDITORS = new Set<string>([
  'trait_picker',
  'occupation',
  'antag_optin',
  'organs',
  'body_markings',
  'flavor',
  'vore_messages',
  'language',
]);

export const CategoryPage = ({
  page,
  staticData,
  values,
  editorData,
  fillHeight,
}: Props) => {
  if (fillHeight) {
    return (
      <Box style={{ height: '100%' }}>
        {page.groups.map((group, gi) => (
          <GroupBlock
            key={`${gi}-${group.group}`}
            category={page.category}
            group={group}
            staticData={staticData}
            values={values}
            editorData={editorData}
            fillHeight
          />
        ))}
      </Box>
    );
  }

  return (
    <Box
      style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(380px, 1fr))',
        gap: '6px',
        alignItems: 'start',
      }}
    >
      {page.groups.map((group, gi) => {
        const containsFullWidthEditor = group.items.some(
          (i) => i.type === 'editor' && FULL_WIDTH_EDITORS.has(i.key),
        );
        return (
          <Box
            key={`${gi}-${group.group}`}
            style={
              containsFullWidthEditor ? { gridColumn: '1 / -1' } : undefined
            }
          >
            <GroupBlock
              category={page.category}
              group={group}
              staticData={staticData}
              values={values}
              editorData={editorData}
            />
          </Box>
        );
      })}
    </Box>
  );
};

/// Widget rows inside a single group: a two-column grid (label, control) sized in em so it
/// follows the theme font and the display scale. The label column fits the longest label up to
/// a cap and wraps beyond it, so a long label never pushes the control out of the panel.
export const WidgetGrid = ({
  widgets,
  values,
}: {
  widgets: PrefWidgetItem[];
  values: Record<string, unknown>;
}) => (
  <Box
    style={{
      display: 'grid',
      gridTemplateColumns: 'minmax(6em, max-content) minmax(0, 1fr)',
      columnGap: '0.75em',
      rowGap: '0.3em',
      alignItems: 'center',
    }}
  >
    {widgets.map((item) => (
      <WidgetRow key={item.key} item={item} values={values} />
    ))}
  </Box>
);

const WidgetRow = ({
  item,
  values,
}: {
  item: PrefWidgetItem;
  values: Record<string, unknown>;
}) => {
  const anchor = prefAnchor(item.key);
  const lit = useSearchHighlight(anchor);
  return (
    <Box
      data-dq-anchor={anchor}
      style={{
        display: 'contents',
      }}
    >
      <Box
        color="label"
        style={{
          maxWidth: '14em',
          overflowWrap: 'anywhere',
          ...highlightStyle(lit),
        }}
      >
        {labelForKey(item.key, item.label)}:
      </Box>
      <Box style={{ minWidth: 0, ...highlightStyle(lit) }}>
        <PrefWidget
          item={{
            ...item,
            value: Object.hasOwn(values, item.key)
              ? values[item.key]
              : item.value,
          }}
        />
      </Box>
    </Box>
  );
};

const GroupBlock = ({
  category,
  group,
  staticData,
  values,
  editorData,
  fillHeight,
}: {
  category: string;
  group: PrefGroup;
  staticData?: Record<string, Record<string, unknown>>;
  values: Record<string, unknown>;
  editorData: Record<string, Record<string, unknown>>;
  fillHeight?: boolean;
}) => {
  const widgets = group.items.filter(
    (i): i is PrefWidgetItem => i.type === 'widget',
  );
  const editors = group.items.filter((i) => i.type === 'editor');
  const hasTitle = !!group.group;
  const anchor = groupAnchor(category, group.group);
  const lit = useSearchHighlight(anchor);

  // Full-height editor pages (Loadout, Mind & Body) MUST fill the panel. Render the editor(s)
  // directly in a height:100% container even when the group carries a title — a titled, non-fill
  // Section (the path below) has no height:100% and collapses the editor to its content height,
  // which left the loadout catalog filling only ~half the window (the paper-doll column height).
  // These pages are single-editor by design, so dropping the redundant group frame is fine.
  if (fillHeight) {
    return (
      <Box style={{ height: '100%' }}>
        {editors.map((item, idx) => (
          <EditorBlock
            key={`editor:${item.key}-${idx}`}
            item={item}
            editorData={editorData}
            staticData={staticData}
          />
        ))}
      </Box>
    );
  }

  // Bare-frame mode: no group title and no widgets — just render the editors
  // directly. Used by groups that only carry an editor.
  if (!hasTitle && widgets.length === 0) {
    return (
      <Box>
        {editors.map((item, idx) => (
          <EditorBlock
            key={`editor:${item.key}-${idx}`}
            item={item}
            editorData={editorData}
            staticData={staticData}
          />
        ))}
      </Box>
    );
  }

  return (
    <Section
      title={hasTitle ? labelForGroup(group.group) : null}
      data-dq-anchor={anchor}
      style={highlightStyle(lit)}
    >
      {widgets.length > 0 && <WidgetGrid widgets={widgets} values={values} />}
      {editors.map((item, idx) => (
        <Box
          key={`editor:${item.key}-${idx}`}
          mt={widgets.length > 0 ? 0.5 : 0}
        >
          <EditorBlock
            item={item}
            editorData={editorData}
            staticData={staticData}
          />
        </Box>
      ))}
    </Section>
  );
};

const EditorBlock = ({
  item,
  editorData,
  staticData,
}: {
  item: PrefGroupItem;
  editorData: Record<string, Record<string, unknown>>;
  staticData?: Record<string, Record<string, unknown>>;
}) => {
  const anchor = editorAnchor(item.key);
  const lit = useSearchHighlight(anchor);
  if (item.type !== 'editor') return null;
  const Editor = getEditor(item.key);
  return (
    <Box
      data-dq-anchor={anchor}
      style={{ height: '100%', ...highlightStyle(lit) }}
    >
      <Editor
        data={editorData[item.key] ?? item.data ?? {}}
        staticData={staticData?.[item.key]}
      />
    </Box>
  );
};
