// Standard Issue starting-kit items as zero-cost loadout gear datums.
//
// Replaces the headset / backbag / pdachoice prefs (deleted). Players who don't pick
// anything still get their job's themed kit via the regular job outfit equip pipeline
// (job.equip runs after loadout — empty slots get filled). Players who DO pick get the
// generic version regardless of department theming.
//
// Note re. the slot_l_ear warning in loadout_ears.dm: that warning predates the
// loadout-equips-first ordering. With the current spawn pipeline (loadout layer first,
// job fills empty slots after), a loadout l_ear pick correctly overrides the job's
// themed headset. The headsets below intentionally use slot_l_ear.

// ── Headsets ────────────────────────────────────────────────────────────────────────

/datum/gear/standard_headset
	display_name = "standard headset"
	description = "A generic, no-channel radio headset. If you don't want your job's themed headset, pick this."
	path = /obj/item/radio/headset
	slot = slot_l_ear
	cost = 0
	sort_category = "Standard Issue"

/datum/gear/bowman_headset
	display_name = "bowman headset"
	description = "Over-the-ear variant. Generic, no channels."
	path = /obj/item/radio/headset/alt
	slot = slot_l_ear
	cost = 0
	sort_category = "Standard Issue"

/datum/gear/earbud_headset
	display_name = "earbud headset"
	description = "Discreet in-ear variant. Generic, no channels."
	path = /obj/item/radio/headset/earbud
	slot = slot_l_ear
	cost = 0
	sort_category = "Standard Issue"

// ── Backpacks ───────────────────────────────────────────────────────────────────────

/datum/gear/standard_backpack
	display_name = "backpack"
	description = "A generic backpack. Overrides your job-themed default bag."
	path = /obj/item/storage/backpack
	slot = slot_back
	cost = 0
	sort_category = "Standard Issue"

/datum/gear/standard_satchel
	display_name = "satchel"
	description = "Generic over-the-shoulder satchel."
	path = /obj/item/storage/backpack/satchel/norm
	slot = slot_back
	cost = 0
	sort_category = "Standard Issue"

/datum/gear/standard_satchel_alt
	display_name = "leather satchel"
	description = "Generic leather satchel."
	path = /obj/item/storage/backpack/satchel
	slot = slot_back
	cost = 0
	sort_category = "Standard Issue"

/datum/gear/standard_messenger
	display_name = "messenger bag"
	description = "Generic messenger bag."
	path = /obj/item/storage/backpack/messenger
	slot = slot_back
	cost = 0
	sort_category = "Standard Issue"

/datum/gear/standard_sports_bag
	display_name = "sports bag"
	description = "Generic sports bag."
	path = /obj/item/storage/backpack/sport
	slot = slot_back
	cost = 0
	sort_category = "Standard Issue"

// ── PDAs ────────────────────────────────────────────────────────────────────────────

// PDA is a single item type; chassis variants are cosmetic skins driven by H.pdachoice
// (now always default = 1, since the pdachoice pref is gone). The Standard PDA goes in
// slot_belt — the most common pda_slot across job outfits. Players whose job's pda_slot
// is a pocket (Engineering, Cargo) can still pick this and the job's themed PDA falls
// back to the unoccupied slot the job specified.
/datum/gear/standard_pda
	display_name = "personal data assistant"
	description = "A generic PDA. Configure your ringtone here. Job-themed PDAs (with department channels, ID rank) still spawn in their normal slot if you don't pick this — this generic version has neither."
	path = /obj/item/pda
	slot = slot_belt
	cost = 0
	sort_category = "Standard Issue"

/datum/gear/standard_pda/New()
	..()
	// Pin the ringtone tweak at a known index. Metadata is stored as a string-keyed dict
	// {"<idx>": <value>}, so changing the parent's gear_tweaks ordering would silently
	// reassign saved metadata to the wrong tweak. The PDA only has the parent defaults
	// (recolor, custom_name, custom_desc) ahead of this — appending at the end is stable
	// for now, but document the contract so future parent reorders trigger a save migration
	// rather than a silent reshuffle.
	gear_tweaks += GLOB.gear_tweak_pda_ringtone

// Custom tweak — ringtone is per-PDA, stored as gear metadata, applied to the spawned
// PDA's ttone. The standalone ringtone pref is still read by the job's default PDA at
// spawn (when the player didn't pick this loadout PDA); this tweak is only for the
// loadout-picked one.
GLOBAL_DATUM_INIT(gear_tweak_pda_ringtone, /datum/gear_tweak/pda_ringtone, new)

/datum/gear_tweak/pda_ringtone

/datum/gear_tweak/pda_ringtone/get_default()
	return "beep"

/datum/gear_tweak/pda_ringtone/get_contents(metadata)
	return "Ringtone: [metadata || "beep"]"

/datum/gear_tweak/pda_ringtone/get_metadata(user, metadata)
	var/list/choices = list()
	if(GLOB.device_ringtones)
		for(var/key in GLOB.device_ringtones)
			choices += key
	var/picked = tgui_input_list(user, "Pick a ringtone", "Ringtone", choices, metadata)
	if(isnull(picked))
		return metadata
	return picked

/datum/gear_tweak/pda_ringtone/tweak_item(obj/item/I, metadata)
	if(istype(I, /obj/item/pda) && istext(metadata))
		var/obj/item/pda/P = I
		P.ttone = metadata

/datum/gear_tweak/pda_ringtone/get_inline_choices()
	return GLOB.device_ringtones ? assoc_to_keys(GLOB.device_ringtones) : list()

/datum/gear_tweak/pda_ringtone/validate_inline_value(value, mob/user)
	if(!(value in GLOB.device_ringtones))
		return PREF_UPDATE_REJECTED
	return value

// ── Belt items ──────────────────────────────────────────────────────────────────────

/datum/gear/utility_belt
	display_name = "utility belt"
	description = "An empty utility belt — eight pouches for whatever tools you scrounge up."
	path = /obj/item/storage/belt/utility
	slot = slot_belt
	cost = 1
	sort_category = "Belts"

/datum/gear/medical_belt
	display_name = "medical belt"
	description = "An empty medical belt."
	path = /obj/item/storage/belt/medical
	slot = slot_belt
	cost = 1
	sort_category = "Belts"
	allowed_roles = list(JOB_MEDICAL_DOCTOR, JOB_PARAMEDIC, JOB_CHIEF_MEDICAL_OFFICER, JOB_PSYCHIATRIST, JOB_CHEMIST)

/datum/gear/security_belt
	display_name = "security belt"
	description = "An empty security belt."
	path = /obj/item/storage/belt/security
	slot = slot_belt
	cost = 1
	sort_category = "Belts"
	allowed_roles = list(JOB_SECURITY_OFFICER, JOB_WARDEN, JOB_HEAD_OF_SECURITY, JOB_DETECTIVE)

/datum/gear/utility_belt_full
	display_name = "utility belt (filled)"
	description = "A utility belt pre-loaded with screwdriver, wrench, wirecutters, multitool, and crowbar."
	path = /obj/item/storage/belt/utility/full
	slot = slot_belt
	cost = 3
	sort_category = "Belts"
	allowed_roles = list(JOB_ENGINEER, JOB_ATMOSPHERIC_TECHNICIAN, JOB_CHIEF_ENGINEER, JOB_QUARTERMASTER, JOB_ROBOTICIST)

/datum/gear/medical_belt_emt
	display_name = "EMT belt"
	description = "An EMT-style medical belt."
	path = /obj/item/storage/belt/medical/emt
	slot = slot_belt
	cost = 1
	sort_category = "Belts"
	allowed_roles = list(JOB_MEDICAL_DOCTOR, JOB_PARAMEDIC, JOB_CHIEF_MEDICAL_OFFICER)
