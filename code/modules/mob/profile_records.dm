// A mob's identity profile record (code/engine/declare/profiles.dm): who the character says they are. Declared in the mob's
// CAPABILITIES block (mob_defines.dm) with profile(nameof(bio), /datum/record/identity). It sits on /mob, not only on humans,
// because robots, simple mobs and pAIs have flavour text, nicknames and custom say verbs too.

/// The character's background, records, flavour text, nickname, starting kit choices and say verbs.
/datum/record/identity
	/// Age in years (pure fluff).
	var/age = 30
	var/home_system = ""
	var/birthplace = ""
	var/citizenship = ""
	/// Employer recorded in the station's personnel database. This is not a social reputation faction.
	var/personal_faction = "NanoTrasen"
	var/religion = ""
	var/antag_faction = ""
	var/antag_vis = ""
	var/med_record = ""
	var/sec_record = ""
	var/gen_record = ""
	var/exploit_record = ""
	/// The one examine text of a mob without zones (robots, simple mobs); a human's is built from flavor_texts.
	var/flavor_text = ""
	/// A human's examine text by zone ("general", "head", ...). Lazy.
	var/list/flavor_texts
	var/nickname = null
	/// The headset, backpack and PDA kinds the player chose.
	var/headset = 1
	var/backbag = 2
	var/pdachoice = 1
	var/custom_say = null
	var/custom_ask = null
	var/custom_whisper = null
	var/custom_exclaim = null

/mob
	/// Who the character says they are (a profile record, built before init).
	var/datum/record/identity/bio
