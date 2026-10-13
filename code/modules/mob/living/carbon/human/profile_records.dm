// A human's profile records (code/engine/declare/profiles.dm): the character's chosen look. Declared in the human's
// CAPABILITIES block (code/library/mob/hands.dm) with profile(nameof(looks), /datum/record/appearance).

/// How the character chose to look: colours are "#rrggbb" strings, styles are sprite accessory names.
/datum/record/appearance
	var/hair_style = "Bald"
	var/hair_color = "#000000"
	var/grad_style = "none"
	var/grad_color = "#000000"
	var/facial_style = "Shaved"
	var/facial_color = "#000000"
	var/eyes_color = "#000000"
	/// Skin tone for species with HAS_SKIN_TONE (a negative darkens).
	var/skin_tone = 0
	/// Skin colour for species with HAS_SKIN_COLOR.
	var/skin_color = "#eeceb3"
	/// Whether synthetic parts that can't normally be coloured take synth_color_rgb.
	var/synth_color = FALSE
	var/synth_color_rgb = "#000000"
	/// Whether markings show on synthetic parts.
	var/synth_markings = FALSE
	/// 0 = plantigrade legs, 1+ = digitigrade.
	var/digitigrade = 0
	/// Lipstick or other make-up colour name, or null.
	var/lip_style = null
	/// The ears', tail's and wings' colours (the chosen sprite accessories' colour channels) and their alpha.
	var/ears_color = "#1e1e1e"
	var/ears_color2 = "#1e1e1e"
	var/ears_color3 = "#1e1e1e"
	var/ears_alpha = 255
	var/ears_alpha2 = 255
	var/tail_color = "#1e1e1e"
	var/tail_color2 = "#1e1e1e"
	var/tail_color3 = "#1e1e1e"
	var/tail_alpha = 255
	var/wing_color = "#1e1e1e"
	var/wing_color2 = "#1e1e1e"
	var/wing_color3 = "#1e1e1e"
	var/wing_alpha = 255

TRACKED_DATA(/datum/record/appearance, hair_style)
TRACKED_DATA(/datum/record/appearance, hair_color)
TRACKED_DATA(/datum/record/appearance, grad_style)
TRACKED_DATA(/datum/record/appearance, grad_color)
TRACKED_DATA(/datum/record/appearance, facial_style)
TRACKED_DATA(/datum/record/appearance, facial_color)
TRACKED_DATA(/datum/record/appearance, eyes_color)
TRACKED_DATA(/datum/record/appearance, skin_tone)
TRACKED_DATA(/datum/record/appearance, skin_color)
TRACKED_DATA(/datum/record/appearance, synth_color)
TRACKED_DATA(/datum/record/appearance, synth_color_rgb)
TRACKED_DATA(/datum/record/appearance, synth_markings)
TRACKED_DATA(/datum/record/appearance, digitigrade)
TRACKED_DATA(/datum/record/appearance, lip_style)
TRACKED_DATA(/datum/record/appearance, ears_color)
TRACKED_DATA(/datum/record/appearance, ears_color2)
TRACKED_DATA(/datum/record/appearance, ears_color3)
TRACKED_DATA(/datum/record/appearance, ears_alpha)
TRACKED_DATA(/datum/record/appearance, ears_alpha2)
TRACKED_DATA(/datum/record/appearance, tail_color)
TRACKED_DATA(/datum/record/appearance, tail_color2)
TRACKED_DATA(/datum/record/appearance, tail_color3)
TRACKED_DATA(/datum/record/appearance, tail_alpha)
TRACKED_DATA(/datum/record/appearance, wing_color)
TRACKED_DATA(/datum/record/appearance, wing_color2)
TRACKED_DATA(/datum/record/appearance, wing_color3)
TRACKED_DATA(/datum/record/appearance, wing_alpha)

/mob/living/carbon/human
	/// The character's chosen look (a profile record, built before init).
	var/datum/record/appearance/looks
