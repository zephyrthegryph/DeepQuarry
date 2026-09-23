// Character identity: who a person IS, independent of the body or container
// they currently occupy.
//
// The mind owns its identity (/datum/mind/var/identity). Every living mob holds
// a REFERENCE to the identity of the mind it hosts (or its own, until a mind
// arrives). Bodies and containers never copy identity fields; they read them
// through `identity`. The only mob vars kept in step with it are the ones the
// engine itself needs (name/real_name, languages, dna, flavour), synced in one
// place: /mob/living/proc/bind_identity().
//
// Minds move between bodies and mind hosts (brain organs, MMIs, posibrains,
// protean cores) through /proc/transfer_mind() — see
// code/datums/components/mind_host.dm.

/datum/character_identity
	/// The character's real name.
	var/real_name
	/// The DNA of the body the character last lived in. A reference, never a
	/// clone: the embodying human's dna datum (see get_dna()).
	var/datum/dna/dna
	/// OOC notes (every field).
	var/ooc_notes
	var/ooc_notes_likes
	var/ooc_notes_dislikes
	var/ooc_notes_favs
	var/ooc_notes_maybes
	var/ooc_notes_style = FALSE
	/// Languages the character knows (the same list the embodying mob speaks with).
	var/list/languages
	/// Flavour text by zone (the same list the embodying human examines with).
	var/list/flavor_texts
	/// Persistent traits: MODIFIER_GENETIC modifier types the character carries.
	var/list/genetic_modifiers
	/// world.time the character's last body died (0 = alive).
	var/time_of_death = 0

/datum/character_identity/Destroy(force)
	dna = null
	languages = null
	flavor_texts = null
	genetic_modifiers = null
	return ..()

/// The identity's DNA, or null if the datum was replaced and deleted.
/datum/character_identity/proc/get_dna()
	if(QDELETED(dna))
		dna = null
	return dna

/// Does the character carry a persistent trait of `modifier_type` (or a subtype)?
/datum/character_identity/proc/has_genetic_modifier(modifier_type)
	for(var/path in genetic_modifiers)
		if(ispath(path, modifier_type))
			return TRUE
	return FALSE


// --- Mob side ------------------------------------------------------------------------

/mob/living
	/// The identity of the character this mob embodies. Owned by the mind when
	/// one is present; always non-null so readers never need to check.
	var/datum/character_identity/identity = new

/// Point this mob at `I` and sync the engine-facing vars from it. The ONE place
/// mob vars are synced from identity.
/mob/living/proc/bind_identity(datum/character_identity/I)
	if(!I)
		return
	identity = I
	on_identity_bound()

/// Per-type sync hook for bind_identity(). By default a mob only records its
/// name when the identity has none (a new character).
/mob/living/proc/on_identity_bound()
	if(!identity.real_name)
		identity.real_name = real_name

/// A human embodies the character: the identity references the body's DNA
/// and flavour text (what the character looks like now), and the body speaks
/// the character's languages. The name stays the character's: a body swap
/// doesn't rename anyone.
/mob/living/carbon/human/on_identity_bound()
	..()
	identity.dna = dna
	identity.flavor_texts = flavor_texts
	if(identity.languages)
		languages = identity.languages
	else
		identity.languages = languages

/// Point this mob (and its mind) at `I` WITHOUT syncing body vars: a player
/// moved by key into a body they temporarily control (dominate prey) shows
/// their own identity there, while the body keeps its own name and languages.
/mob/living/proc/share_identity(datum/character_identity/I)
	if(!I)
		return
	identity = I
	if(mind)
		mind.identity = I

/// Add/remove bookkeeping for persistent traits (see modifiers.dm).
/mob/living/proc/record_genetic_modifier(modifier_type, present)
	if(present)
		LAZYDISTINCTADD(identity.genetic_modifiers, modifier_type)
	else
		LAZYREMOVE(identity.genetic_modifiers, modifier_type)


// --- Mind side -----------------------------------------------------------------------

/datum/mind
	/// The character this mind is. Adopted from the first living body it
	/// enters and carried from then on.
	var/datum/character_identity/identity = new

/// The mind's identity, adopting its current body's if it has none yet.
/datum/mind/proc/get_identity()
	if(!identity && isliving(current))
		var/mob/living/L = current
		identity = L.identity
	return identity


// --- Moving minds --------------------------------------------------------------------

/// THE way to move a mind between bodies and mind hosts. Logs the move and
/// lets the identity follow the mind. Returns TRUE when `dest` now holds `M`.
/proc/transfer_mind(datum/mind/M, mob/living/dest, reason = "unspecified")
	if(!M || !istype(dest) || QDELETED(dest))
		return FALSE
	var/mob/from = M.current
	log_game("MIND: [M.key] ([M.name]) moved from [from ? "[from] ([from.type])" : "nowhere"] to [dest] ([dest.type]): [reason]")
	M.transfer_to(dest)
	return dest.mind == M
