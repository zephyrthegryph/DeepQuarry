// DQAdd — Pref types that are considered "vanity" for /datum/preferences/proc/vanity_copy_to.
// These are the appearance / identity / OOC / size+voice prefs that the
// protean reconstitutor / shapeshifter / appearance changer paths want to copy from a saved
// character without copying job priorities, antag flags, or anything gameplay-affecting.
//
// Keep this list in sync with the bool flags vanity_copy_to honors:
//   copy_name        gates name + nickname
//   copy_flavour     gates flavor_texts
//   copy_ooc_notes   gates ooc_notes* (subset listed in vanity_ooc_pref_types)
//   apply_bloodtype  gates b_type

GLOBAL_LIST_INIT(vanity_pref_types, list(
	// Identity
	/datum/preference/name/real_name,
	/datum/preference/name/nickname,
	/datum/preference/choiced/gender/biological,
	/datum/preference/choiced/gender/identifying,
	/datum/preference/text/human/custom_species,
	/datum/preference/text/human/custom_base,

	// Body
	/datum/preference/numeric/human/s_tone,
	/datum/preference/color/human/skin_color,
	/datum/preference/color/human/eyes_color,
	/datum/preference/toggle/human/synth_color,
	/datum/preference/color/human/synth_color,
	/datum/preference/toggle/human/synth_markings,
	/datum/preference/toggle/human/digitigrade,
	/datum/preference/text/human/b_type,
	/datum/preference/text/human/blood_reagents,

	// Hair / face
	/datum/preference/text/human/h_style,
	/datum/preference/text/human/f_style,
	/datum/preference/text/human/grad_style,
	/datum/preference/color/human/hair_color,
	/datum/preference/color/human/facial_color,
	/datum/preference/color/human/grad_color,

	// Ears
	/datum/preference/text/human/ear_style,
	/datum/preference/text/human/ear_secondary_style,
	/datum/preference/color/human/ears_color1,
	/datum/preference/color/human/ears_color2,
	/datum/preference/color/human/ears_color3,
	/datum/preference/numeric/human/ears_alpha,
	/datum/preference/ear_secondary_colors,

	// Tail
	/datum/preference/text/human/tail_style,
	/datum/preference/color/human/tail_color1,
	/datum/preference/color/human/tail_color2,
	/datum/preference/color/human/tail_color3,
	/datum/preference/numeric/human/tail_alpha,

	// Wings
	/datum/preference/text/human/wing_style,
	/datum/preference/color/human/wing_color1,
	/datum/preference/color/human/wing_color2,
	/datum/preference/color/human/wing_color3,
	/datum/preference/numeric/human/wing_alpha,

	// Markings
	/datum/preference/body_markings,

	// Size + voice
	/datum/preference/numeric/human/size_multiplier,
	/datum/preference/numeric/human/weight_vr,
	/datum/preference/numeric/human/weight_gain,
	/datum/preference/numeric/human/weight_loss,
	/datum/preference/toggle/human/fuzzy,
	/datum/preference/toggle/human/offset_override,
	/datum/preference/numeric/human/voice_freq,
	/datum/preference/text/human/voice_sound,
	/datum/preference/text/human/custom_speech_bubble,

	// Speech verbs
	/datum/preference/text/human/custom_say,
	/datum/preference/text/human/custom_whisper,
	/datum/preference/text/human/custom_ask,
	/datum/preference/text/human/custom_exclaim,

	// Blood color
	/datum/preference/color/human/blood_color,

	// Flavor + OOC (gated by copy_flavour / copy_ooc_notes flags)
	/datum/preference/flavor_texts,
	/datum/preference/text/human/custom_link,
	/datum/preference/text/living/ooc_notes,
	/datum/preference/text/living/ooc_notes_likes,
	/datum/preference/text/living/ooc_notes_dislikes,
	/datum/preference/text/living/ooc_notes_favs,
	/datum/preference/text/living/ooc_notes_maybes,
	/datum/preference/toggle/living/ooc_notes_style,
))

GLOBAL_LIST_INIT(vanity_ooc_pref_types, list(
	/datum/preference/text/living/ooc_notes,
	/datum/preference/text/living/ooc_notes_likes,
	/datum/preference/text/living/ooc_notes_dislikes,
	/datum/preference/text/living/ooc_notes_favs,
	/datum/preference/text/living/ooc_notes_maybes,
	/datum/preference/toggle/living/ooc_notes_style,
))
