// Species picker editor.
//
// Replaces the auto-rendered species dropdown + the separate custom_species
// and custom_base text inputs with a single popup editor. Cards show each
// species' name + sprite thumbnail + a short pitch (first sentence of the
// blurb). Clicking a card selects; a separate "Details" toggle expands the
// full HTML blurb inside the card with internal scroll.
//
// In addition to real /datum/species entries, the picker surfaces two
// synthetic entries — "_robot" and "_pai" — that switch the character
// setup UI into cyborg-mode or pAI-mode by writing /datum/preference/text/
// human/play_mode (which the middleware reads to filter the rest of the UI).
// The underlying /datum/preference/choiced/species pref keeps its real
// organic value so switching back to a human picks up where you left off.
//
// Species the player isn't whitelisted for are filtered out — no point
// showing "you can't play this" cards.
//
// Tagged onto the "identity" / "species" group via _pref_metadata.dm; the
// three underlying organic prefs (species/custom_species/custom_base) and
// play_mode are all hidden from the auto-renderer.

#define DQ_PLAY_MODE_ROBOT_KEY "_robot"
#define DQ_PLAY_MODE_PAI_KEY   "_pai"

/datum/preference_editor/species_picker
	key = "species_picker"
	category = "identity"
	group = "species"
	sort_order = 5
	display_name = "Species"
	pref_keys = list("species", "custom_species", "custom_base", "play_mode")

/datum/preference_editor/species_picker/build_ui_data(datum/preferences/preferences)
	var/play_mode = preferences.read_preference(/datum/preference/text/human/play_mode) || "human"
	var/current_species
	switch(play_mode)
		if("robot")
			current_species = DQ_PLAY_MODE_ROBOT_KEY
		if("pai")
			current_species = DQ_PLAY_MODE_PAI_KEY
		else
			current_species = preferences.read_preference(/datum/preference/choiced/species)
			// Legacy "Custom Species" pick — fall back to Human in the UI so
			// the picker doesn't show a missing-species card. The savefile
			// still has the value; next time the user picks something the
			// pref gets overwritten with their new choice.
			if(current_species == SPECIES_CUSTOM)
				current_species = SPECIES_HUMAN
	return list(
		"current_species" = current_species,
		"custom_species" = preferences.read_preference(/datum/preference/text/human/custom_species) || "",
	)

/// First-sentence pitch from a blurb. Splits on the first period+space so we
/// don't split mid-word; falls back to the whole blurb if there's no sentence
/// break in the first ~140 chars.
/proc/dq_species_pitch(text)
	if(!istext(text))
		return ""
	var/idx = findtext(text, ". ")
	if(idx > 0 && idx <= 140)
		return copytext(text, 1, idx + 1)
	if(length_char(text) <= 140)
		return text
	return copytext_char(text, 1, 138) + "…"

/// Per-species base64 thumbnail cache. Built once at world init from the
/// species icobase "preview" state — pure icon() + icon2base64, no mannequin
/// spawn, no apply pipeline, no subsystem dependencies. The whole warm-up
/// is millisecond-scale per species and runs synchronously at world init so
/// the cache is ready before any prefs window can open.
GLOBAL_LIST_EMPTY(dq_species_preview_cache)

GLOBAL_PROTECT(dq_species_preview_cache_warm_init)
GLOBAL_LIST_INIT(dq_species_preview_cache_warm_init, dq_warm_species_preview_cache())

/proc/dq_warm_species_preview_cache()
	. = list()
	for(var/species_name in GLOB.playable_species)
		var/datum/species/S = GLOB.all_species[species_name]
		if(!S || species_name == SPECIES_CUSTOM)
			continue
		dq_species_preview_b64(S)
	// Synthetic Robot / pAI entries share the same cache so the picker can
	// render them through the same <img data:...> path as real species.
	var/icon/r = icon('icons/mob/robot/default.dmi', "default", dir = SOUTH, frame = 1, moving = FALSE)
	GLOB.dq_species_preview_cache["__robot__"] = icon2base64(r)
	var/icon/p = icon('icons/mob/pai.dmi', "pai-repairbot", dir = SOUTH, frame = 1, moving = FALSE)
	GLOB.dq_species_preview_cache["__pai__"] = icon2base64(p)

/proc/dq_species_preview_b64(datum/species/S)
	if(!istype(S))
		return null
	if(GLOB.dq_species_preview_cache[S.name])
		return GLOB.dq_species_preview_cache[S.name]
	var/icon/result_icon
	// Fast path: species's icobase has a "preview" state. Pure icon flatten.
	if(icon_exists(S.icobase, "preview"))
		result_icon = icon(S.icobase, "preview", dir = SOUTH, frame = 1, moving = FALSE)
	else
		// Slow path for species without a "preview" state (Human, Alrune,
		// etc.): spawn a throwaway mannequin in null-space, set its species,
		// flatten to PNG, qdel. ~1s per species, only runs once per world,
		// wrapped in try/catch so a single bad species can't hang the
		// init loop. Pre-warmed at world startup via dq_warm_species_preview_cache.
		try
			var/mob/living/carbon/human/dummy/mannequin/M = new(null)
			M.dna = new /datum/dna(null)
			M.set_species(S.name)
			M.update_icons_body()
			result_icon = getFlatIcon(M, defdir = SOUTH, no_anim = TRUE)
			qdel(M)
		catch(var/exception/e)
			stack_trace("dq_species_preview_b64 slow path failed for [S.name]: [e.name] at [e.file]:[e.line]")
			return null
	if(!result_icon)
		return null
	var/result = icon2base64(result_icon)
	GLOB.dq_species_preview_cache[S.name] = result
	return result

/datum/preference_editor/species_picker/build_ui_static_data(datum/preferences/preferences)
	var/list/all_species = list()
	var/client/C = preferences.client
	for(var/species_name in GLOB.playable_species)
		var/datum/species/S = GLOB.all_species[species_name]
		if(!S)
			continue
		// "Custom Species" is a placeholder species that exists for the
		// custom_species/custom_base override system, not a thing players
		// pick directly. The display-name override is now a plain inline
		// text input on the species picker trigger (see SpeciesPicker.tsx),
		// available for every species, so this entry is just confusing.
		if(species_name == SPECIES_CUSTOM)
			continue
		// Drop species the player isn't whitelisted for. is_alien_whitelisted
		// is a guard for admin-only / role-specific species; surfacing those
		// in the picker just teases the player with an unreachable option.
		if(C && !is_alien_whitelisted(C, S))
			continue
		all_species[species_name] = list(
			"name" = S.name,
			"pitch" = dq_species_pitch(S.blurb),
			"blurb" = S.blurb,
			"thumb_b64" = dq_species_preview_b64(S),
		)
	// Synthetic entries — not in GLOB.playable_species. Pin them so the
	// player can flip the character setup UI into cyborg / pAI mode through
	// the same picker. Keys are leading-underscore so they can't collide
	// with a real species name.
	all_species[DQ_PLAY_MODE_ROBOT_KEY] = list(
		"name" = "Robot",
		"pitch" = "A cyborg chassis with a positronic mind.",
		"blurb" = "A cyborg chassis with a positronic mind. Pick a module + chassis in the Chassis group; skips the post-spawn module popup.",
		"thumb_b64" = GLOB.dq_species_preview_cache["__robot__"],
	)
	all_species[DQ_PLAY_MODE_PAI_KEY] = list(
		"name" = "pAI",
		"pitch" = "A personal AI bound to a portable card.",
		"blurb" = "A personal AI — a portable holographic companion bound to a card. Configure your card details under the Game tab.",
		"thumb_b64" = GLOB.dq_species_preview_cache["__pai__"],
	)
	return list(
		"all_species" = all_species,
	)

/datum/preference_editor/species_picker/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	switch(action)
		if("set_species")
			var/value = params["value"]
			if(value == DQ_PLAY_MODE_ROBOT_KEY)
				preferences.update_preference_by_type(/datum/preference/text/human/play_mode, "robot")
				// Auto-bump the Cyborg job to high priority. Without this, picking
				// "Robot" in the species picker only flipped UI flags — the player
				// would still spawn as whatever organic job their priorities pointed
				// at (usually Intern → human). The player can still demote Cyborg
				// back down via the Jobs tab if they wanted a non-roundstart cyborg
				// flow (e.g. wait for a posibrain shell).
				preferences.set_job_priority(JOB_CYBORG, "high")
				return PREF_UPDATE_ACCEPTED
			if(value == DQ_PLAY_MODE_PAI_KEY)
				preferences.update_preference_by_type(/datum/preference/text/human/play_mode, "pai")
				// pAIs aren't roundstart — clear any Cyborg priority that the
				// player set previously when in robot mode. Other organic job
				// priorities are left alone so switching back to a human picks
				// up where they left off.
				preferences.set_job_priority(JOB_CYBORG, "off")
				return PREF_UPDATE_ACCEPTED
			if(!(value in GLOB.playable_species))
				return PREF_UPDATE_REJECTED
			preferences.update_preference_by_type(/datum/preference/text/human/play_mode, "human")
			preferences.update_preference_by_type(/datum/preference/choiced/species, value)
			// Clear Cyborg priority when switching back to an organic species so
			// the player doesn't accidentally spawn as a cyborg with a human
			// appearance just because Robot was selected earlier in the session.
			preferences.set_job_priority(JOB_CYBORG, "off")
			return PREF_UPDATE_ACCEPTED
		if("set_custom_species")
			// Plain display-name override — applies on top of whatever species
			// the player picked. custom_base (sprite override) is no longer
			// exposed; players who want a different sprite pick a different
			// species.
			preferences.update_preference_by_type(/datum/preference/text/human/custom_species, params["value"] || "")
			return PREF_UPDATE_ACCEPTED
	return PREF_UPDATE_UNCHANGED

#undef DQ_PLAY_MODE_ROBOT_KEY
#undef DQ_PLAY_MODE_PAI_KEY
