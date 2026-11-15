import { describe, expect, it } from 'bun:test';

import { labelForGroup, labelForKey } from './labels';

describe('restored character settings', () => {
  it('label every restored key', () => {
    const labels: Record<string, string> = {
      nickname: 'Nickname',
      home_system: 'Home System',
      birthplace: 'Birthplace',
      citizenship: 'Citizenship',
      religion: 'Religion',
      economic_status: 'Economic Status',
      med_record: 'Medical',
      sec_record: 'Security',
      gen_record: 'General',
      custom_say: 'Say',
      custom_whisper: 'Whisper',
      custom_ask: 'Ask',
      custom_exclaim: 'Exclaim',
      autohiss: 'Autohiss',
      custom_speech_bubble: 'Speech Bubble',
      custom_footstep: 'Footsteps',
      species_sound: 'Species Sounds',
      directory_gendertag: 'Gender',
      directory_sexualitytag: 'Sexuality',
      Pai_Desc: 'Description',
      Pai_Role: 'Role',
      Pai_Ad: 'Ad Text',
      Pai_Comments: 'Comments',
      flicker_time: 'Flicker Time',
      flicker_color: 'Flicker Color',
      flicker_break_chance: 'Bulb Break Chance',
      flicker_distance: 'Flicker Distance',
      blood_reagents: 'Restored By',
      fuzzy: 'Fuzzy Rendering',
      offset_override: 'Override Pixel Offset',
      resleeve_lock: 'Lock Resleeve',
      auto_backup_implant: 'Auto Backup Implant',
      borg_petting: 'Allow Borg Petting',
      sensorpref: 'Sensor Default',
      ignore_shoes: 'Ignore Shoes',
      vore_egg_type: 'Egg Type',
    };
    for (const [key, label] of Object.entries(labels)) {
      expect(labelForKey(key)).toBe(label);
    }
  });

  it('names the Shadekin section', () => {
    expect(labelForGroup('shadekin')).toBe('Shadekin');
  });
});
