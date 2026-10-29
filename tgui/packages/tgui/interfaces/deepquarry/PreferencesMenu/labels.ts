// DQAdd — user-facing names for character setup categories, groups and prefs (shared by the
// page renderer and the settings search).

export const titleCase = (s: string) =>
  s.replace(
    /(^|[_\s])([a-z])/g,
    (_, sep, ch) => (sep ? ' ' : '') + ch.toUpperCase(),
  );

// User-facing names for groups that don't pretty-print well via titleCase.
// titleCase("ooc_notes") yields "Ooc Notes" (looks wrong); titleCase("mind_body")
// yields "Mind Body" (should be "Mind & Body"). Keys match the `group` field
// emitted by tag_pref on the DM side.
export const GROUP_LABELS: Record<string, string> = {
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

export const labelForGroup = (key: string) =>
  GROUP_LABELS[key] ?? titleCase(key);

// User-facing names for prefs whose DM-side savefile_key is short/cryptic
// (h_style, s_tone, etc.) and whose display_label isn't set. titleCase("s_tone")
// produces "S Tone" which is unhelpful; this map fixes the common cases without
// requiring a DM-side touch on every pref. If a pref has display_label set on
// the DM side (item.label), that always wins.
export const PREF_KEY_LABELS: Record<string, string> = {
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
  synth_color: 'Use Synth Color',
  synth_color_rgb: 'Synth Color',
  skin_tone: 'Skin Tone',
  hair_style_name: 'Hair Style',
  facial_style_name: 'Facial Hair Style',
  grad_style_name: 'Hair Gradient',
  secondary_ears_alpha: 'Secondary Ear Opacity',
  preflang: 'Preferred Language',
  uplinklocation: 'Uplink Location',
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

export const labelForKey = (key: string, override?: string | null) =>
  override ?? PREF_KEY_LABELS[key] ?? titleCase(key);

// Consolidated, shorter labels so all tabs fit on one row at the default window width.
// Keys match /datum/preference.category values written by tag_pref(). Categories without
// an override here fall back to titleCase(category).
export const CATEGORY_LABELS: Record<string, string> = {
  identity: 'Identity',
  factions: 'Factions',
  appearance: 'Looks',
  // Renamed from "Body" so the new Mind & Body specialty tab can own that word; the
  // size_voice category is really size sliders + voice prefs, "Size" is closer anyway.
  size_voice: 'Size',
  loadout: 'Loadout',
  occupation: 'Jobs',
  traits: 'Traits',
  mind_body: 'Mind & Body',
  antag: 'Antag',
  vore: 'Vore',
  game: 'Game',
  misc: 'Misc',
};

export const labelForCategory = (key: string) =>
  CATEGORY_LABELS[key] ?? titleCase(key);
