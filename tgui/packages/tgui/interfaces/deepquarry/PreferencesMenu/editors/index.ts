// DQAdd — Registry of composite editor React components. Keyed by the editor's `key`
// field on the DM side (/datum/preference_editor.key). Add new editors here as they're
// implemented; the auto-renderer looks them up by string.
//
// The payloads are typed by the window's generated shape (ui_shape() in
// code/content/client/preferences.dm; each editor's own shape is a UI_SCHEMA beside its
// build_ui_data() in code/content/client/preferences/editors/).

import type { ComponentType } from 'react';
import type { PreferencesMenuData } from '../../../generated/PreferencesMenu';
import { AntagOptInEditor } from './AntagOptInEditor';
import { BirthdayEditor } from './BirthdayEditor';
import { BodyMarkingsEditor } from './BodyMarkingsEditor';
import { FactionAffiliationsEditor } from './FactionAffiliationsEditor';
import { FlavorTextEditor } from './FlavorTextEditor';
import { LanguagePicker } from './LanguagePicker';
import { LoadoutBuilder } from './LoadoutBuilder';
import { MindBodyEditor } from './MindBodyEditor';
import { NifStatusPanel } from './NifStatusPanel';
import { OccupationEditor } from './OccupationEditor';
import { OrgansEditor } from './OrgansEditor';
import { PersistenceEditor } from './PersistenceEditor';
import { RobotChassisPicker } from './RobotChassisPicker';
import { SpeciesPicker } from './SpeciesPicker';
import { TraitPicker } from './TraitPicker';
import { VoreMessagesEditor } from './VoreMessagesEditor';

type EditorDataMap = PreferencesMenuData['dq_editor_data'];
type EditorStaticMap = NonNullable<
  PreferencesMenuData['dq_editor_static_patch']
>;

/// Every shown editor's key (/datum/preference_editor.key).
export type EditorKey = keyof EditorDataMap;
/// The keys of the editors that have a static catalog.
export type EditorStaticKey = keyof EditorStaticMap;

/// What the window has received so far: the server sends null for an editor it did not answer for, and the window keeps what it had.
export type EditorDataCache = {
  [K in EditorKey]?: NonNullable<EditorDataMap[K]>;
};
export type EditorStaticCache = {
  [K in EditorStaticKey]?: NonNullable<EditorStaticMap[K]>;
};

export type EditorProps<K extends EditorKey> = {
  data: NonNullable<EditorDataMap[K]>;
  /// Undefined until the window has asked for the catalogs; an editor without a catalog never gets one.
  staticData?: K extends EditorStaticKey
    ? NonNullable<EditorStaticMap[K]>
    : undefined;
};

export const PREF_EDITORS: {
  [K in EditorKey]?: ComponentType<EditorProps<K>>;
} = {
  antag_optin: AntagOptInEditor,
  birthday: BirthdayEditor,
  body_markings: BodyMarkingsEditor,
  flavor: FlavorTextEditor,
  faction_affiliations: FactionAffiliationsEditor,
  language: LanguagePicker,
  loadout: LoadoutBuilder,
  mind_body: MindBodyEditor,
  nif_status: NifStatusPanel,
  occupation: OccupationEditor,
  organs: OrgansEditor,
  persistence: PersistenceEditor,
  robot_chassis: RobotChassisPicker,
  species_picker: SpeciesPicker,
  trait_picker: TraitPicker,
  vore_messages: VoreMessagesEditor,
};

/// A key the server sent is a string: this is the one place it meets the per-editor payload types. An editor
/// without a component (or one whose data has not arrived) renders as the placeholder (or nothing).
export const getEditor = (
  key: string,
): ComponentType<EditorProps<EditorKey>> | undefined =>
  PREF_EDITORS[key as EditorKey] as
    | ComponentType<EditorProps<EditorKey>>
    | undefined;
