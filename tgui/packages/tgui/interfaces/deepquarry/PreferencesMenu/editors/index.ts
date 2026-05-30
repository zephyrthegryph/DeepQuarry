// DQAdd — Registry of composite editor React components. Keyed by the editor's `key`
// field on the DM side (/datum/preference_editor.key). Add new editors here as they're
// implemented; the auto-renderer looks them up by string.

import type { ComponentType } from 'react';
import { AntagOptInEditor } from './AntagOptInEditor';
import { BirthdayEditor } from './BirthdayEditor';
import { BodyMarkingsEditor } from './BodyMarkingsEditor';
import { FlavorTextEditor } from './FlavorTextEditor';
import { LanguagePicker } from './LanguagePicker';
import { LoadoutBuilder } from './LoadoutBuilder';
import { MindBodyEditor } from './MindBodyEditor';
import { NifStatusPanel } from './NifStatusPanel';
import { OccupationEditor } from './OccupationEditor';
import { OrgansEditor } from './OrgansEditor';
import { PersistenceEditor } from './PersistenceEditor';
import { PlaceholderEditor } from './PlaceholderEditor';
import { TraitPicker } from './TraitPicker';
import { VoreMessagesEditor } from './VoreMessagesEditor';

export type EditorProps = {
  data: Record<string, unknown>;
  staticData?: Record<string, unknown>;
};

export const PREF_EDITORS: Record<string, ComponentType<EditorProps>> = {
  antag_optin: AntagOptInEditor,
  birthday: BirthdayEditor,
  body_markings: BodyMarkingsEditor,
  flavor: FlavorTextEditor,
  language: LanguagePicker,
  loadout: LoadoutBuilder,
  mind_body: MindBodyEditor,
  nif_status: NifStatusPanel,
  occupation: OccupationEditor,
  organs: OrgansEditor,
  persistence: PersistenceEditor,
  trait_picker: TraitPicker,
  vore_messages: VoreMessagesEditor,
};

export const getEditor = (key: string): ComponentType<EditorProps> =>
  PREF_EDITORS[key] ?? PlaceholderEditor;
