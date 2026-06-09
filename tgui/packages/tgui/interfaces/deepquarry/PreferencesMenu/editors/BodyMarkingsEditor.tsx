// DQAdd — Body markings editor. Each marking shows a live colorized sprite preview
// overlaid on a human silhouette. Picker has a search field and uses thumbnail buttons.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { getIconFromRefMap } from 'tgui/events/handlers/assets';
import {
  Box,
  Button,
  ColorBox,
  Dimmer,
  Input,
  LabeledList,
  Section,
  Stack,
} from 'tgui-core/components';
import {
  ColorizedImage,
  ColorizedImageButton,
  getImage,
} from '../helper_components';
import type { EditorProps } from './index';

type ZoneState = { color: string; on: number };
type MarkingState = Record<string, ZoneState>;
type MarkingsData = { markings: Record<string, MarkingState> };
type MarkingStyleMeta = {
  name: string;
  body_parts: string[];
  icon?: string;
  icon_state?: string;
};
type MarkingStatic = {
  available_styles: Record<string, MarkingStyleMeta>;
};

const send = (
  act: ReturnType<typeof useBackend>['act'],
  action: string,
  params: Record<string, unknown>,
) => act('dq_editor_action', { editor: 'body_markings', action, params });

/// Returns a postRender callback that overlays a human silhouette behind the marking sprite.
const humanBackground = async (ctx: OffscreenCanvasRenderingContext2D) => {
  ctx.save();
  ctx.globalCompositeOperation = 'destination-over';
  const iconRef = getIconFromRefMap('icons/mob/human.dmi');
  if (!iconRef) {
    ctx.restore();
    return;
  }
  const background = await getImage(`${iconRef}?state=body_m_s&dir=2`);
  ctx.drawImage(background, 0, 0, ctx.canvas.width, ctx.canvas.height);
  ctx.restore();
};

export const BodyMarkingsEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const d = data as MarkingsData;
  const s = (staticData ?? {}) as MarkingStatic;
  const [pickerOpen, setPickerOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<string | null>(null);
  const [showHuman, setShowHuman] = useState(true);

  const used = new Set(Object.keys(d.markings ?? {}));
  const lcSearch = search.trim().toLowerCase();
  const available = Object.entries(s.available_styles ?? {})
    .filter(([key, meta]) => {
      if (used.has(key)) return false;
      if (!lcSearch) return true;
      return meta.name.toLowerCase().includes(lcSearch);
    })
    .sort((a, b) => a[1].name.localeCompare(b[1].name));

  return (
    <Section
      title="Body Markings"
      buttons={
        <>
          <Button.Checkbox
            checked={showHuman}
            onClick={() => setShowHuman((v) => !v)}
          >
            Show silhouette
          </Button.Checkbox>
          <Button
            icon={pickerOpen ? 'xmark' : 'plus'}
            onClick={() => setPickerOpen((v) => !v)}
          >
            {pickerOpen ? 'Close picker' : 'Add marking'}
          </Button>
        </>
      }
    >
      {Object.keys(d.markings ?? {}).length === 0 && !pickerOpen && (
        <Box italic color="label">
          No markings selected. Click "Add marking" to pick one.
        </Box>
      )}
      <Stack vertical>
        {Object.entries(d.markings ?? {}).map(([key, zones]) => (
          <Stack.Item key={key}>
            <MarkingRow
              markingKey={key}
              zones={zones}
              meta={s.available_styles?.[key]}
              onOpenDetails={() => setEditing(key)}
              showHuman={showHuman}
            />
          </Stack.Item>
        ))}
      </Stack>

      {pickerOpen && (
        <Dimmer
          style={{
            display: 'block',
            overflowY: 'auto',
            textAlign: 'center',
            zIndex: 100,
          }}
          height="100%"
          p={1}
        >
          <Section
            title="Add Marking"
            buttons={
              <Button
                icon="xmark"
                color="bad"
                onClick={() => setPickerOpen(false)}
              >
                Close
              </Button>
            }
          >
            <Box mb={1}>
              <Input
                fluid
                expensive
                placeholder="Search markings…"
                value={search}
                onChange={(v) => setSearch(v)}
              />
            </Box>
            {available.length === 0 && (
              <Box italic>
                {lcSearch ? 'No matches.' : 'No more markings available.'}
              </Box>
            )}
            <Stack wrap justify="center">
              {available.map(([key, meta]) => (
                <Stack.Item key={key} m={0.5}>
                  {meta.icon && meta.icon_state ? (
                    <ColorizedImageButton
                      iconRef={meta.icon}
                      iconState={meta.icon_state}
                      color="#ffffff"
                      tooltip={meta.name}
                      postRender={showHuman ? humanBackground : undefined}
                      onClick={() => {
                        send(act, 'add', { marking: key });
                        setPickerOpen(false);
                      }}
                    >
                      {meta.name}
                    </ColorizedImageButton>
                  ) : (
                    <Button
                      icon="plus"
                      onClick={() => {
                        send(act, 'add', { marking: key });
                        setPickerOpen(false);
                      }}
                    >
                      {meta.name}
                    </Button>
                  )}
                </Stack.Item>
              ))}
            </Stack>
          </Section>
        </Dimmer>
      )}

      {editing && d.markings?.[editing] && (
        <MarkingDetailPanel
          markingKey={editing}
          zones={d.markings[editing]}
          meta={s.available_styles?.[editing]}
          onClose={() => setEditing(null)}
        />
      )}
    </Section>
  );
};

const MarkingRow = ({
  markingKey,
  zones,
  meta,
  onOpenDetails,
  showHuman,
}: {
  markingKey: string;
  zones: MarkingState;
  meta?: MarkingStyleMeta;
  onOpenDetails: () => void;
  showHuman: boolean;
}) => {
  const { act } = useBackend();
  const firstZone = Object.values(zones).find(
    (z) => z && typeof z === 'object' && 'color' in z,
  );
  const previewColor = firstZone?.color ?? '#ffffff';
  return (
    <Stack align="center">
      <Stack.Item>
        {meta?.icon && meta.icon_state ? (
          <ColorizedImage
            iconRef={meta.icon}
            iconState={meta.icon_state}
            color={previewColor}
            postRender={showHuman ? humanBackground : undefined}
            size={48}
          />
        ) : (
          <ColorBox color={previewColor} mr={1} />
        )}
      </Stack.Item>
      <Stack.Item grow>
        <Box bold>{meta?.name ?? markingKey}</Box>
      </Stack.Item>
      <Stack.Item>
        <Button
          icon="arrow-up"
          onClick={() => send(act, 'move_up', { marking: markingKey })}
        />
        <Button
          icon="arrow-down"
          onClick={() => send(act, 'move_down', { marking: markingKey })}
        />
        <Button icon="sliders" onClick={onOpenDetails}>
          Edit
        </Button>
        <Button
          color="bad"
          icon="trash"
          onClick={() => send(act, 'remove', { marking: markingKey })}
        />
      </Stack.Item>
    </Stack>
  );
};

const MarkingDetailPanel = ({
  markingKey,
  zones,
  meta,
  onClose,
}: {
  markingKey: string;
  zones: MarkingState;
  meta?: MarkingStyleMeta;
  onClose: () => void;
}) => {
  const { act } = useBackend();
  return (
    <Dimmer
      style={{
        display: 'block',
        overflowY: 'auto',
        textAlign: 'left',
        zIndex: 100,
      }}
      height="100%"
      p={1}
    >
      <Section
        title={`${meta?.name ?? markingKey} options`}
        buttons={
          <Button icon="xmark" color="bad" onClick={onClose}>
            Close
          </Button>
        }
      >
        <Stack mb={1}>
          <Stack.Item>
            <Button
              icon="palette"
              onClick={() => send(act, 'set_color', { marking: markingKey })}
            >
              Recolor all zones
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button.Confirm
              icon="trash"
              color="bad"
              onClick={() => {
                send(act, 'remove', { marking: markingKey });
                onClose();
              }}
            >
              Delete
            </Button.Confirm>
          </Stack.Item>
        </Stack>
        <LabeledList>
          {Object.entries(zones)
            .filter(([_, v]) => v && typeof v === 'object' && 'on' in v)
            .map(([zone, state]) => (
              <LabeledList.Item key={zone} label={zone}>
                <Stack inline>
                  <Stack.Item>
                    <Button.Checkbox
                      checked={!!state.on}
                      onClick={() =>
                        send(act, 'toggle_zone', { marking: markingKey, zone })
                      }
                    >
                      {state.on ? 'Visible' : 'Hidden'}
                    </Button.Checkbox>
                  </Stack.Item>
                  <Stack.Item>
                    <Button
                      icon="palette"
                      onClick={() =>
                        send(act, 'set_zone_color', {
                          marking: markingKey,
                          zone,
                        })
                      }
                    >
                      <ColorBox color={state.color} mr={1} />
                      {state.color}
                    </Button>
                  </Stack.Item>
                </Stack>
              </LabeledList.Item>
            ))}
        </LabeledList>
      </Section>
    </Dimmer>
  );
};
