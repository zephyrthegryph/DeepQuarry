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

import { Box, LabeledList, Section } from 'tgui-core/components';
import { getEditor } from './editors';
import { PrefWidget } from './PrefWidget';
import type {
  PrefCategory,
  PrefGroup,
  PrefGroupItem,
  PrefWidgetItem,
} from './types';

type Props = {
  page: PrefCategory;
  staticData?: Record<string, Record<string, unknown>>;
  /// When true, this page hosts a full-height editor (e.g. loadout). Skip the
  /// grid layout and let the editor own the container directly.
  fillHeight?: boolean;
};

const titleCase = (s: string) =>
  s.replace(/(^|[_\s])([a-z])/g, (_, sep, ch) => (sep ? ' ' : '') + ch.toUpperCase());

// User-facing names for groups that don't pretty-print well via titleCase.
// titleCase("ooc_notes") yields "Ooc Notes" (looks wrong); titleCase("mind_body")
// yields "Mind Body" (should be "Mind & Body"). Keys match the `group` field
// emitted by tag_pref on the DM side.
const GROUP_LABELS: Record<string, string> = {
  ooc_notes: 'OOC Notes',
  speech_verbs: 'Speech Verbs',
  starting_kit: 'Starting Kit',
  be_special: 'Antag Roles',
  mind_body: 'Mind & Body',
  size_voice: 'Size & Voice',
  pai: 'pAI Card',
  nif: 'NIF',
  background: 'Background',
};

const labelForGroup = (key: string) =>
  GROUP_LABELS[key] ?? titleCase(key);

// User-facing names for prefs whose DM-side savefile_key is short/cryptic
// (h_style, s_tone, etc.) and whose display_label isn't set. titleCase("s_tone")
// produces "S Tone" which is unhelpful; this map fixes the common cases without
// requiring a DM-side touch on every pref. If a pref has display_label set on
// the DM side (item.label), that always wins.
const PREF_KEY_LABELS: Record<string, string> = {
  s_tone: 'Skin Tone',
  skin_color: 'Skin Color',
  eyes_color: 'Eye Color',
  hair_color: 'Hair Color',
  facial_color: 'Facial Hair Color',
  grad_color: 'Gradient Color',
  h_style: 'Hair Style',
  f_style: 'Facial Hair Style',
  grad_style: 'Hair Gradient',
  ear_style: 'Ear Style',
  ear_secondary_style: 'Secondary Ear Style',
  ears_color1: 'Ear Color (Primary)',
  ears_color2: 'Ear Color (Secondary)',
  ears_color3: 'Ear Color (Tertiary)',
  ears_alpha: 'Ear Opacity',
  tail_style: 'Tail Style',
  tail_color1: 'Tail Color (Primary)',
  tail_color2: 'Tail Color (Secondary)',
  tail_color3: 'Tail Color (Tertiary)',
  tail_alpha: 'Tail Opacity',
  tail_layering: 'Tail Layering',
  wing_style: 'Wing Style',
  wing_color1: 'Wing Color (Primary)',
  wing_color2: 'Wing Color (Secondary)',
  wing_color3: 'Wing Color (Tertiary)',
  wing_alpha: 'Wing Opacity',
  b_type: 'Blood Type',
  blood_reagents: 'Blood Reagent',
  blood_color: 'Blood Color',
  real_name: 'Name',
  nickname: 'Nickname',
  bday_announce: 'Announce Birthday',
  digitigrade: 'Digitigrade Legs',
  custom_link: 'Custom Link',
  custom_say: 'Custom Say Verb',
  custom_whisper: 'Custom Whisper Verb',
  custom_ask: 'Custom Ask Verb',
  custom_exclaim: 'Custom Exclaim Verb',
  birthplace: 'Birthplace',
  citizenship: 'Citizenship',
  faction: 'Faction',
  home_system: 'Home System',
  religion: 'Religion',
  economic_status: 'Economic Status',
  preferred_language: 'Preferred Language',
  runechat_color: 'Runechat Color',
  med_record: 'Medical Record',
  sec_record: 'Security Record',
  gen_record: 'General Record',
  ooc_notes: 'General Notes',
  ooc_notes_likes: 'Likes',
  ooc_notes_dislikes: 'Dislikes',
  ooc_notes_favs: 'Favorites',
  ooc_notes_maybes: 'Maybes',
  private_notes: 'Private Notes',
  ooc_notes_style: 'Use Stylized Display',
  // The DM savefile_keys for OOC notes use CamelCase and one has a typo
  // ("OOC_Notes_Disikes"). Map every actual key emitted so the UI is consistent.
  OOC_Notes: 'General Notes',
  OOC_Notes_Likes: 'Likes',
  OOC_Notes_Disikes: 'Dislikes',
  OOC_Notes_Maybes: 'Maybes',
  OOC_Notes_Favs: 'Favorites',
  OOC_Notes_System: 'Use Stylized Display',
  Private_Notes: 'Private Notes',
  synth_color: 'Synth Color',
  synth_markings: 'Synth Markings',
  preview_loadout: 'Show Loadout in Preview',
  preview_job: 'Show Job in Preview',
  animations_toggle: 'Preview Animations',
  voice_freq: 'Voice Frequency',
  voice_sound: 'Voice Sound',
  custom_speech_bubble: 'Custom Speech Bubble',
  custom_footstep: 'Custom Footstep',
  species_sound: 'Species Sound',
  fuzzy: 'Fuzzy Rendering',
  offset_override: 'Override Pixel Offset',
  spawnpoint: 'Spawn Point',
  gender: 'Gender',
  resleeve_lock: 'Lock Resleeve',
  resleeve_scan: 'Allow Resleeve Scan',
  mind_scan: 'Allow Mind Scan',
  capture_crystal: 'Use Capture Crystal',
  auto_backup_implant: 'Auto Backup Implant',
  borg_petting: 'Allow Borg Petting',
  show_in_directory: 'Show in Vore Directory',
  directory_tag: 'Vore Tag',
  directory_gendertag: 'Directory Gender',
  directory_sexualitytag: 'Sexuality',
  directory_erptag: 'ERP Tag',
  directory_ad: 'Directory Ad',
  ignore_shoes: 'Ignore Shoes',
  sensorpref: 'Sensor Default',
  autohiss: 'Autohiss',
  vore_egg_type: 'Egg Type',
  pai_name: 'pAI Name',
  pai_description: 'Description',
  pai_role: 'Role',
  pai_ad: 'Ad Text',
  pai_comments: 'Comments',
  pai_eye_color: 'Eye Color',
  pai_chassis: 'Chassis',
  pai_emotion: 'Default Emotion',
  // Actual savefile_keys for pAI prefs are CamelCase (Pai_Name, Pai_Desc, etc.).
  Pai_Name: 'pAI Name',
  Pai_Desc: 'Description',
  Pai_Role: 'Role',
  Pai_Ad: 'Ad Text',
  Pai_Comments: 'Comments',
  Pai_EyeColor: 'Eye Color',
  Pai_Chassis: 'Chassis',
  Pai_Emotion: 'Default Emotion',
  antag_faction: 'Antag Faction',
  antag_vis: 'Antag Visibility',
  vantag_volunteer: 'Volunteer for Visitor-Antag',
  vantag_preference: 'Visitor-Antag Type',
  exploit_record: 'Exploitable Record',
};

const labelForKey = (key: string, override?: string | null) =>
  override ?? PREF_KEY_LABELS[key] ?? titleCase(key);

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

export const CategoryPage = ({ page, staticData, fillHeight }: Props) => {
  if (fillHeight) {
    return (
      <Box style={{ height: '100%' }}>
        {page.groups.map((group, gi) => (
          <GroupBlock
            key={`${gi}-${group.group}`}
            group={group}
            staticData={staticData}
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
              containsFullWidthEditor
                ? { gridColumn: '1 / -1' }
                : undefined
            }
          >
            <GroupBlock group={group} staticData={staticData} />
          </Box>
        );
      })}
    </Box>
  );
};

/// Widget rows inside a single group. We render each widget on its own row
/// (one LabeledList per group) so the label column auto-sizes to fit the
/// longest label and every widget column lines up. Multi-column packing
/// looked nice for short labels but caused dropdowns/inputs to overflow
/// inconsistently when one cell's value was longer than the next.
const WidgetGrid = ({ widgets }: { widgets: PrefWidgetItem[] }) => (
  <LabeledList>
    {widgets.map((item) => (
      <LabeledList.Item
        key={item.key}
        label={labelForKey(item.key, item.label)}
      >
        <PrefWidget item={item} />
      </LabeledList.Item>
    ))}
  </LabeledList>
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

  // Bare-frame mode: no group title and no widgets — just render the editors
  // directly. Used by single-editor categories (Loadout, Mind & Body) and
  // by groups that only carry an editor.
  if (!hasTitle && widgets.length === 0) {
    return (
      <Box style={fillHeight ? { height: '100%' } : undefined}>
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
    <Section title={hasTitle ? labelForGroup(group.group) : null}>
      {widgets.length > 0 && <WidgetGrid widgets={widgets} />}
      {editors.map((item, idx) => (
        <Box
          key={`editor:${item.key}-${idx}`}
          mt={widgets.length > 0 ? 0.5 : 0}
        >
          <EditorBlock item={item} staticData={staticData} />
        </Box>
      ))}
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
