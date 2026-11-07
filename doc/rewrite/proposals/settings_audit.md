# Settings, preferences and verbs audit

2026-11-07. Every character preference, game setting and player verb, where it is read, its class and the action taken.
Classes: **DEAD** (nothing reads it, or its feature is gone), **DUPLICATE** (a second setting or verb for one thing), **NICHE** (rarely useful; proposed for a default or an Advanced group, not changed: the user decides), **KEEP**.

Saved values: retired keys are listed in `GLOB.retired_player_pref_keys` and `GLOB.retired_character_pref_keys` (`code/content/client/preferences_savefile.dm`) and dropped on load; `equip_preview_mob` is first migrated into `preview_loadout`/`preview_job`. Tests: `dq_retired_character_keys_migrate`, `dq_retired_player_keys_drop`.

## Summary

| Area | Before | After | Removed |
|---|---|---|---|
| Character preferences | 164 | 162 | `equip_preview_mob` (migrated), `vantag_volunteer` |
| Game settings (declarations) | 129 | 118 | 8 settings plus 3 second declarations of one type |
| Player verbs | 171 | 170 | `Set Default Language` |
| Verbs listed in the verb panel | 55 | 50 | 5 Menu duplicates hidden (still run by name) |

The panel count counts every categorised verb, including procs granted only to some mobs.

NICHE items are listed in the tables with a proposed action; none were changed.

## Character preferences (164)

| Key | Type | Read at | Class | Action |
|---|---|---|---|---|
| `tail_style_under_taur` | `/datum/preference/text/human/tail_style_under_taur` | `code/content/client/preferences/editors/legs.dm:29` | KEEP | keep |
| `be_special` | `/datum/preference/numeric/human/be_special` | `code/content/client/preferences/editors/antag_optin.dm:37` | KEEP | keep |
| `antag_faction` | `/datum/preference/text/human/antag_faction` | `apply proc in antagonism.dm` | KEEP | keep |
| `antag_vis` | `/datum/preference/choiced/human/antag_vis` | `code/content/client/preferences/types/character/antagonism.dm:42` | KEEP | keep |
| `exploit_record` | `/datum/preference/text/human/exploit_record` | `apply proc in antagonism.dm` | KEEP | keep |
| `vantag_volunteer` | `/datum/preference/toggle/human/vantag_volunteer` | `apply proc in antagonism.dm` | DUPLICATE | deleted (no reader); vantag_preference is the setting |
| `vantag_preference` | `/datum/preference/choiced/human/vantag_preference` | `code/content/client/preferences/types/character/antagonism.dm:81` | KEEP | keep |
| `uplinklocation` | `/datum/preference/choiced/uplinklocation` | `code/content/antagonist/station/traitor.dm:117` | KEEP | keep |
| `home_system` | `/datum/preference/text/human/home_system` | `apply proc in background.dm` | KEEP | keep |
| `birthplace` | `/datum/preference/text/human/birthplace` | `apply proc in background.dm` | KEEP | keep |
| `citizenship` | `/datum/preference/text/human/citizenship` | `apply proc in background.dm` | KEEP | keep |
| `religion` | `/datum/preference/text/human/religion` | `apply proc in background.dm` | KEEP | keep |
| `economic_status` | `/datum/preference/choiced/human/economic_status` | `code/content/gamemodes/game_mode.dm:577` | KEEP | keep |
| `b_type` | `/datum/preference/text/human/b_type` | `code/content/client/preferences.dm:171` | KEEP | keep |
| `blood_reagents` | `/datum/preference/text/human/blood_reagents` | `code/content/client/preferences/_vanity_pref_types.dm:27` | KEEP | keep |
| `hair_style_name` | `/datum/preference/text/human/h_style` | `code/content/client/preferences/_vanity_pref_types.dm:30` | KEEP | keep |
| `facial_style_name` | `/datum/preference/text/human/f_style` | `code/content/client/preferences/_vanity_pref_types.dm:31` | KEEP | keep |
| `grad_style_name` | `/datum/preference/text/human/grad_style` | `code/content/client/preferences/_vanity_pref_types.dm:32` | KEEP | keep |
| `digitigrade` | `/datum/preference/toggle/human/digitigrade` | `code/content/client/preferences/_vanity_pref_types.dm:25` | KEEP | keep |
| `ear_style` | `/datum/preference/text/human/ear_style` | `code/content/client/preferences/_vanity_pref_types.dm:38` | KEEP | keep |
| `ear_secondary_style` | `/datum/preference/text/human/ear_secondary_style` | `code/content/client/preferences/_vanity_pref_types.dm:39` | KEEP | keep |
| `tail_style` | `/datum/preference/text/human/tail_style` | `code/content/client/preferences/_vanity_pref_types.dm:47` | KEEP | keep |
| `wing_style` | `/datum/preference/text/human/wing_style` | `code/content/client/preferences/_vanity_pref_types.dm:54` | KEEP | keep |
| `bgstate` | `/datum/preference/text/human/bgstate` | `code/content/client/preferences.dm:258` | KEEP | keep |
| `equip_preview_mob` | `/datum/preference/numeric/human/equip_preview_mob` | `apply proc in body_styles.dm` | DUPLICATE | deleted; replaced by preview_loadout + preview_job, migrated on load |
| `preview_loadout` | `/datum/preference/toggle/human/preview_loadout` | `code/content/mob/new_player/preferences_setup.dm:174` | KEEP | keep |
| `preview_job` | `/datum/preference/toggle/human/preview_job` | `code/content/mob/new_player/preferences_setup.dm:175` | KEEP | keep |
| `animations_toggle` | `/datum/preference/toggle/human/animations_toggle` | `code/content/mob/new_player/preferences_setup.dm:350` | KEEP | keep |
| `palette_primary` | `/datum/preference/color/human/color_slot/primary` | `code/content/client/preferences/types/character/color_palette.dm:9` | KEEP | keep |
| `palette_secondary` | `/datum/preference/color/human/color_slot/secondary` | `code/content/client/preferences/types/character/color_palette.dm:10` | KEEP | keep |
| `palette_tertiary` | `/datum/preference/color/human/color_slot/tertiary` | `code/content/client/preferences/editors/organs.dm:96` | KEEP | keep |
| `palette_extra1` | `/datum/preference/color/human/color_slot/extra1` | `code/content/client/preferences/types/character/color_palette.dm:12` | KEEP | keep |
| `palette_extra2` | `/datum/preference/color/human/color_slot/extra2` | `code/content/client/preferences/types/character/color_palette.dm:13` | KEEP | keep |
| `limb_colors` | `/datum/preference/limb_colors` | `code/content/client/preferences/_vanity_pref_types.dm:24` | KEEP | keep |
| `body_markings` | `/datum/preference/body_markings` | `code/content/client/preferences/_vanity_pref_types.dm:61` | KEEP | keep |
| `flavor_texts` | `/datum/preference/flavor_texts` | `code/content/admin/verbs/randomverbs.dm:1495` | KEEP | keep |
| `flavour_texts_robot` | `/datum/preference/flavour_texts_robot` | `code/content/admin/verbs/randomverbs.dm:1497` | KEEP | keep |
| `ear_secondary_colors` | `/datum/preference/ear_secondary_colors` | `code/content/client/preferences/_vanity_pref_types.dm:44` | KEEP | keep |
| `language` | `/datum/preference/alternate_languages` | `code/content/admin/verbs/randomverbs.dm:801` | KEEP | keep |
| `language_custom_keys` | `/datum/preference/language_custom_keys` | `code/content/client/preferences/editors/language.dm:97` | KEEP | keep |
| `all_underwear` | `/datum/preference/all_underwear` | `code/content/client/preferences/_pref_sanitizers.dm:199` | KEEP | keep |
| `all_underwear_metadata` | `/datum/preference/all_underwear_metadata` | `code/content/client/preferences/apply_hooks/equipment.dm:15` | KEEP | keep |
| `gear_list` | `/datum/preference/gear_list` | `code/content/client/preferences/editors/loadout.dm:194` | KEEP | keep |
| `gear_slot` | `/datum/preference/text/human/gear_slot` | `code/content/client/preferences/editors/loadout.dm:490` | KEEP | keep |
| `body_perks` | `/datum/preference/typed_list/body_perks` | `code/content/client/preferences/apply_hooks/mind_body.dm:18` | KEEP | keep |
| `mind_perks` | `/datum/preference/typed_list/mind_perks` | `code/content/client/preferences/apply_hooks/mind_body.dm:26` | KEEP | keep |
| `custom_heat` | `/datum/preference/custom_heat` | `code/content/client/preferences/editors/vore_messages.dm:15` | KEEP | keep |
| `custom_cold` | `/datum/preference/custom_cold` | `code/content/client/preferences/editors/vore_messages.dm:16` | KEEP | keep |
| `blood_color` | `/datum/preference/color/human/blood_color` | `code/content/client/preferences.dm:480` | KEEP | keep |
| `starting_trait_points` | `/datum/preference/numeric/human/starting_trait_points` | `code/content/client/preferences/constraints/traits_validity.dm:72` | KEEP | keep |
| `max_traits` | `/datum/preference/numeric/human/max_traits` | `code/content/client/preferences/constraints/traits_validity.dm:75` | KEEP | keep |
| `traits_cheating` | `/datum/preference/numeric/human/traits_cheating` | `code/content/client/preferences/constraints/traits_validity.dm:68` | KEEP | keep |
| `pos_traits` | `/datum/preference/typed_list/traits/pos_traits` | `code/content/client/preferences/apply_hooks/traits.dm:26` | KEEP | keep |
| `neu_traits` | `/datum/preference/typed_list/traits/neu_traits` | `code/content/client/preferences.dm:500` | KEEP | keep |
| `neg_traits` | `/datum/preference/typed_list/traits/neg_traits` | `code/content/client/preferences/apply_hooks/traits.dm:28` | KEEP | keep |
| `show_in_directory` | `/datum/preference/toggle/human/show_in_directory` | `code/content/client/verbs/character_directory.dm:49` | KEEP | keep |
| `directory_tag` | `/datum/preference/choiced/human/directory_tag` | `code/content/client/preferences/types/character/directory.dm:30` | KEEP | keep |
| `directory_gendertag` | `/datum/preference/choiced/human/directory_gendertag` | `code/content/client/preferences/types/character/directory.dm:44` | KEEP | keep |
| `directory_sexualitytag` | `/datum/preference/choiced/human/directory_sexualitytag` | `code/content/client/preferences/types/character/directory.dm:58` | KEEP | keep |
| `directory_erptag` | `/datum/preference/choiced/human/directory_erptag` | `code/content/client/preferences/types/character/directory.dm:72` | KEEP | keep |
| `directory_ad` | `/datum/preference/text/human/directory_ad` | `code/content/client/verbs/character_directory.dm:113` | KEEP | keep |
| `sensorpref` | `/datum/preference/numeric/human/sensorpref` | `apply proc in directory.dm` | KEEP | keep |
| `capture_crystal` | `/datum/preference/toggle/human/capture_crystal` | `code/content/items/devices/denecrotizer.dm:64` | KEEP | keep |
| `auto_backup_implant` | `/datum/preference/toggle/human/auto_backup_implant` | `code/content/mob/new_player/new_player.dm:267` | KEEP | keep |
| `borg_petting` | `/datum/preference/toggle/human/borg_petting` | `code/content/mob/living/silicon/robot/robot.dm:1106` | KEEP | keep |
| `ttone` | `/datum/preference/text/human/ringtone` | `code/content/client/preferences/editors/starting_kit.dm:21` | KEEP | keep |
| `communicator_visibility` | `/datum/preference/toggle/human/communicator_visibility` | `code/content/client/preferences/editors/starting_kit.dm:22` | KEEP | keep |
| `faction_affiliations` | `/datum/preference/faction_affiliations` | `code/content/client/preferences/editors/faction_affiliations.dm:10` | KEEP | keep |
| `gender` | `/datum/preference/choiced/gender/biological` | `code/content/client/preferences/_vanity_pref_types.dm:16` | KEEP | keep |
| `id_gender` | `/datum/preference/choiced/gender/identifying` | `code/content/client/preferences.dm:170` | KEEP | keep |
| `bday_announce` | `/datum/preference/toggle/human/bday_announce` | `code/content/client/preferences/editors/birthday.dm:22` | KEEP | keep |
| `age` | `/datum/preference/numeric/human/age` | `code/content/client/preferences/constraints/mind_body_validity.dm:35` | KEEP | keep |
| `bday_month` | `/datum/preference/numeric/human/bday_month` | `code/content/client/preferences/editors/birthday.dm:17` | KEEP | keep |
| `bday_day` | `/datum/preference/numeric/human/bday_day` | `code/content/client/preferences/editors/birthday.dm:20` | KEEP | keep |
| `last_bday_note` | `/datum/preference/numeric/human/last_bday_note` | `code/content/mob/living/carbon/human/birthday.dm:12` | KEEP | keep |
| `OOC_Notes` | `/datum/preference/text/living/ooc_notes` | `code/content/client/preferences/_vanity_pref_types.dm:86` | KEEP | keep |
| `OOC_Notes_Likes` | `/datum/preference/text/living/ooc_notes_likes` | `code/content/client/preferences/_vanity_pref_types.dm:87` | KEEP | keep |
| `OOC_Notes_Disikes` | `/datum/preference/text/living/ooc_notes_dislikes` | `code/content/client/preferences/_vanity_pref_types.dm:88` | KEEP | keep |
| `OOC_Notes_System` | `/datum/preference/toggle/living/ooc_notes_style` | `code/content/client/preferences.dm:540` | KEEP | keep |
| `OOC_Notes_Maybes` | `/datum/preference/text/living/ooc_notes_maybes` | `code/content/client/preferences/_vanity_pref_types.dm:90` | KEEP | keep |
| `OOC_Notes_Favs` | `/datum/preference/text/living/ooc_notes_favs` | `code/content/client/preferences/_vanity_pref_types.dm:89` | KEEP | keep |
| `name_is_always_random` | `/datum/preference/toggle/human/name_is_always_random` | `code/content/client/preferences.dm:283` | KEEP | keep |
| `spawnpoint` | `/datum/preference/choiced/living/spawnpoint` | `code/content/client/preferences/constraints/species_change.dm:95` | KEEP | keep |
| `emote_sound_mode` | `/datum/preference/choiced/living/emote_sound_mode` | `code/content/client/preferences/types/character/general/01_basic.dm:222` | NICHE | see EMOTE_VARY. |
| `hair_color` | `/datum/preference/color/human/hair_color` | `code/content/client/preferences/_vanity_pref_types.dm:33` | KEEP | keep |
| `grad_color` | `/datum/preference/color/human/grad_color` | `code/content/client/preferences/_vanity_pref_types.dm:35` | KEEP | keep |
| `facial_color` | `/datum/preference/color/human/facial_color` | `code/content/client/preferences/_vanity_pref_types.dm:34` | KEEP | keep |
| `eyes_color` | `/datum/preference/color/human/eyes_color` | `code/content/client/preferences/_vanity_pref_types.dm:23` | KEEP | keep |
| `skin_color` | `/datum/preference/color/human/skin_color` | `code/content/client/preferences/_vanity_pref_types.dm:22` | KEEP | keep |
| `tail_color1` | `/datum/preference/color/human/tail_color1` | `code/content/client/preferences/_vanity_pref_types.dm:48` | KEEP | keep |
| `tail_color2` | `/datum/preference/color/human/tail_color2` | `code/content/client/preferences/_vanity_pref_types.dm:49` | KEEP | keep |
| `tail_color3` | `/datum/preference/color/human/tail_color3` | `code/content/client/preferences/_vanity_pref_types.dm:50` | KEEP | keep |
| `tail_alpha` | `/datum/preference/numeric/human/tail_alpha` | `code/content/client/preferences/_vanity_pref_types.dm:51` | KEEP | keep |
| `wing_color1` | `/datum/preference/color/human/wing_color1` | `code/content/client/preferences/_vanity_pref_types.dm:55` | KEEP | keep |
| `wing_color2` | `/datum/preference/color/human/wing_color2` | `code/content/client/preferences/_vanity_pref_types.dm:56` | KEEP | keep |
| `wing_color3` | `/datum/preference/color/human/wing_color3` | `code/content/client/preferences/_vanity_pref_types.dm:57` | KEEP | keep |
| `wing_alpha` | `/datum/preference/numeric/human/wing_alpha` | `code/content/client/preferences/_vanity_pref_types.dm:58` | KEEP | keep |
| `ears_color1` | `/datum/preference/color/human/ears_color1` | `code/content/client/preferences/_vanity_pref_types.dm:40` | KEEP | keep |
| `ears_color2` | `/datum/preference/color/human/ears_color2` | `code/content/client/preferences/_vanity_pref_types.dm:41` | KEEP | keep |
| `ears_color3` | `/datum/preference/color/human/ears_color3` | `code/content/client/preferences/_vanity_pref_types.dm:42` | KEEP | keep |
| `ears_alpha` | `/datum/preference/numeric/human/ears_alpha` | `code/content/client/preferences/_vanity_pref_types.dm:43` | KEEP | keep |
| `secondary_ears_alpha` | `/datum/preference/numeric/human/ears_alpha/secondary` | `apply proc in 03_body.dm` | KEEP | keep |
| `flicker_color` | `/datum/preference/color/living/flicker_color` | `code/content/mob/living/carbon/human/species/shadekin/state/helpers/comp_helpers.dm:202` | NICHE | the four flicker_* settings: one Advanced group. |
| `flicker_time` | `/datum/preference/numeric/living/flicker_time` | `code/content/mob/living/carbon/human/species/shadekin/state/helpers/comp_helpers.dm:203` | NICHE | see flicker_color. |
| `flicker_break_chance` | `/datum/preference/numeric/living/flicker_break_chance` | `code/content/mob/living/carbon/human/species/shadekin/state/helpers/comp_helpers.dm:204` | NICHE | see flicker_color. |
| `flicker_distance` | `/datum/preference/numeric/living/flicker_distance` | `code/content/mob/living/carbon/human/species/shadekin/state/helpers/comp_helpers.dm:205` | NICHE | see flicker_color. |
| `DARK_RETREAT_TOGGLE` | `/datum/preference/toggle/living/dark_retreat_toggle` | `code/content/mob/living/carbon/human/species/shadekin/state/helpers/comp_helpers.dm:206` | KEEP | keep |
| `SHADEKIN_NUTRITION_CONVERSION` | `/datum/preference/toggle/living/shadekin_nutrition_conversion` | `code/content/mob/living/carbon/human/species/shadekin/state/helpers/comp_helpers.dm:207` | KEEP | keep |
| `SHADEKIN_HIDE_VOICE_IN_PHASE` | `/datum/preference/toggle/living/shadekin_hide_voice_in_phase` | `code/content/mob/living/carbon/human/species/shadekin/state/helpers/comp_helpers.dm:208` | KEEP | keep |
| `ignore_shoes` | `/datum/preference/toggle/human/ignore_shoes` | `code/content/behaviours/footstep.dm:141` | KEEP | keep |
| `job_priorities` | `/datum/preference/job_priorities` | `code/content/client/preferences/editors/loadout.dm:303` | KEEP | keep |
| `prefer_visitor_role` | `/datum/preference/toggle/human/prefer_visitor_role` | `code/content/client/preferences/types/character/job_priorities.dm:14` | KEEP | keep |
| `extra_languages` | `/datum/preference/numeric/human/extra_languages` | `code/content/client/preferences/_pref_sanitizers.dm:30` | KEEP | keep |
| `preflang` | `/datum/preference/text/human/preferred_language` | `code/content/client/preferences/editors/language.dm:44` | KEEP | keep |
| `custom_base` | `/datum/preference/text/human/custom_base` | `code/content/client/preferences.dm:469` | KEEP | keep |
| `dirty_synth` | `/datum/preference/toggle/human/dirty_synth` | `code/content/client/preferences/apply_hooks/traits.dm:20` | KEEP | keep |
| `gross_meatbag` | `/datum/preference/toggle/human/gross_meatbag` | `code/content/client/preferences/apply_hooks/traits.dm:21` | KEEP | keep |
| `custom_link` | `/datum/preference/text/human/custom_link` | `code/content/client/preferences/_vanity_pref_types.dm:85` | KEEP | keep |
| `real_name` | `/datum/preference/name/real_name` | `code/content/admin/verbs/randomverbs.dm:534` | KEEP | keep |
| `nickname` | `/datum/preference/name/nickname` | `code/content/client/preferences.dm:417` | KEEP | keep |
| `nif_path` | `/datum/preference/nif_path` | `code/content/client/preferences/apply_hooks/nif.dm:14` | KEEP | keep |
| `nif_durability` | `/datum/preference/numeric/nif_durability` | `code/content/client/preferences/apply_hooks/nif.dm:15` | KEEP | keep |
| `nif_savedata` | `/datum/preference/nif_savedata` | `code/content/client/preferences/apply_hooks/nif.dm:16` | KEEP | keep |
| `alternate_option` | `/datum/preference/numeric/human/alternate_option` | `code/content/client/preferences/editors/occupation.dm:50` | KEEP | keep |
| `player_alt_titles` | `/datum/preference/player_alt_titles` | `code/content/client/preferences/editors/occupation.dm:26` | KEEP | keep |
| `organ_data` | `/datum/preference/organ_data` | `code/content/antagonist/station/changeling.dm:86` | KEEP | keep |
| `Pai_Name` | `/datum/preference/text/pai_name` | `code/content/items/devices/paicard.dm:136` | KEEP | keep |
| `Pai_Desc` | `/datum/preference/text/pai_description` | `code/content/mob/living/silicon/pai/api.dm:118` | KEEP | keep |
| `Pai_Role` | `/datum/preference/text/pai_role` | `code/content/mob/living/silicon/pai/api.dm:89` | KEEP | keep |
| `Pai_Ad` | `/datum/preference/text/pai_ad` | `code/content/mob/living/silicon/pai/api.dm:90` | KEEP | keep |
| `Pai_Comments` | `/datum/preference/text/pai_comments` | `code/content/mob/living/silicon/pai/api.dm:120` | KEEP | keep |
| `Pai_EyeColor` | `/datum/preference/color/pai_eye_color` | `code/content/mob/living/silicon/pai/api.dm:91` | KEEP | keep |
| `Pai_Chassis` | `/datum/preference/text/pai_chassis` | `code/content/mob/living/silicon/pai/api.dm:82` | KEEP | keep |
| `Pai_Emotion` | `/datum/preference/text/pai_emotion` | `code/content/mob/living/silicon/pai/api.dm:93` | KEEP | keep |
| `persistence_settings` | `/datum/preference/numeric/human/persistence_settings` | `code/content/client/preferences/editors/persistence.dm:14` | KEEP | keep |
| `resleeve_lock` | `/datum/preference/toggle/human/resleeve_lock` | `code/content/client/preferences/apply_hooks/body_backup.dm:28` | KEEP | keep |
| `resleeve_scan` | `/datum/preference/toggle/human/resleeve_scan` | `code/content/admin/verbs/randomverbs.dm:767` | KEEP | keep |
| `mind_scan` | `/datum/preference/toggle/human/mind_scan` | `code/content/admin/verbs/randomverbs.dm:766` | KEEP | keep |
| `med_record` | `/datum/preference/text/human/med_record` | `code/content/client/record_updater.dm:218` | KEEP | keep |
| `sec_record` | `/datum/preference/text/human/sec_record` | `code/content/client/record_updater.dm:222` | KEEP | keep |
| `gen_record` | `/datum/preference/text/human/gen_record` | `code/content/client/record_updater.dm:220` | KEEP | keep |
| `rlimb_data` | `/datum/preference/rlimb_data` | `code/content/client/preferences.dm:448` | KEEP | keep |
| `robot_module` | `/datum/preference/text/human/robot_module` | `code/content/client/preferences/editors/robot_chassis.dm:22` | KEEP | keep |
| `robot_chassis` | `/datum/preference/text/human/robot_chassis` | `code/content/client/preferences/editors/robot_chassis.dm:23` | KEEP | keep |
| `play_mode` | `/datum/preference/text/human/play_mode` | `code/content/client/preferences/editors/flavor.dm:49` | KEEP | keep |
| `size_multiplier` | `/datum/preference/numeric/human/size_multiplier` | `code/content/client/preferences.dm:236` | KEEP | keep |
| `weight_vr` | `/datum/preference/numeric/human/weight_vr` | `code/content/client/preferences/_vanity_pref_types.dm:65` | KEEP | keep |
| `weight_gain` | `/datum/preference/numeric/human/weight_gain` | `code/content/client/preferences/_vanity_pref_types.dm:66` | KEEP | keep |
| `weight_loss` | `/datum/preference/numeric/human/weight_loss` | `code/content/client/preferences/_vanity_pref_types.dm:67` | KEEP | keep |
| `fuzzy` | `/datum/preference/toggle/human/fuzzy` | `code/content/client/preferences/_vanity_pref_types.dm:68` | KEEP | keep |
| `offset_override` | `/datum/preference/toggle/human/offset_override` | `code/content/client/preferences/_vanity_pref_types.dm:69` | KEEP | keep |
| `voice_freq` | `/datum/preference/numeric/human/voice_freq` | `code/content/client/preferences/_vanity_pref_types.dm:70` | KEEP | keep |
| `voice_sound` | `/datum/preference/text/human/voice_sound` | `code/content/client/preferences/_vanity_pref_types.dm:71` | KEEP | keep |
| `custom_speech_bubble` | `/datum/preference/text/human/custom_speech_bubble` | `code/content/client/preferences/_vanity_pref_types.dm:72` | KEEP | keep |
| `custom_footstep` | `/datum/preference/text/human/custom_footstep` | `apply proc in size_voice.dm` | KEEP | keep |
| `species_sound` | `/datum/preference/text/human/species_sound` | `code/content/client/preferences/apply_hooks/traits.dm:43` | KEEP | keep |
| `species` | `/datum/preference/choiced/species` | `code/content/antagonist/station/changeling.dm:83` | KEEP | keep |
| `custom_say` | `/datum/preference/text/human/custom_say` | `code/content/client/preferences/_vanity_pref_types.dm:75` | KEEP | keep |
| `custom_whisper` | `/datum/preference/text/human/custom_whisper` | `code/content/client/preferences/_vanity_pref_types.dm:76` | KEEP | keep |
| `custom_ask` | `/datum/preference/text/human/custom_ask` | `code/content/client/preferences/_vanity_pref_types.dm:77` | KEEP | keep |
| `custom_exclaim` | `/datum/preference/text/human/custom_exclaim` | `code/content/client/preferences/_vanity_pref_types.dm:78` | KEEP | keep |
| `custom_species` | `/datum/preference/text/human/custom_species` | `code/content/client/preferences/_vanity_pref_types.dm:18` | KEEP | keep |
| `vore_egg_type` | `/datum/preference/text/human/vore_egg_type` | `apply proc in vore_basic.dm` | KEEP | keep |
| `autohiss` | `/datum/preference/text/human/autohiss` | `code/content/mob/living/autohiss.dm:11` | KEEP | keep |

## Game preferences (129)

| Key | Type | Read at | Class | Action |
|---|---|---|---|---|
| `ability_order` | `/datum/preference/ability_order` | `code/content/abilities/ability_panel.dm:11` | KEEP | keep |
| `ADMIN_VERB_PINS` | `/datum/preference/text/admin_verb_pins` | `code/content/admin/admin_verb_browser.dm:134` | KEEP | keep |
| `ADMIN_VERB_RECENT` | `/datum/preference/text/admin_verb_recent` | `code/content/admin/admin_verb_browser.dm:188` | KEEP | keep |
| `CHAT_FLOATING` | `/datum/preference/toggle/chat_floating` | `code/content/client/floating_chat.dm:217` | KEEP | keep |
| `CHAT_DOCK_SIDE` | `/datum/preference/choiced/chat_dock_side` | `code/content/client/floating_chat.dm:55` | KEEP | keep |
| `CHAT_SHARE` | `/datum/preference/numeric/chat_share` | `code/content/client/floating_chat.dm:218` | KEEP | keep |
| `CHAT_INLINE_INPUT` | `/datum/preference/toggle/chat_inline_input` | `code/content/client/floating_chat.dm:92` | KEEP | keep |
| `CHAT_ATTACKLOGS` | `/datum/preference/toggle/show_attack_logs` | `code/content/admin/admin.dm:20` | KEEP | keep |
| `CHAT_DEBUGLOGS` | `/datum/preference/toggle/show_debug_logs` | `apply proc in admin.dm` | DEAD | deleted (no reader) |
| `CHAT_PRAYER` | `/datum/preference/toggle/show_chat_prayers` | `code/content/admin/verbs/pray.dm:26` | KEEP | keep |
| `SOUND_ADMINHELP` | `/datum/preference/toggle/holder/play_adminhelp_ping` | `code/content/admin/verbs/adminpm.dm:186` | KEEP | keep |
| `CHAT_RADIO` | `/datum/preference/toggle/holder/hear_radio` | `code/content/machinery/telecomms/broadcaster.dm:388` | KEEP | keep |
| `CHAT_RLOOC` | `/datum/preference/toggle/holder/show_rlooc` | `code/content/client/verbs/ooc.dm:166` | KEEP | keep |
| `CHAT_ADSAY` | `/datum/preference/toggle/holder/show_staff_dsay` | `code/content/mob/mob_helpers.dm:420` | KEEP | keep |
| `vvdark` | `/datum/preference/toggle/holder/vv_dark` | `apply proc in admin.dm` | DEAD | deleted (no reader) |
| `vvgfi` | `/datum/preference/toggle/holder/vv_gfi` | `apply proc in admin.dm` | DEAD | deleted (no reader) |
| `ooccolor` | `/datum/preference/color/ooc_color` | `code/content/client/verbs/ooc.dm:76` | KEEP | keep |
| `VISIBLE_TUMMIES` | `/datum/preference/toggle/tummy_sprites` | `code/content/mob/living/carbon/human/human_helpers.dm:213` | KEEP | keep |
| `BELCH_NOISES` | `/datum/preference/toggle/tummy_sprites` | `code/content/mob/living/carbon/human/human_helpers.dm:213` | KEEP | keep |
| `EATING_NOISES` | `/datum/preference/toggle/eating_noises` | `code/content/mob/living/silicon/robot/dogborg/dog_sleeper.dm:180` | KEEP | keep |
| `DIGEST_NOISES` | `/datum/preference/toggle/digestion_noises` | `code/content/behaviours/slosh.dm:95` | KEEP | keep |
| `VORE_HEALTH_BARS` | `/datum/preference/toggle/vore_health_bars` | `code/content/vore/chat_healthbars.dm:68` | KEEP | keep |
| `auto_fit_viewport` | `/datum/preference/toggle/auto_fit_viewport` | `code/content/client/verbs/ooc.dm:295` | KEEP | keep |
| `CHAT_SHOWICONS` | `/datum/preference/toggle/chat_tags` | `code/library/ui/tgchat/text_tags.dm:14` | KEEP | keep |
| `SHOW_TYPING` | `/datum/preference/toggle/show_typing_indicator` | `code/content/client/verbs/typing.dm:10` | KEEP | keep |
| `SHOW_TYPING_SUBTLE` | `/datum/preference/toggle/show_typing_indicator_subtle` | `code/content/client/verbs/typing.dm:37` | KEEP | keep |
| `CHAT_OOC` | `/datum/preference/toggle/show_ooc` | `code/content/client/verbs/ooc.dm:15` | KEEP | keep |
| `CHAT_LOOC` | `/datum/preference/toggle/show_looc` | `code/content/client/verbs/ooc.dm:98` | KEEP | keep |
| `CHAT_DEAD` | `/datum/preference/toggle/show_dsay` | `code/content/admin/verbs/deadsay.dm:6` | KEEP | keep |
| `CHAT_MENTION` | `/datum/preference/toggle/check_mention` | `code/content/mob/hear_say.dm:125` | KEEP | keep |
| `NEWS_POPUP` | `/datum/preference/toggle/show_lore_news` | `apply proc in chat.dm` | DEAD | deleted (no reader; the lore news popup is gone) |
| `RECEIVE_TIPS` | `/datum/preference/toggle/player_tips` | `code/content/player_tips/player_tips_controller.dm:36` | KEEP | keep |
| `PAIN_FREQUENCY` | `/datum/preference/toggle/pain_frequency` | `code/domains/body/pain.dm:27` | NICHE | Advanced group. |
| `EXAMINE_IN_CHAT` | `/datum/preference/toggle/examine_in_chat` | `code/content/examine/inspect_panel.dm:4` | KEEP | keep |
| `EXAMINE_MODE` | `/datum/preference/choiced/examine_mode` | `code/content/client/preferences/types/game/chat.dm:77` | KEEP | keep |
| `MULTI_LANGUAGE_YAP_MODE` | `/datum/preference/choiced/multilingual_mode` | `code/content/client/preferences/types/game/chat.dm:87` | KEEP | keep |
| `client_fps` | `/datum/preference/numeric/fps` | `apply proc in fps.dm` | KEEP | keep |
| `BORDERLESS_FULLSCREEN` | `/datum/preference/toggle/borderless_fullscreen` | `code/content/client/preferences/types/game/fullscreen.dm:28` | KEEP | keep |
| `WHISUBTLE_VIS` | `/datum/preference/toggle/whisubtle_vis` | `code/content/mob/living/say.dm:380` | KEEP | keep |
| `GHOST_SEE_WHISUBTLE` | `/datum/preference/toggle/ghost_see_whisubtle` | `code/content/mob/living/say.dm:379` | KEEP | keep |
| `CHAT_GHOSTEARS` | `/datum/preference/toggle/ghost_ears` | `code/content/items/devices/communicator/messaging.dm:230` | KEEP | keep |
| `CHAT_GHOSTSIGHT` | `/datum/preference/toggle/ghost_sight` | `code/library/helpers/game.dm:301` | KEEP | keep |
| `CHAT_GHOSTRADIO` | `/datum/preference/toggle/ghost_radio` | `code/content/machinery/telecomms/broadcaster.dm:395` | KEEP | keep |
| `ignored_players` | `/datum/preference/ignored_players` | `code/content/client/verbs/ignore.dm:22` | KEEP | keep |
| `HotkeyButtons` | `/datum/preference/toggle/hotkey_buttons` | `code/content/hud/human.dm:313` | KEEP | keep |
| `HardsuitActivation` | `/datum/preference/choiced/hardsuit_activation` | `code/content/click/rig.dm:4` | KEEP | keep |
| `ShowNutrition` | `/datum/preference/toggle/show_nutrition` | `code/content/client/preferences/types/game/in_game.dm:81` | KEEP | keep |
| `MicroPickup` | `/datum/preference/toggle/micro_pickup` | `code/content/client/preferences/types/game/in_game.dm:73` | KEEP | keep |
| `BellyEntranceLogs` | `/datum/preference/toggle/belly_entrance_logs` | `code/content/client/preferences/types/game/in_game.dm:74` | KEEP | keep |
| `LiquidbellyVisuals` | `/datum/preference/toggle/liquidbelly_visuals` | `code/content/client/preferences/types/game/in_game.dm:75` | KEEP | keep |
| `MAP_SPLIT` | `/datum/preference/numeric/map_split` | `code/content/client/preferences/types/game/map_split.dm:33` | KEEP | keep |
| `AMBIENT_OCCLUSION_PREF` | `/datum/preference/toggle/ambient_occlusion` | `code/content/mob/login.dm:81` | KEEP | keep |
| `ATTACK_ICONS` | `/datum/preference/toggle/attack_icons` | `code/content/mob/animations.dm:153` | KEEP | keep |
| `PRECISE_PLACEMENT` | `/datum/preference/toggle/precision_placement` | `code/content/casino/casino.dm:29` | KEEP | keep |
| `HUD_HOTKEYS` | `/datum/preference/toggle/hotkeys_default` | `apply proc in misc.dm` | DEAD | deleted (no reader) |
| `SHOW_PROGRESS` | `/datum/preference/toggle/show_progress_bar` | `apply proc in misc.dm` | DEAD | deleted (no reader) |
| `SAFE_FIRING` | `/datum/preference/toggle/safefiring` | `code/content/items/weapons/flamethrower.dm:86` | KEEP | keep |
| `SHOW_STATUS` | `/datum/preference/toggle/status_indicators` | `code/content/mob/login.dm:86` | KEEP | keep |
| `AUTO_AFK` | `/datum/preference/toggle/auto_afk` | `code/domains/life/living_systems.dm:172` | KEEP | keep |
| `MessengerEmbeds` | `/datum/preference/toggle/messenger_embeds` | `code/content/pda/messenger.dm:25` | KEEP | keep |
| `AutoPunctuation` | `/datum/preference/toggle/autopunctuation` | `code/content/mob/living/say.dm:203` | KEEP | keep |
| `BrowserDevTools` | `/datum/preference/toggle/browser_dev_tools` | `code/content/client/client_procs.dm:358` | KEEP | keep |
| `obfuscate_key` | `/datum/preference/toggle/obfuscate_key` | `code/content/mob/new_player/new_player.dm:46` | NICHE | Advanced group. |
| `obfuscate_job` | `/datum/preference/toggle/obfuscate_job` | `code/content/mob/new_player/new_player.dm:47` | NICHE | Advanced group. |
| `lastchangelog` | `/datum/preference/text/lastchangelog` | `code/content/mob/mob.dm:540` | KEEP | keep |
| `EMOTE_VARY` | `/datum/preference/toggle/random_emote_pitch` | `code/content/emotes/emote_define.dm:201` | NICHE | merge with the character emote_sound_mode. |
| `AUTOTRANSCORE` | `/datum/preference/toggle/autotranscore` | `code/content/resleeving/infocore_records.dm:57` | KEEP | keep |
| `RUNECHAT_MOB` | `/datum/preference/toggle/runechat_mob` | `code/content/balloon_alert/balloon_alert.dm:29` | KEEP | keep |
| `RUNECHAT_OBJ` | `/datum/preference/toggle/runechat_obj` | `code/content/runechat/chat_message.dm:327` | KEEP | keep |
| `RUNECHAT_BORDER` | `/datum/preference/toggle/runechat_border` | `code/content/runechat/chat_message.dm:344` | NICHE | Advanced group. |
| `RUNECHAT_LONG` | `/datum/preference/toggle/runechat_long_messages` | `code/content/runechat/chat_message.dm:114` | NICHE | Advanced group. |
| `RUNECHAT_BALLOON_MESSAGES` | `/datum/preference/toggle/runechat_balloon_messages` | `code/content/balloon_alert/balloon_alert.dm:14` | KEEP | keep |
| `SOUND_MIDI` | `/datum/preference/toggle/play_admin_midis` | `code/content/admin/verbs/playsound.dm:62` | KEEP | keep |
| `SOUND_LOBBY` | `/datum/preference/toggle/play_lobby_music` | `code/content/sound/sound.dm:167` | KEEP | keep |
| `SOUND_AMBIENCE` | `/datum/preference/toggle/play_ambience` | `code/content/mob/living/carbon/human/life.dm:1310` | KEEP | keep |
| `SOUND_JUKEBOX` | `/datum/preference/toggle/play_jukebox` | `code/content/media/mediamanager.dm:121` | KEEP | keep |
| `SOUND_INSTRUMENT` | `/datum/preference/toggle/instrument_toggle` | `apply proc in sound.dm` | DUPLICATE | deleted (no reader); the Instruments volume sound_instruments is the setting |
| `EMOTE_NOISES` | `/datum/preference/toggle/emote_noises` | `code/content/emotes/definitions/audible_belch.dm:5` | KEEP | keep |
| `RADIO_SOUNDS` | `/datum/preference/toggle/radio_sounds` | `code/content/items/devices/radio/headset.dm:70` | KEEP | keep |
| `SAY_SOUNDS` | `/datum/preference/toggle/say_sounds` | `code/content/mob/living/say.dm:427` | KEEP | keep |
| `BLOOP_SOUNDS` | `/datum/preference/toggle/bloop_sounds` | `code/content/mob/living/say.dm:440` | KEEP | keep |
| `EMOTE_SOUNDS` | `/datum/preference/toggle/emote_sounds` | `code/content/emotes/custom_emote.dm:103` | KEEP | keep |
| `WHISPER_SOUNDS` | `/datum/preference/toggle/whisper_sounds` | `code/content/mob/living/say.dm:420` | KEEP | keep |
| `SUBTLE_SOUNDS` | `/datum/preference/toggle/subtle_sounds` | `code/content/mob/living/simple_mob/subtypes/animal/alien_animals/stardog.dm:524` | KEEP | keep |
| `SOUND_AIRPUMP` | `/datum/preference/toggle/air_pump_noise` | `code/content/looping_sounds/machinery_sounds.dm:106` | NICHE | fold into the Machinery Idle volume channel. |
| `SOUND_OLDDOORS` | `/datum/preference/toggle/old_door_sounds` | `code/content/machinery/doors/airlock.dm:1044` | NICHE | merge with SOUND_DEPARTMENTDOORS into one door sound style choice. |
| `SOUND_DEPARTMENTDOORS` | `/datum/preference/toggle/department_door_sounds` | `code/content/machinery/doors/airlock.dm:1046` | NICHE | see SOUND_OLDDOORS. |
| `SOUND_PICKED` | `/datum/preference/toggle/pickup_sounds` | `code/domains/world_model/obj/items.dm:405` | KEEP | keep |
| `SOUND_DROPPED` | `/datum/preference/toggle/drop_sounds` | `code/content/mob/living/inventory.dm:63` | KEEP | keep |
| `SOUND_WEATHER` | `/datum/preference/toggle/weather_sounds` | `code/content/admin/verbs/lightning_strike.dm:77` | KEEP | keep |
| `SOUND_SUPERMATTER` | `/datum/preference/toggle/supermatter_hum` | `code/content/looping_sounds/machinery_sounds.dm:16` | NICHE | fold into the Machinery volume channel. |
| `SOUND_MENTORHELP` | `/datum/preference/toggle/play_mentorhelp_ping` | `code/content/tickets/mentor_pm.dm:467` | KEEP | keep |
| `ambience_freq` | `/datum/preference/numeric/ambience_freq` | `code/domains/life/living_systems.dm:229` | NICHE | see ambience_chance. |
| `ambience_chance` | `/datum/preference/numeric/ambience_chance` | `code/domains/world_model/area/areas.dm:419` | NICHE | merge with ambience_freq into one Ambience frequency slider. |
| `volume_channels` | `/datum/preference/volume_channels` | `code/content/client/preferences/types/game/sound.dm:196` | KEEP | keep |
| `media_volume` | `/datum/preference/numeric/living/jukebox_volume` | `code/content/media/mediamanager.dm:137` | KEEP | keep |
| `sound_instruments` | `/datum/preference/numeric/volume/sound_instruments` | `code/content/instruments/songs/play_legacy.dm:86` | KEEP | keep |
| `SOUND_FRIDGEHUM` | `/datum/preference/toggle/fridge_hum` | `code/content/looping_sounds/machinery_sounds.dm:125` | NICHE | fold into the Machinery Idle volume channel. |
| `MOB_TOOLTIPS` | `/datum/preference/toggle/mob_tooltips` | `code/content/mob/mob.dm:1269` | KEEP | keep |
| `INV_TOOLTIPS` | `/datum/preference/toggle/inv_tooltips` | `code/domains/world_model/obj/items.dm:839` | KEEP | keep |
| `tooltipstyle` | `/datum/preference/choiced/tooltip_style` | `code/content/client/preferences/types/game/tooltip.dm:18` | KEEP | keep |
| `BROWSER_STYLED` | `/datum/preference/toggle/browser_style` | `apply proc in ui.dm` | DEAD | deleted (no reader) |
| `VCHAT_ENABLE` | `/datum/preference/toggle/vchat_enable` | `code/content/examine/examine.dm:103` | NICHE | oldchat fallback; the floating/docked chat assumes TGChat. Recommend delete (always on). |
| `screentips_optin` | `/datum/preference/toggle/screentips` | `code/content/interactions/presentation.dm:38` | KEEP | keep |
| `tgui_fancy` | `/datum/preference/toggle/tgui_fancy` | `code/library/ui/tgui/tgui.dm:133` | NICHE | default on; Advanced group. |
| `tgui_lock` | `/datum/preference/toggle/tgui_lock` | `code/library/ui/tgui/tgui.dm:405` | NICHE | default off; Advanced group. |
| `tgui_input_mode` | `/datum/preference/toggle/tgui_input_mode` | `code/library/ui/tgui_input/alert.dm:31` | KEEP | keep |
| `tgui_large_buttons` | `/datum/preference/toggle/tgui_large_buttons` | `code/library/ui/tgui_input/alert.dm:106` | KEEP | keep |
| `tgui_swapped_buttons` | `/datum/preference/toggle/tgui_swapped_buttons` | `code/library/ui/tgui_input/alert.dm:107` | KEEP | keep |
| `tgui_layout` | `/datum/preference/choiced/tgui_layout` | `code/content/client/preferences/types/game/ui.dm:70` | KEEP | keep |
| `TGUI_SAY` | `/datum/preference/toggle/tgui_say` | `code/content/mob/typing_indicator.dm:21` | KEEP | keep |
| `TGUI_SAY_LIGHT_MODE` | `/datum/preference/toggle/tgui_say_light` | `code/library/ui/tgui_input/say_modal/modal.dm:79` | NICHE | follow the theme instead (theme work). |
| `TGUI_SAY_PREVIEW` | `/datum/preference/toggle/tgui_say_preview` | `code/library/ui/tgui_input/say_modal/modal.dm:85` | KEEP | keep |
| `TGUI_ENABLE_SPELLCHECK` | `/datum/preference/toggle/tgui_use_spellcheck` | `code/library/ui/tgui_input/say_modal/modal.dm:84` | KEEP | keep |
| `tgui_say_emotes` | `/datum/preference/toggle/tgui_say_emotes` | `code/content/mob/typing_indicator.dm:35` | KEEP | keep |
| `tgui_say_height` | `/datum/preference/numeric/tgui_say_height` | `code/library/ui/tgui_input/say_modal/modal.dm:75` | NICHE | Advanced group. |
| `tgui_say_width` | `/datum/preference/numeric/tgui_say_width` | `code/library/ui/tgui_input/say_modal/modal.dm:74` | NICHE | Advanced group. |
| `preset_colors` | `/datum/preference/text/preset_colors` | `code/content/vore/eating/vorepanel.dm:66` | KEEP | keep |
| `ui_scale` | `/datum/preference/toggle/ui_scale` | `code/library/ui/tgui/tgui.dm:406` | KEEP | keep |
| `windowflashing` | `/datum/preference/toggle/window_flashing` | `code/library/helpers/game.dm:630` | KEEP | keep |
| `UI_style` | `/datum/preference/choiced/ui_style` | `code/content/hud/hud.dm:374` | KEEP | keep |
| `UI_style_alpha` | `/datum/preference/numeric/ui_style_alpha` | `code/content/hud/hud.dm:376` | KEEP | keep |
| `UI_style_color` | `/datum/preference/color/ui_style_color` | `code/content/hud/hud.dm:375` | KEEP | keep |
| `SOUND_ALARMLOOP` | `/datum/preference/toggle/looping_alarms` | `code/content/looping_sounds/alarm_sounds.dm:5` | NICHE | fold into the Alarms volume channel. |
| `SLEEP_MUSIC` | `/datum/preference/toggle/sleep_music` | `code/content/looping_sounds/mob_sounds.dm:28` | KEEP | keep |
| `RECYCLER_POINTS` | `/datum/preference/numeric/recycler_points` | `code/content/maint_recycler/code/maint_recycler.dm:459` | KEEP | keep |
| `EMOTE_VARY (2nd)` | `/datum/preference/toggle/random_emote_pitch` | `types/misc.dm, a second declaration` | DUPLICATE | deleted the second declaration |
| `AUTOTRANSCORE (2nd)` | `/datum/preference/toggle/autotranscore` | `types/misc.dm, a second declaration` | DUPLICATE | deleted the second declaration |
| `SOUND_FRIDGEHUM (2nd)` | `/datum/preference/toggle/fridge_hum` | `types/sound.dm, a second declaration` | DUPLICATE | deleted the second declaration |

## Player verbs (171)

Admin verbs live in the admin verb browser and are out of scope. Panel is the verb panel category; a hidden verb is run by name from a keybind, the Menu page or a UI button (the keybind test `dq_keybinding_commands_resolve` walks them).

| Verb | Name | Panel | Declared | Class | Action |
|---|---|---|---|---|---|
| `/mob/living/proc/write_ambition` | Set Ambition | VERB_CAT_IC_ANTAG | `code/content/antagonist/antagonist_objectives.dm:34` | KEEP | keep |
| `/client/verb/character_setup` | Character Setup | no | `code/content/client/client_procs.dm:916` | KEEP | keep |
| `/client/verb/game_options` | Game Options | no | `code/content/client/client_procs.dm:924` | KEEP | keep |
| `/client/verb/show_active_playtime` | Active Playtime | no | `code/content/client/client_procs.dm:952` | KEEP | keep |
| `/client/verb/ooc_input` | .dq-ooc-input | no | `code/content/client/floating_chat.dm:102` | KEEP | keep |
| `/client/verb/toggle_floating_chat` | toggle-floating-chat | VERB_CAT_OOC_CLIENT_SETTINGS | `code/content/client/floating_chat.dm:360` | DUPLICATE | hidden; Menu: Float / dock chat |
| `/client/verb/dock_chat` | dock-chat | VERB_CAT_OOC_CLIENT_SETTINGS | `code/content/client/floating_chat.dm:366` | DUPLICATE | hidden; the float window on-close runs it |
| `/client/verb/reset_chat_window` | reset-chat-window | VERB_CAT_OOC_CLIENT_SETTINGS | `code/content/client/floating_chat.dm:373` | DUPLICATE | hidden; Menu: Reset chat window |
| `/client/verb/spinleft` | Spin View CCW | no | `code/content/client/movement.dm:6` | KEEP | keep |
| `/client/verb/spinright` | Spin View CW | no | `code/content/client/movement.dm:11` | KEEP | keep |
| `/client/verb/toggle_fullscreen` | toggle-fullscreen | VERB_CAT_OOC_CLIENT_SETTINGS | `code/content/client/preferences/types/game/fullscreen.dm:41` | DUPLICATE | hidden; Menu and the Borderless fullscreen setting |
| `/mob/verb/skincmd` | - | no | `code/content/client/skincmd.dm:10` | KEEP | keep |
| `/client/verb/tab_noop` | .dq-tab-noop | no | `code/content/client/tab_noop.dm:12` | KEEP | keep |
| `/client/verb/show_character_directory` | Character Directory | no | `code/content/client/verbs/character_directory.dm:3` | KEEP | keep |
| `/client/verb/ooc` | OOC | VERB_CAT_OOC_CHAT | `code/content/client/verbs/ooc.dm:2` | KEEP | keep |
| `/client/verb/looc` | LOOC | VERB_CAT_OOC_CHAT | `code/content/client/verbs/ooc.dm:82` | KEEP | keep |
| `/client/verb/fit_viewport` | Fit Viewport | no | `code/content/client/verbs/ooc.dm:203` | KEEP | keep |
| `/client/verb/fix_stat_panel` | Fix Stat Panel | no | `code/content/client/verbs/ooc.dm:304` | KEEP | keep |
| `/client/verb/update_ping` | .update_ping | no | `code/content/client/verbs/ping.dm:1` | KEEP | keep |
| `/client/verb/display_ping` | .display_ping | no | `code/content/client/verbs/ping.dm:14` | KEEP | keep |
| `/client/verb/ping` | Ping | no | `code/content/client/verbs/ping.dm:19` | KEEP | keep |
| `/mob/living/carbon/human/verb/suicide` | - | no | `code/content/client/verbs/suicide.dm:2` | KEEP | keep |
| `/mob/living/carbon/brain/verb/suicide` | - | no | `code/content/client/verbs/suicide.dm:16` | KEEP | keep |
| `/mob/living/silicon/ai/verb/suicide` | - | no | `code/content/client/verbs/suicide.dm:43` | KEEP | keep |
| `/mob/living/silicon/robot/verb/suicide` | - | no | `code/content/client/verbs/suicide.dm:66` | KEEP | keep |
| `/client/verb/who` | Who | VERB_CAT_OOC_RESOURCES | `code/content/client/verbs/who.dm:3` | KEEP | keep |
| `/mob/living/verb/create_env_message` | Create Env Message | VERB_CAT_OOC_GAME | `code/content/env_message/env_message.dm:51` | NICHE | one Env Messages op on the turf menu |
| `/mob/living/verb/remove_env_message` | Remove Env Message | VERB_CAT_OOC_GAME | `code/content/env_message/env_message.dm:85` | NICHE | see Create Env Message |
| `/mob/verb/mob_examine` | Mob Examine | no | `code/content/examine/examine.dm:156` | KEEP | keep |
| `/mob/verb/check_round_info` | Check Round Info | VERB_CAT_OOC_GAME | `code/content/gamemodes/game_mode.dm:595` | NICHE | move to the Menu page |
| `/mob/verb/button_pressed_F12` | F12 | no | `code/content/hud/hud.dm:444` | KEEP | keep |
| `/client/verb/handle_popup_close` | - | no | `code/content/hud/map_popups.dm:165` | KEEP | keep |
| `/client/verb/input_menu` | .input-menu | no | `code/content/interactions/menu.dm:276` | KEEP | keep |
| `/client/verb/use_ability` | .use-ability | no | `code/content/keybindings/abilities.dm:5` | KEEP | keep |
| `/client/verb/use_ability_slot` | .use-ability-slot | no | `code/content/keybindings/abilities.dm:16` | KEEP | keep |
| `/client/verb/moveKeyDown` | KeyDown | no | `code/content/keybindings/bindings_movekeys.dm:2` | KEEP | keep |
| `/client/verb/moveKeyUp` | KeyUp | no | `code/content/keybindings/bindings_movekeys.dm:33` | KEEP | keep |
| `/client/verb/hotkeys_help` | hotkeys-help | no | `code/content/keybindings/client_macros.dm:75` | KEEP | keep |
| `/client/verb/input_category` | .input-category | no | `code/content/keybindings/hover.dm:36` | KEEP | keep |
| `/mob/verb/combat_mode_key` | .combat-mode | no | `code/content/mob/combat_mode.dm:93` | KEEP | keep |
| `/mob/verb/attack_variant_key` | .attack-variant | no | `code/content/mob/combat_mode.dm:107` | KEEP | keep |
| `/mob/verb/attack_variant_key_release` | .attack-variant-release | no | `code/content/mob/combat_mode.dm:117` | KEEP | keep |
| `/mob/observer/dead/verb/cleanup` | Quit This Round | VERB_CAT_OOC_GAME | `code/content/mob/dead/observer/free.dm:3` | KEEP | keep |
| `/mob/observer/dead/verb/ghost_panel` | Ghost Panel | VERB_CAT_GHOST_GAME | `code/content/mob/dead/observer/ghost_panel.dm:199` | KEEP | keep |
| `/mob/living/verb/ghost` | Ghost | VERB_CAT_OOC_GAME | `code/content/mob/dead/observer/observer.dm:228` | KEEP | keep |
| `/mob/verb/check_languages` | Check Known Languages | no | `code/content/mob/language/language_panel.dm:121` | KEEP | keep |
| `/mob/proc/adjust_hive_range` | Adjust Special Language Range | VERB_CAT_IC_SETTINGS | `code/content/mob/language/snowflake.dm:2` | KEEP | keep |
| `/mob/living/carbon/human/verb/hide_wings_vr` | Show/Hide wings | VERB_CAT_IC_SETTINGS | `code/content/mob/living/carbon/human/emote.dm:538` | KEEP | keep |
| `/mob/living/carbon/human/verb/hide_tail_vr` | Show/Hide tail | VERB_CAT_IC_SETTINGS | `code/content/mob/living/carbon/human/emote.dm:550` | KEEP | keep |
| `/mob/living/carbon/human/proc/toggle_speech_sounds` | Toggle Species Speech Sounds | VERB_CAT_IC_SETTINGS | `code/content/mob/living/carbon/human/emote.dm:574` | KEEP | keep |
| `/mob/living/carbon/human/proc/bloody_doodle` | Write in blood | VERB_CAT_IC_GAME | `code/content/mob/living/carbon/human/human.dm:1482` | KEEP | keep |
| `/mob/living/carbon/human/proc/tie_hair` | Tie Hair | VERB_CAT_IC_GAME | `code/content/mob/living/carbon/human/human_powers.dm:4` | KEEP | keep |
| `/mob/living/carbon/human/proc/setmonitor_state` | Set monitor display | VERB_CAT_IC_SETTINGS | `code/content/mob/living/carbon/human/human_powers.dm:375` | KEEP | keep |
| `/mob/living/carbon/human/proc/reagent_purge` | Purge Reagents | VERB_CAT_IC_GAME | `code/content/mob/living/carbon/human/human_powers.dm:441` | KEEP | keep |
| `/mob/living/carbon/human/verb/toggle_eyes_layer` | Switch Eyes/Monitor Layer | VERB_CAT_IC_SETTINGS | `code/content/mob/living/carbon/human/human_powers.dm:458` | KEEP | keep |
| `/mob/living/carbon/human/verb/quick_equip` | quick-equip | no | `code/content/mob/living/carbon/human/inventory.dm:6` | KEEP | keep |
| `/mob/living/proc/toggle_waddle` | Toggle or Enable Waddling | VERB_CAT_PREFERENCES_CHARACTER | `code/content/mob/living/carbon/human/species/station/traits/states/waddle.dm:39` | KEEP | keep |
| `/mob/living/proc/waddle_adjust` | Waddle Adjust | VERB_CAT_PREFERENCES_CHARACTER | `code/content/mob/living/carbon/human/species/station/traits/states/waddle.dm:48` | KEEP | keep |
| `/mob/living/verb/set_default_language` | Set Default Language | no | `code/content/mob/living/default_language.dm:5` | DUPLICATE | deleted; the language panel sets it |
| `/mob/living/verb/pulled` | Pull | no | `code/content/mob/living/living.dm:64` | KEEP | keep |
| `/mob/living/verb/succumb` | Succumb to death | no | `code/content/mob/living/living.dm:99` | KEEP | keep |
| `/mob/living/verb/toggle_afk` | Toggle AFK | no | `code/content/mob/living/living.dm:134` | KEEP | keep |
| `/mob/living/verb/resist` | Resist | no | `code/content/mob/living/living.dm:341` | KEEP | keep |
| `/mob/living/verb/lay_down` | Rest | no | `code/content/mob/living/living.dm:400` | KEEP | keep |
| `/mob/living/silicon/ai/proc/ai_panel` | AI Panel | VERB_CAT_AI_COMMANDS | `code/content/mob/living/silicon/ai/ai_panel.dm:44` | KEEP | keep |
| `/mob/living/silicon/ai/proc/malf_panel` | Malfunction Panel | VERB_CAT_HARDWARE | `code/content/mob/living/silicon/ai/malf_panel.dm:28` | KEEP | keep |
| `/mob/living/silicon/robot/verb/cmd_unequip_module` | unequip-module | no | `code/content/mob/living/silicon/robot/inventory.dm:17` | KEEP | keep |
| `/mob/living/silicon/robot/verb/rest_style` | Switch Rest Style | VERB_CAT_IC_SETTINGS | `code/content/mob/living/silicon/robot/robot.dm:1468` | KEEP | keep |
| `/mob/living/simple_mob/animal/verb/set_flavour_text` | Set Flavour Text | VERB_CAT_IC_SETTINGS | `code/content/mob/living/simple_mob/subtypes/animal/animal.dm:24` | KEEP | keep |
| `/mob/verb/memory` | Notes | no | `code/content/mob/mob.dm:314` | KEEP | keep |
| `/mob/verb/abandon_mob` | Return to Menu | VERB_CAT_OOC_GAME | `code/content/mob/mob.dm:416` | KEEP | keep |
| `/client/verb/changes` | Changelog | no | `code/content/mob/mob.dm:532` | KEEP | keep |
| `/mob/verb/observe` | Observe | VERB_CAT_OOC_GAME | `code/content/mob/mob.dm:543` | KEEP | keep |
| `/mob/verb/cancel_camera` | Cancel Camera View | VERB_CAT_OOC_GAME | `code/content/mob/mob.dm:592` | KEEP | keep |
| `/mob/verb/stop_pulling` | Stop Pulling | no | `code/content/mob/mob.dm:616` | KEEP | keep |
| `/mob/verb/eastface` | - | no | `code/content/mob/mob.dm:830` | KEEP | keep |
| `/mob/verb/westface` | - | no | `code/content/mob/mob.dm:834` | KEEP | keep |
| `/mob/verb/northface` | - | no | `code/content/mob/mob.dm:838` | KEEP | keep |
| `/mob/verb/southface` | - | no | `code/content/mob/mob.dm:842` | KEEP | keep |
| `/mob/verb/face_direction` | Face Direction | no | `code/content/mob/mob.dm:1015` | KEEP | keep |
| `/mob/verb/northfaceperm` | - | no | `code/content/mob/mob.dm:1049` | KEEP | keep |
| `/mob/verb/southfaceperm` | - | no | `code/content/mob/mob.dm:1053` | KEEP | keep |
| `/mob/verb/eastfaceperm` | - | no | `code/content/mob/mob.dm:1057` | KEEP | keep |
| `/mob/verb/westfaceperm` | - | no | `code/content/mob/mob.dm:1061` | KEEP | keep |
| `/mob/verb/shiftnorth` | - | no | `code/content/mob/mob.dm:1066` | KEEP | keep |
| `/mob/verb/shiftsouth` | - | no | `code/content/mob/mob.dm:1074` | KEEP | keep |
| `/mob/verb/shiftwest` | - | no | `code/content/mob/mob.dm:1082` | KEEP | keep |
| `/mob/verb/shifteast` | - | no | `code/content/mob/mob.dm:1090` | KEEP | keep |
| `/mob/verb/planeup` | - | no | `code/content/mob/mob.dm:1098` | KEEP | keep |
| `/mob/verb/planedown` | - | no | `code/content/mob/mob.dm:1111` | KEEP | keep |
| `/mob/verb/spacebar_throw_on` | .throwon | no | `code/content/mob/mob.dm:1159` | KEEP | keep |
| `/mob/verb/spacebar_throw_off` | .throwoff | no | `code/content/mob/mob.dm:1165` | KEEP | keep |
| `/client/verb/body_toggle_head` | body-toggle-head | no | `code/content/mob/mob.dm:1182` | KEEP | keep |
| `/client/verb/body_r_arm` | body-r-arm | no | `code/content/mob/mob.dm:1187` | KEEP | keep |
| `/client/verb/body_l_arm` | body-l-arm | no | `code/content/mob/mob.dm:1192` | KEEP | keep |
| `/client/verb/body_chest` | body-chest | no | `code/content/mob/mob.dm:1197` | KEEP | keep |
| `/client/verb/body_groin` | body-groin | no | `code/content/mob/mob.dm:1202` | KEEP | keep |
| `/client/verb/body_r_leg` | body-r-leg | no | `code/content/mob/mob.dm:1207` | KEEP | keep |
| `/client/verb/body_l_leg` | body-l-leg | no | `code/content/mob/mob.dm:1212` | KEEP | keep |
| `/client/verb/delete_key_pressed` | - | no | `code/content/mob/mob_movement.dm:78` | KEEP | keep |
| `/client/verb/swap_hand` | - | no | `code/content/mob/mob_movement.dm:86` | KEEP | keep |
| `/client/verb/attack_self` | Use Held Item | no | `code/content/mob/mob_movement.dm:98` | KEEP | keep |
| `/client/verb/robot_alt_mode` | Use Held Module | no | `code/content/mob/mob_movement.dm:108` | KEEP | keep |
| `/client/verb/holster_key` | Holster | no | `code/content/mob/mob_movement.dm:117` | KEEP | keep |
| `/client/verb/toggle_throw_mode` | - | no | `code/content/mob/mob_movement.dm:128` | KEEP | keep |
| `/client/verb/drop_item` | - | no | `code/content/mob/mob_movement.dm:139` | KEEP | keep |
| `/client/verb/set_incorporeal_speed` | Set Incorporeal Speed | VERB_CAT_OOC_GAME_SETTINGS | `code/content/mob/mob_movement.dm:421` | KEEP | keep |
| `/client/verb/moveup` | .moveup | no | `code/content/mob/mob_movement.dm:613` | KEEP | keep |
| `/client/verb/movedown` | .movedown | no | `code/content/mob/mob_movement.dm:618` | KEEP | keep |
| `/client/verb/moveright` | .moveright | no | `code/content/mob/mob_movement.dm:623` | KEEP | keep |
| `/client/verb/moveleft` | .moveleft | no | `code/content/mob/mob_movement.dm:628` | KEEP | keep |
| `/mob/verb/whisper` | Whisper | no | `code/content/mob/say.dm:9` | KEEP | keep |
| `/mob/verb/say_verb` | Say | no | `code/content/mob/say.dm:18` | KEEP | keep |
| `/mob/verb/me_verb` | Me | no | `code/content/mob/say.dm:33` | KEEP | keep |
| `/mob/verb/me_verb_subtle` | Subtle | no | `code/content/mob/say.dm:321` | KEEP | keep |
| `/mob/verb/me_verb_subtle_custom` | Subtle (Custom) | no | `code/content/mob/say.dm:340` | KEEP | keep |
| `/mob/verb/psay` | Psay | no | `code/content/mob/say.dm:637` | KEEP | keep |
| `/mob/verb/pme` | Pme | no | `code/content/mob/say.dm:753` | KEEP | keep |
| `/mob/living/verb/player_narrate` | Narrate (Player) | no | `code/content/mob/say.dm:867` | KEEP | keep |
| `/mob/verb/say_wrapper` | Say verb | no | `code/content/mob/typing_indicator.dm:14` | KEEP | keep |
| `/mob/verb/me_wrapper` | Me verb | no | `code/content/mob/typing_indicator.dm:28` | KEEP | keep |
| `/mob/verb/whisper_wrapper` | Whisper verb | no | `code/content/mob/typing_indicator.dm:42` | KEEP | keep |
| `/mob/verb/subtle_wrapper` | Subtle verb | no | `code/content/mob/typing_indicator.dm:53` | KEEP | keep |
| `/mob/verb/up` | Move Upwards | no | `code/content/multiz/movement.dm:1` | KEEP | keep |
| `/mob/verb/down` | Move Down | no | `code/content/multiz/movement.dm:8` | KEEP | keep |
| `/mob/living/verb/climb_down` | Climb down wall | no | `code/content/multiz/movement.dm:959` | KEEP | keep |
| `/mob/living/carbon/human/proc/set_nif_examine` | NIF Appearance | VERB_CAT_OOC_GAME_SETTINGS | `code/content/nifsoft/nif.dm:722` | KEEP | keep |
| `/mob/living/carbon/human/proc/nif_menu` | NIF Menu | VERB_CAT_IC_NIF | `code/content/nifsoft/nif_tgui.dm:125` | KEEP | keep |
| `/mob/proc/nsay` | NSay | VERB_CAT_IC_NIF | `code/content/nifsoft/software/13_soulcatcher.dm:560` | KEEP | keep |
| `/mob/proc/nme` | NMe | VERB_CAT_IC_NIF | `code/content/nifsoft/software/13_soulcatcher.dm:595` | KEEP | keep |
| `/mob/living/carbon/brain/caught_soul/verb/nsay_brain` | NSay | VERB_CAT_SOULCATCHER | `code/content/nifsoft/software/13_soulcatcher.dm:674` | KEEP | keep |
| `/mob/living/carbon/brain/caught_soul/verb/nme_brain` | NMe | VERB_CAT_SOULCATCHER | `code/content/nifsoft/software/13_soulcatcher.dm:690` | KEEP | keep |
| `/mob/living/verb/request_automated_advice` | Request Automated Advice | no | `code/content/player_tips/player_tips_controller.dm:43` | KEEP | keep |
| `/mob/verb/pointed` | Point To | no | `code/content/point/point.dm:63` | KEEP | keep |
| `/mob/verb/toggle_gun_mode` | Toggle Gun Mode | no | `code/content/projectiles/targeting/targeting_mob.dm:4` | KEEP | keep |
| `/client/verb/tcssave` | - | no | `code/content/scripting/ide.dm:1` | KEEP | keep |
| `/client/verb/tcscompile` | - | no | `code/content/scripting/ide.dm:33` | KEEP | keep |
| `/client/verb/tcsrun` | - | no | `code/content/scripting/ide.dm:90` | KEEP | keep |
| `/client/verb/exittcs` | - | no | `code/content/scripting/ide.dm:163` | KEEP | keep |
| `/client/verb/tcsrevert` | - | no | `code/content/scripting/ide.dm:181` | KEEP | keep |
| `/client/verb/tcsclearmem` | - | no | `code/content/scripting/ide.dm:211` | KEEP | keep |
| `/client/verb/mentorhelp` | Mentorhelp | no | `code/content/tickets/mentor_pm.dm:5` | KEEP | keep |
| `/client/verb/requesthelp` | Request help | no | `code/content/tickets/mentor_pm.dm:111` | KEEP | keep |
| `/client/verb/adminhelp` | Adminhelp | VERB_CAT_OOC_RESOURCES | `code/content/tickets/mentor_pm.dm:137` | DUPLICATE | hidden; Request help (F1, Menu) offers it |
| `/client/verb/adminspice` | Request Spice | no | `code/content/tickets/mentor_pm.dm:243` | KEEP | keep |
| `/client/proc/set_base_turf` | Set Base Turf | VERB_CAT_DEBUG | `code/content/turfs/base_turf.dm:17` | KEEP | keep |
| `/mob/living/proc/escapeOOC` | OOC Escape | VERB_CAT_OOC_VORE | `code/content/vore/eating/living.dm:651` | KEEP | keep |
| `/mob/living/simple_mob/proc/toggle_digestion` | Toggle Animal's Digestion | VERB_CAT_OOC_MOB_SETTINGS | `code/content/vore/eating/simple_animal.dm:44` | NICHE | move into the vore panel |
| `/mob/living/simple_mob/proc/toggle_fancygurgle` | Toggle Animal's Gurgle sounds | VERB_CAT_OOC_MOB_SETTINGS | `code/content/vore/eating/simple_animal.dm:77` | NICHE | move into the vore panel |
| `/mob/proc/enter_soulcatcher` | Enter Soulcatcher | VERB_CAT_IC_VORE | `code/content/vore/eating/soulcatcher_mob.dm:79` | NICHE | granted to every living mob at login; grant it only while a soulcatcher can take you |
| `/mob/proc/nsay_vore_ch` | NSay Vore CH | VERB_CAT_IC_VORE | `code/content/vore/eating/soulcatcher_mob.dm:100` | NICHE | merge with the NIF NSay |
| `/mob/proc/nme_vore_ch` | NMe Vore CH | VERB_CAT_IC_VORE | `code/content/vore/eating/soulcatcher_mob.dm:137` | NICHE | merge with the NIF NMe |
| `/mob/living/carbon/brain/caught_soul/vore/proc/transfer_self` | Transfer Self | VERB_CAT_SOULCATCHER | `code/content/vore/eating/soulcatcher_mob.dm:240` | KEEP | keep |
| `/mob/living/carbon/brain/caught_soul/vore/proc/reenter_body` | Re-enter Body | VERB_CAT_SOULCATCHER | `code/content/vore/eating/soulcatcher_mob.dm:270` | KEEP | keep |
| `/client/verb/vote` | Vote | VERB_CAT_OOC_GAME | `code/content/vote/vote_verb.dm:1` | KEEP | keep |
| `/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/verb/change_settings` | Change Settings | VERB_CAT_IC | `code/domains/ai/ports/swoopie.dm:42` | KEEP | keep |
| `/obj/item/organ/internal/eyes/proc/change_eye_color` | Change Eye Color | VERB_CAT_IC_SETTINGS | `code/domains/body/organs/internal/eyes.dm:29` | KEEP | keep |
| `/mob/living/silicon/verb/set_flavor` | Set Flavour Text | VERB_CAT_IC_SETTINGS | `code/domains/world_model/mob/silicon.dm:279` | KEEP | keep |
| `/mob/living/simple_mob/verb/toggle_speech_sounds` | Toggle Species Speech Sounds | VERB_CAT_IC_MOB | `code/domains/world_model/mob/simple_mob.dm:903` | KEEP | keep |
| `/client/verb/export_chat` | Export Chatlog | no | `code/library/ui/tgchat/chat_verbs.dm:1` | KEEP | keep |
| `/client/verb/tguiclose` | uiclose | no | `code/library/ui/tgui/external.dm:232` | KEEP | keep |
| `/client/verb/tgui_feedback` | Submit TGUI Feedback | no | `code/library/ui/tgui/modules/feedback.dm:34` | KEEP | keep |
| `/client/verb/fix_ui` | Fix UI | VERB_CAT_OOC_DEBUG | `code/library/ui/tgui_panel/external.dm:12` | KEEP | keep |
| `/client/verb/showrevinfo` | Show Server Revision | no | `code/world/getrev.dm:54` | KEEP | keep |
| `/client/verb/wiki` | wiki | no | `interface/interface.dm:2` | KEEP | keep |
| `/client/verb/forum` | forum | no | `interface/interface.dm:19` | KEEP | keep |
| `/client/verb/rules` | Rules | no | `interface/interface.dm:31` | KEEP | keep |
| `/client/verb/map` | Map | no | `interface/interface.dm:44` | KEEP | keep |
| `/client/verb/github` | GitHub | no | `interface/interface.dm:57` | KEEP | keep |
| `/client/verb/discord` | Discord | no | `interface/interface.dm:70` | KEEP | keep |
| `/client/verb/patreon` | Patreon | no | `interface/interface.dm:83` | KEEP | keep |

## Second pass (2026-11-07, user-approved: halve every area)

| Area | Before | After |
|---|---|---|
| Character preferences | 162 | 106 |
| Game settings | 119 (the first count missed BELCH_NOISES) | 48 |
| Verbs in the verb panel | 50 | 19 |

### Game settings cut

| Key | Type | Now |
|---|---|---|
| `ambience_chance` | `/datum/preference/numeric/ambience_chance` | hardcoded `35` |
| `ambience_freq` | `/datum/preference/numeric/ambience_freq` | hardcoded `5` |
| `ATTACK_ICONS` | `/datum/preference/toggle/attack_icons` | hardcoded `TRUE` |
| `AUTO_AFK` | `/datum/preference/toggle/auto_afk` | hardcoded `TRUE` |
| `auto_fit_viewport` | `/datum/preference/toggle/auto_fit_viewport` | hardcoded `TRUE` |
| `AutoPunctuation` | `/datum/preference/toggle/autopunctuation` | hardcoded `FALSE` |
| `BELCH_NOISES` | `/datum/preference/toggle/belch_noises` | volume channel `VOLUME_CHANNEL_VORE` |
| `BellyEntranceLogs` | `/datum/preference/toggle/belly_entrance_logs` | hardcoded `TRUE` |
| `BLOOP_SOUNDS` | `/datum/preference/toggle/bloop_sounds` | volume channel `VOLUME_CHANNEL_VOICE` |
| `CHAT_GHOSTRADIO` | `/datum/preference/toggle/ghost_radio` | merged into `CHAT_GHOSTEARS` |
| `CHAT_GHOSTSIGHT` | `/datum/preference/toggle/ghost_sight` | merged into `CHAT_GHOSTEARS` |
| `CHAT_INLINE_INPUT` | `/datum/preference/toggle/chat_inline_input` | hardcoded `TRUE` |
| `CHAT_SHOWICONS` | `/datum/preference/toggle/chat_tags` | hardcoded `TRUE` |
| `DIGEST_NOISES` | `/datum/preference/toggle/digestion_noises` | volume channel `VOLUME_CHANNEL_VORE` |
| `EATING_NOISES` | `/datum/preference/toggle/eating_noises` | volume channel `VOLUME_CHANNEL_VORE` |
| `EMOTE_NOISES` | `/datum/preference/toggle/emote_noises` | volume channel `VOLUME_CHANNEL_VOICE` |
| `EMOTE_SOUNDS` | `/datum/preference/toggle/emote_sounds` | volume channel `VOLUME_CHANNEL_VOICE` |
| `EMOTE_VARY` | `/datum/preference/toggle/random_emote_pitch` | hardcoded `TRUE` |
| `GHOST_SEE_WHISUBTLE` | `/datum/preference/toggle/ghost_see_whisubtle` | merged into `CHAT_GHOSTEARS` |
| `HardsuitActivation` | `/datum/preference/choiced/hardsuit_activation` | hardcoded `HARDSUIT_CLICK_MIDDLE` |
| `HotkeyButtons` | `/datum/preference/toggle/hotkey_buttons` | hardcoded `TRUE` |
| `INV_TOOLTIPS` | `/datum/preference/toggle/inv_tooltips` | hardcoded `TRUE` |
| `LiquidbellyVisuals` | `/datum/preference/toggle/liquidbelly_visuals` | hardcoded `TRUE` |
| `MessengerEmbeds` | `/datum/preference/toggle/messenger_embeds` | hardcoded `TRUE` |
| `MOB_TOOLTIPS` | `/datum/preference/toggle/mob_tooltips` | hardcoded `TRUE` |
| `MULTI_LANGUAGE_YAP_MODE` | `/datum/preference/choiced/multilingual_mode` | hardcoded `MULTILINGUAL_DEFAULT` |
| `obfuscate_job` | `/datum/preference/toggle/obfuscate_job` | hardcoded `FALSE` |
| `obfuscate_key` | `/datum/preference/toggle/obfuscate_key` | hardcoded `FALSE` |
| `PAIN_FREQUENCY` | `/datum/preference/toggle/pain_frequency` | hardcoded `FALSE` |
| `PRECISE_PLACEMENT` | `/datum/preference/toggle/precision_placement` | hardcoded `TRUE` |
| `RADIO_SOUNDS` | `/datum/preference/toggle/radio_sounds` | volume channel `VOLUME_CHANNEL_VOICE` |
| `RECEIVE_TIPS` | `/datum/preference/toggle/player_tips` | hardcoded `TRUE` |
| `RUNECHAT_BALLOON_MESSAGES` | `/datum/preference/toggle/runechat_balloon_messages` | hardcoded `TRUE` |
| `RUNECHAT_BORDER` | `/datum/preference/toggle/runechat_border` | hardcoded `TRUE` |
| `RUNECHAT_LONG` | `/datum/preference/toggle/runechat_long_messages` | hardcoded `FALSE` |
| `RUNECHAT_OBJ` | `/datum/preference/toggle/runechat_obj` | hardcoded `TRUE` |
| `SAFE_FIRING` | `/datum/preference/toggle/safefiring` | hardcoded `TRUE` |
| `SAY_SOUNDS` | `/datum/preference/toggle/say_sounds` | volume channel `VOLUME_CHANNEL_VOICE` |
| `SHOW_STATUS` | `/datum/preference/toggle/status_indicators` | hardcoded `TRUE` |
| `SHOW_TYPING_SUBTLE` | `/datum/preference/toggle/show_typing_indicator_subtle` | merged into `SHOW_TYPING` |
| `ShowNutrition` | `/datum/preference/toggle/show_nutrition` | hardcoded `TRUE` |
| `SLEEP_MUSIC` | `/datum/preference/toggle/sleep_music` | hardcoded `TRUE` |
| `SOUND_AIRPUMP` | `/datum/preference/toggle/air_pump_noise` | volume channel `VOLUME_CHANNEL_MACHINERY_IDLE` |
| `SOUND_ALARMLOOP` | `/datum/preference/toggle/looping_alarms` | volume channel `VOLUME_CHANNEL_ALARMS` |
| `SOUND_AMBIENCE` | `/datum/preference/toggle/play_ambience` | volume channel `VOLUME_CHANNEL_AMBIENCE` |
| `SOUND_DEPARTMENTDOORS` | `/datum/preference/toggle/department_door_sounds` | hardcoded `TRUE` |
| `SOUND_DROPPED` | `/datum/preference/toggle/drop_sounds` | hardcoded `TRUE` |
| `SOUND_FRIDGEHUM` | `/datum/preference/toggle/fridge_hum` | volume channel `VOLUME_CHANNEL_MACHINERY_IDLE` |
| `SOUND_JUKEBOX` | `/datum/preference/toggle/play_jukebox` | the jukebox volume (`media_volume`) |
| `SOUND_OLDDOORS` | `/datum/preference/toggle/old_door_sounds` | hardcoded `FALSE` |
| `SOUND_PICKED` | `/datum/preference/toggle/pickup_sounds` | hardcoded `TRUE` |
| `SOUND_SUPERMATTER` | `/datum/preference/toggle/supermatter_hum` | volume channel `VOLUME_CHANNEL_MACHINERY` |
| `SOUND_WEATHER` | `/datum/preference/toggle/weather_sounds` | volume channel `VOLUME_CHANNEL_WEATHER` |
| `SUBTLE_SOUNDS` | `/datum/preference/toggle/subtle_sounds` | volume channel `VOLUME_CHANNEL_VOICE` |
| `tgui_fancy` | `/datum/preference/toggle/tgui_fancy` | hardcoded `TRUE` |
| `tgui_input_mode` | `/datum/preference/toggle/tgui_input_mode` | hardcoded `TRUE` |
| `tgui_large_buttons` | `/datum/preference/toggle/tgui_large_buttons` | hardcoded `TRUE` |
| `tgui_lock` | `/datum/preference/toggle/tgui_lock` | hardcoded `FALSE` |
| `TGUI_SAY` | `/datum/preference/toggle/tgui_say` | hardcoded `TRUE` |
| `tgui_say_emotes` | `/datum/preference/toggle/tgui_say_emotes` | hardcoded `TRUE` |
| `tgui_say_height` | `/datum/preference/numeric/tgui_say_height` | hardcoded `1` |
| `TGUI_SAY_LIGHT_MODE` | `/datum/preference/toggle/tgui_say_light` | hardcoded `FALSE` |
| `TGUI_SAY_PREVIEW` | `/datum/preference/toggle/tgui_say_preview` | hardcoded `TRUE` |
| `tgui_say_width` | `/datum/preference/numeric/tgui_say_width` | hardcoded `360` |
| `tgui_swapped_buttons` | `/datum/preference/toggle/tgui_swapped_buttons` | hardcoded `FALSE` |
| `tooltipstyle` | `/datum/preference/choiced/tooltip_style` | hardcoded `GLOB.all_tooltip_styles[1]` |
| `UI_style_alpha` | `/datum/preference/numeric/ui_style_alpha` | hardcoded `255` |
| `UI_style_color` | `/datum/preference/color/ui_style_color` | hardcoded `COLOR_WHITE` |
| `VCHAT_ENABLE` | `/datum/preference/toggle/vchat_enable` | hardcoded `TRUE` |
| `VORE_HEALTH_BARS` | `/datum/preference/toggle/vore_health_bars` | hardcoded `TRUE` |
| `WHISPER_SOUNDS` | `/datum/preference/toggle/whisper_sounds` | volume channel `VOLUME_CHANNEL_VOICE` |

Moved to staff only: `BrowserDevTools` (debug rights), `SOUND_MENTORHELP` (mentors and admins).

A per-sound toggle that was off in an old save sets its volume channel to 0 (`GLOB.retired_sound_toggle_channels`). A new channel, Voices and Emotes, carries speech blips, emote and radio sounds.

### Character preferences cut

| Key | Type | Now |
|---|---|---|
| `animations_toggle` | `/datum/preference/toggle/human/animations_toggle` | hardcoded `FALSE` |
| `antag_faction` | `/datum/preference/text/human/antag_faction` | hardcoded `"None"` |
| `antag_vis` | `/datum/preference/choiced/human/antag_vis` | hardcoded `"Hidden"` |
| `auto_backup_implant` | `/datum/preference/toggle/human/auto_backup_implant` | hardcoded `FALSE` |
| `autohiss` | `/datum/preference/text/human/autohiss` | hardcoded `AUTOHISS_DEFAULT_CHOICE` |
| `bday_announce` | `/datum/preference/toggle/human/bday_announce` | hardcoded `FALSE` |
| `birthplace` | `/datum/preference/text/human/birthplace` | hardcoded `"Unset"` |
| `blood_reagents` | `/datum/preference/text/human/blood_reagents` | hardcoded `"default"` |
| `borg_petting` | `/datum/preference/toggle/human/borg_petting` | hardcoded `TRUE` |
| `citizenship` | `/datum/preference/text/human/citizenship` | hardcoded `"None"` |
| `communicator_visibility` | `/datum/preference/toggle/human/communicator_visibility` | hardcoded `FALSE` |
| `custom_ask` | `/datum/preference/text/human/custom_ask` | hardcoded `null` |
| `custom_exclaim` | `/datum/preference/text/human/custom_exclaim` | hardcoded `null` |
| `custom_footstep` | `/datum/preference/text/human/custom_footstep` | hardcoded `"Default"` |
| `custom_link` | `/datum/preference/text/human/custom_link` | hardcoded `null` |
| `custom_say` | `/datum/preference/text/human/custom_say` | hardcoded `null` |
| `custom_speech_bubble` | `/datum/preference/text/human/custom_speech_bubble` | hardcoded `"default"` |
| `custom_whisper` | `/datum/preference/text/human/custom_whisper` | hardcoded `null` |
| `directory_gendertag` | `/datum/preference/choiced/human/directory_gendertag` | hardcoded `"Unset"` |
| `directory_sexualitytag` | `/datum/preference/choiced/human/directory_sexualitytag` | hardcoded `"Unset"` |
| `ears_alpha` | `/datum/preference/numeric/human/ears_alpha` | hardcoded `255` |
| `economic_status` | `/datum/preference/choiced/human/economic_status` | hardcoded `"Average"` |
| `exploit_record` | `/datum/preference/text/human/exploit_record` | hardcoded `""` |
| `flicker_break_chance` | `/datum/preference/numeric/living/flicker_break_chance` | hardcoded `0` |
| `flicker_color` | `/datum/preference/color/living/flicker_color` | hardcoded `"#E0EFF0"` |
| `flicker_distance` | `/datum/preference/numeric/living/flicker_distance` | hardcoded `4` |
| `flicker_time` | `/datum/preference/numeric/living/flicker_time` | hardcoded `10` |
| `fuzzy` | `/datum/preference/toggle/human/fuzzy` | hardcoded `FALSE` |
| `gen_record` | `/datum/preference/text/human/gen_record` | hardcoded `""` |
| `grad_color` | `/datum/preference/color/human/grad_color` | hardcoded `null` |
| `grad_style_name` | `/datum/preference/text/human/grad_style` | hardcoded `null` |
| `home_system` | `/datum/preference/text/human/home_system` | hardcoded `"Unset"` |
| `ignore_shoes` | `/datum/preference/toggle/human/ignore_shoes` | hardcoded `FALSE` |
| `med_record` | `/datum/preference/text/human/med_record` | hardcoded `""` |
| `name_is_always_random` | `/datum/preference/toggle/human/name_is_always_random` | hardcoded `FALSE` |
| `nickname` | `/datum/preference/name/nickname` | hardcoded `null` |
| `offset_override` | `/datum/preference/toggle/human/offset_override` | hardcoded `TRUE` |
| `Pai_Ad` | `/datum/preference/text/pai_ad` | hardcoded `PAI_UNSET` |
| `Pai_Comments` | `/datum/preference/text/pai_comments` | hardcoded `PAI_UNSET` |
| `Pai_Desc` | `/datum/preference/text/pai_description` | hardcoded `PAI_UNSET` |
| `Pai_Role` | `/datum/preference/text/pai_role` | hardcoded `PAI_UNSET` |
| `preview_job` | `/datum/preference/toggle/human/preview_job` | hardcoded `TRUE` |
| `preview_loadout` | `/datum/preference/toggle/human/preview_loadout` | hardcoded `TRUE` |
| `religion` | `/datum/preference/text/human/religion` | hardcoded `"None"` |
| `resleeve_lock` | `/datum/preference/toggle/human/resleeve_lock` | hardcoded `FALSE` |
| `sec_record` | `/datum/preference/text/human/sec_record` | hardcoded `""` |
| `secondary_ears_alpha` | `/datum/preference/numeric/human/ears_alpha/secondary` | hardcoded `255` |
| `sensorpref` | `/datum/preference/numeric/human/sensorpref` | hardcoded `5` |
| `species_sound` | `/datum/preference/text/human/species_sound` | hardcoded `"Unset"` |
| `tail_alpha` | `/datum/preference/numeric/human/tail_alpha` | hardcoded `255` |
| `ttone` | `/datum/preference/text/human/ringtone` | hardcoded `"beep"` |
| `uplinklocation` | `/datum/preference/choiced/uplinklocation` | hardcoded `"PDA"` |
| `vore_egg_type` | `/datum/preference/text/human/vore_egg_type` | hardcoded `"Egg"` |
| `weight_gain` | `/datum/preference/numeric/human/weight_gain` | hardcoded `100` |
| `weight_loss` | `/datum/preference/numeric/human/weight_loss` | hardcoded `50` |
| `wing_alpha` | `/datum/preference/numeric/human/wing_alpha` | hardcoded `255` |

The gender and sexuality directory tags are kept for the round on the mind (set from the Character Directory) instead of saved. The shadekin flicker settings are set per round from the shadekin panel. The starting-kit editor is deleted.

### Verb panel

- Menu page, new Round section: Who, Vote, Check Round Info, Observe, Return to Menu, Cancel Camera View, Set Incorporeal Speed.
- Chat input channels: OOC, LOOC (hidden verbs, still bound).
- Abilities panel rows: Set Ambition, Adjust Special Language Range, Toggle Species Speech Sounds (human and simple mob), Write in blood, Tie Hair, Set monitor display, Purge Reagents, Toggle Waddling, Waddle Adjust, NIF Appearance, Show/Hide wings, Show/Hide tail, Switch Eyes/Monitor Layer, Switch Rest Style, Set Flavour Text (animal, silicon), Create/Remove Env Message, and the soulcatcher commands (Enter Soulcatcher, NSay/NMe Vore CH), which show only for a mob with a soulcatcher instead of being granted to every mob.
- Left in the panel: Ghost, Ghost Panel, Quit This Round (ghosts), OOC Escape, AI Panel, Malfunction Panel, NIF Menu, NSay/NMe (NIF and caught souls), Transfer Self, Re-enter Body, Change Eye Color, the animal digestion/gurgle toggles and the swoopie settings (used on an adjacent mob), Pray.

### Kept although considered

- OOC notes (six fields): merging them needs the notes editor reworked; left for a later pass.
- Colour slots (tail/wing/ear colour 3, palette): the palette links them; cutting them needs the palette editor changed.
- `bgstate`, `capture_crystal`, resleeving scans, NIF settings, job and loadout settings: the default does not serve almost everyone.
