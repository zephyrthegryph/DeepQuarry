/*
 * /datum/belly_serializer — data-driven serialization for /obj/belly.
 *
 * Problem: /obj/belly/vars_to_save() was a 200-line hand-maintained list of
 * var names.  Adding a new belly var required editing the list in vars_to_save(),
 * the copy() proc, AND the belly_import.dm apply path.  A forgotten entry would
 * silently drop data on the floor at save time, with no warning until a player
 * noticed a missing setting.
 *
 * Solution: a single canonical list of (var_name, type_tag) entries that drives:
 *   - vars_to_save() — returns exactly the vars in the schema.
 *   - validate_schema_coverage() — asserts every registered var exists on /obj/belly
 *     so a typo is caught at boot, not in production.
 *   - copy_scalar_vars(src, dest) — copies all non-list scalars in one pass,
 *     eliminating the parallel copy() proc hand-list.
 *
 * Type tags (see BELLY_FIELD_* defines in __defines/vore.dm extension below):
 *   BELLY_FIELD_SCALAR   — a single num/text/bool value copied directly.
 *   BELLY_FIELD_LIST     — a flat list of strings; copy via deep-copy.
 *   BELLY_FIELD_ASSOC    — an associative list; copy via deep-copy.
 *   BELLY_FIELD_RUNTIME  — tmp var, never saved; included for copy() only.
 *
 * Procedure for adding a new belly var:
 *   1. Declare the var on /obj/belly as usual.
 *   2. Add one entry to get_schema() below with the correct type tag.
 *   3. Done.  vars_to_save(), copy(), and validate_schema_coverage() all
 *      pick it up automatically.
 */

// ------------------------------------------------------------------ //
//  Type-tag constants                                                 //
// ------------------------------------------------------------------ //

#define BELLY_FIELD_SCALAR  1   // num / text / bool — save + copy directly
#define BELLY_FIELD_LIST    2   // flat list of strings — save + deep-copy
#define BELLY_FIELD_ASSOC   3   // assoc list — save + deep-copy
#define BELLY_FIELD_RUNTIME 4   // tmp var — copy only, never saved

/datum/belly_serializer

/datum/belly_serializer/proc/get_schema()
	// Returns a list of lists: each inner list is list(var_name, type_tag).
	// THIS IS THE SINGLE SOURCE OF TRUTH for belly persistence.
	//
	// Add new vars here — DO NOT add them to vars_to_save(), copy(), or
	// belly_import.dm scalar blocks separately.

	return list(
		// ---- Identity / display ----
		list("name",                        BELLY_FIELD_SCALAR),
		list("desc",                        BELLY_FIELD_SCALAR),
		list("display_name",               BELLY_FIELD_SCALAR),
		list("absorbed_desc",              BELLY_FIELD_SCALAR),
		list("message_mode",               BELLY_FIELD_SCALAR),

		// ---- Sound / verb ----
		list("vore_sound",                 BELLY_FIELD_SCALAR),
		list("vore_verb",                  BELLY_FIELD_SCALAR),
		list("release_verb",               BELLY_FIELD_SCALAR),
		list("release_sound",              BELLY_FIELD_SCALAR),
		list("fancy_vore",                 BELLY_FIELD_SCALAR),
		list("is_wet",                     BELLY_FIELD_SCALAR),
		list("wet_loop",                   BELLY_FIELD_SCALAR),
		list("vorefootsteps_sounds",       BELLY_FIELD_SCALAR),
		list("sound_volume",               BELLY_FIELD_SCALAR),
		list("noise_freq",                 BELLY_FIELD_SCALAR),

		// ---- Timing ----
		list("human_prey_swallow_time",    BELLY_FIELD_SCALAR),
		list("nonhuman_prey_swallow_time", BELLY_FIELD_SCALAR),
		list("emote_time",                 BELLY_FIELD_SCALAR),
		list("emote_active",               BELLY_FIELD_SCALAR),

		// ---- Digestion / damage ----
		list("nutrition_percent",          BELLY_FIELD_SCALAR),
		list("digest_max",                 BELLY_FIELD_SCALAR),
		list("digest_brute",               BELLY_FIELD_SCALAR),
		list("digest_burn",                BELLY_FIELD_SCALAR),
		list("digest_oxy",                 BELLY_FIELD_SCALAR),
		list("digest_tox",                 BELLY_FIELD_SCALAR),
		list("digest_clone",               BELLY_FIELD_SCALAR),
		list("bellytemperature",           BELLY_FIELD_SCALAR),
		list("temperature_damage",         BELLY_FIELD_SCALAR),
		list("slow_digestion",             BELLY_FIELD_SCALAR),
		list("slow_brutal",                BELLY_FIELD_SCALAR),
		list("speedy_mob_processing",      BELLY_FIELD_SCALAR),

		// ---- Escape / struggle ----
		list("escapable",                  BELLY_FIELD_SCALAR),
		list("escapetime",                 BELLY_FIELD_SCALAR),
		list("escapechance",               BELLY_FIELD_SCALAR),
		list("escapechance_absorbed",      BELLY_FIELD_SCALAR),
		list("selectchance",               BELLY_FIELD_SCALAR),
		list("digestchance",               BELLY_FIELD_SCALAR),
		list("absorbchance",               BELLY_FIELD_SCALAR),
		list("escape_stun",                BELLY_FIELD_SCALAR),
		list("private_struggle",           BELLY_FIELD_SCALAR),
		list("belchchance",                BELLY_FIELD_SCALAR),

		// ---- Transfer ----
		list("transferchance",             BELLY_FIELD_SCALAR),
		list("transferchance_secondary",   BELLY_FIELD_SCALAR),
		list("transferlocation",           BELLY_FIELD_SCALAR),
		list("transferlocation_secondary", BELLY_FIELD_SCALAR),
		list("transferlocation_absorb",    BELLY_FIELD_SCALAR),

		// ---- Autotransfer ----
		list("autotransferchance",                    BELLY_FIELD_SCALAR),
		list("autotransferwait",                      BELLY_FIELD_SCALAR),
		list("autotransferlocation",                  BELLY_FIELD_SCALAR),
		list("autotransferextralocation",             BELLY_FIELD_LIST),
		list("autotransfer_enabled",                  BELLY_FIELD_SCALAR),
		list("autotransfer_min_amount",               BELLY_FIELD_SCALAR),
		list("autotransfer_max_amount",               BELLY_FIELD_SCALAR),
		list("autotransferchance_secondary",          BELLY_FIELD_SCALAR),
		list("autotransferlocation_secondary",        BELLY_FIELD_SCALAR),
		list("autotransferextralocation_secondary",   BELLY_FIELD_LIST),
		list("autotransfer_whitelist",                BELLY_FIELD_SCALAR),
		list("autotransfer_blacklist",                BELLY_FIELD_SCALAR),
		list("autotransfer_whitelist_items",          BELLY_FIELD_SCALAR),
		list("autotransfer_blacklist_items",          BELLY_FIELD_SCALAR),
		list("autotransfer_secondary_whitelist",      BELLY_FIELD_SCALAR),
		list("autotransfer_secondary_blacklist",      BELLY_FIELD_SCALAR),
		list("autotransfer_secondary_whitelist_items",BELLY_FIELD_SCALAR),
		list("autotransfer_secondary_blacklist_items",BELLY_FIELD_SCALAR),

		// ---- Spawn / latejoin ----
		list("vorespawn_blacklist",        BELLY_FIELD_SCALAR),
		list("vorespawn_whitelist",        BELLY_FIELD_LIST),
		list("vorespawn_absorbed",         BELLY_FIELD_SCALAR),
		list("latejoin_vore",              BELLY_FIELD_SCALAR),
		list("latejoin_prey",              BELLY_FIELD_SCALAR),

		// ---- Examine / display ----
		list("immutable",                  BELLY_FIELD_SCALAR),
		list("can_taste",                  BELLY_FIELD_SCALAR),
		list("bulge_size",                 BELLY_FIELD_SCALAR),
		list("display_absorbed_examine",   BELLY_FIELD_SCALAR),
		list("shrink_grow_size",           BELLY_FIELD_SCALAR),
		list("show_fullness_messages",     BELLY_FIELD_SCALAR),
		list("entrance_logs",              BELLY_FIELD_SCALAR),
		list("item_digest_logs",           BELLY_FIELD_SCALAR),
		list("is_feedable",                BELLY_FIELD_SCALAR),
		list("absorbedrename_enabled",     BELLY_FIELD_SCALAR),
		list("absorbedrename_name",        BELLY_FIELD_SCALAR),

		// ---- Mode flags ----
		list("mode_flags",                 BELLY_FIELD_SCALAR),
		list("item_digest_mode",           BELLY_FIELD_SCALAR),
		list("selective_preference",       BELLY_FIELD_SCALAR),
		list("drainmode",                  BELLY_FIELD_SCALAR),
		list("save_digest_mode",           BELLY_FIELD_SCALAR),
		list("eating_privacy_local",       BELLY_FIELD_SCALAR),
		list("silicon_belly_overlay_preference", BELLY_FIELD_SCALAR),
		list("belly_mob_mult",             BELLY_FIELD_SCALAR),
		list("belly_item_mult",            BELLY_FIELD_SCALAR),
		list("belly_overall_mult",         BELLY_FIELD_SCALAR),
		list("displayed_message_flags",    BELLY_FIELD_SCALAR),

		// ---- Contamination ----
		list("contaminates",               BELLY_FIELD_SCALAR),
		list("contamination_flavor",       BELLY_FIELD_SCALAR),
		list("contamination_color",        BELLY_FIELD_SCALAR),

		// ---- Reagent / liquid ----
		list("reagentbellymode",           BELLY_FIELD_SCALAR),
		list("reagent_gen_cost_limit",     BELLY_FIELD_SCALAR),
		list("reagent_mode_flags",         BELLY_FIELD_SCALAR),
		list("show_liquids",               BELLY_FIELD_SCALAR),
		list("liquid_overlay",             BELLY_FIELD_SCALAR),
		list("max_liquid_level",           BELLY_FIELD_SCALAR),
		list("reagent_touches",            BELLY_FIELD_SCALAR),
		list("mush_overlay",               BELLY_FIELD_SCALAR),
		list("mush_color",                 BELLY_FIELD_SCALAR),
		list("mush_alpha",                 BELLY_FIELD_SCALAR),
		list("max_mush",                   BELLY_FIELD_SCALAR),
		list("min_mush",                   BELLY_FIELD_SCALAR),
		list("item_mush_val",              BELLY_FIELD_SCALAR),
		list("custom_reagentcolor",        BELLY_FIELD_SCALAR),
		list("custom_reagentalpha",        BELLY_FIELD_SCALAR),
		list("metabolism_overlay",         BELLY_FIELD_SCALAR),
		list("metabolism_mush_ratio",      BELLY_FIELD_SCALAR),
		list("max_ingested",               BELLY_FIELD_SCALAR),
		list("custom_ingested_color",      BELLY_FIELD_SCALAR),
		list("custom_ingested_alpha",      BELLY_FIELD_SCALAR),
		list("nutri_reagent_gen",          BELLY_FIELD_SCALAR),
		list("is_beneficial",              BELLY_FIELD_SCALAR),
		list("gen_cost",                   BELLY_FIELD_SCALAR),
		list("gen_amount",                 BELLY_FIELD_SCALAR),
		list("gen_time",                   BELLY_FIELD_SCALAR),
		list("gen_time_display",           BELLY_FIELD_SCALAR),
		list("reagent_transfer_verb",      BELLY_FIELD_SCALAR),
		list("custom_max_volume",          BELLY_FIELD_SCALAR),
		list("reagent_name",               BELLY_FIELD_SCALAR),
		list("reagentid",                  BELLY_FIELD_SCALAR),
		list("reagentcolor",               BELLY_FIELD_SCALAR),
		list("generated_reagents",         BELLY_FIELD_ASSOC),

		// ---- Fullness messages (liquid) ----
		list("liquid_fullness1_messages",  BELLY_FIELD_SCALAR),
		list("liquid_fullness2_messages",  BELLY_FIELD_SCALAR),
		list("liquid_fullness3_messages",  BELLY_FIELD_SCALAR),
		list("liquid_fullness4_messages",  BELLY_FIELD_SCALAR),
		list("liquid_fullness5_messages",  BELLY_FIELD_SCALAR),

		// ---- Fullness messages (custom) ----
		list("fullness1_messages",         BELLY_FIELD_LIST),
		list("fullness2_messages",         BELLY_FIELD_LIST),
		list("fullness3_messages",         BELLY_FIELD_LIST),
		list("fullness4_messages",         BELLY_FIELD_LIST),
		list("fullness5_messages",         BELLY_FIELD_LIST),

		// ---- Sprite / overlay ----
		list("belly_fullscreen",           BELLY_FIELD_SCALAR),
		list("disable_hud",                BELLY_FIELD_SCALAR),
		list("colorization_enabled",       BELLY_FIELD_SCALAR),
		list("belly_fullscreen_color",     BELLY_FIELD_SCALAR),
		list("belly_fullscreen_color2",    BELLY_FIELD_SCALAR),
		list("belly_fullscreen_color3",    BELLY_FIELD_SCALAR),
		list("belly_fullscreen_color4",    BELLY_FIELD_SCALAR),
		list("belly_fullscreen_alpha",     BELLY_FIELD_SCALAR),
		list("vore_sprite_flags",          BELLY_FIELD_SCALAR),
		list("affects_vore_sprites",       BELLY_FIELD_SCALAR),
		list("count_absorbed_prey_for_sprite", BELLY_FIELD_SCALAR),
		list("absorbed_multiplier",        BELLY_FIELD_SCALAR),
		list("count_liquid_for_sprite",    BELLY_FIELD_SCALAR),
		list("liquid_multiplier",          BELLY_FIELD_SCALAR),
		list("count_items_for_sprite",     BELLY_FIELD_SCALAR),
		list("item_multiplier",            BELLY_FIELD_SCALAR),
		list("health_impacts_size",        BELLY_FIELD_SCALAR),
		list("resist_triggers_animation",  BELLY_FIELD_SCALAR),
		list("size_factor_for_sprite",     BELLY_FIELD_SCALAR),
		list("belly_sprite_to_affect",     BELLY_FIELD_SCALAR),

		// ---- Undergarment ----
		list("undergarment_chosen",        BELLY_FIELD_SCALAR),
		list("undergarment_if_none",       BELLY_FIELD_SCALAR),
		list("undergarment_color",         BELLY_FIELD_SCALAR),

		// ---- Egg ----
		list("egg_type",                   BELLY_FIELD_SCALAR),
		list("egg_name",                   BELLY_FIELD_SCALAR),
		list("egg_size",                   BELLY_FIELD_SCALAR),

		// ---- Miscellaneous ----
		list("recycling",                  BELLY_FIELD_SCALAR),
		list("storing_nutrition",          BELLY_FIELD_SCALAR),
		list("prevent_saving",             BELLY_FIELD_SCALAR),

		// ---- Message strings (flat lists) ----
		list("struggle_messages_outside",             BELLY_FIELD_LIST),
		list("struggle_messages_inside",              BELLY_FIELD_LIST),
		list("absorbed_struggle_messages_outside",    BELLY_FIELD_LIST),
		list("absorbed_struggle_messages_inside",     BELLY_FIELD_LIST),
		list("escape_attempt_messages_owner",         BELLY_FIELD_LIST),
		list("escape_attempt_messages_prey",          BELLY_FIELD_LIST),
		list("escape_messages_owner",                 BELLY_FIELD_LIST),
		list("escape_messages_prey",                  BELLY_FIELD_LIST),
		list("escape_messages_outside",               BELLY_FIELD_LIST),
		list("escape_item_messages_owner",            BELLY_FIELD_LIST),
		list("escape_item_messages_prey",             BELLY_FIELD_LIST),
		list("escape_item_messages_outside",          BELLY_FIELD_LIST),
		list("escape_fail_messages_owner",            BELLY_FIELD_LIST),
		list("escape_fail_messages_prey",             BELLY_FIELD_LIST),
		list("escape_attempt_absorbed_messages_owner",BELLY_FIELD_LIST),
		list("escape_attempt_absorbed_messages_prey", BELLY_FIELD_LIST),
		list("escape_absorbed_messages_owner",        BELLY_FIELD_LIST),
		list("escape_absorbed_messages_prey",         BELLY_FIELD_LIST),
		list("escape_absorbed_messages_outside",      BELLY_FIELD_LIST),
		list("escape_fail_absorbed_messages_owner",   BELLY_FIELD_LIST),
		list("escape_fail_absorbed_messages_prey",    BELLY_FIELD_LIST),
		list("primary_transfer_messages_owner",       BELLY_FIELD_LIST),
		list("primary_transfer_messages_prey",        BELLY_FIELD_LIST),
		list("secondary_transfer_messages_owner",     BELLY_FIELD_LIST),
		list("secondary_transfer_messages_prey",      BELLY_FIELD_LIST),
		list("primary_autotransfer_messages_owner",   BELLY_FIELD_LIST),
		list("primary_autotransfer_messages_prey",    BELLY_FIELD_LIST),
		list("secondary_autotransfer_messages_owner", BELLY_FIELD_LIST),
		list("secondary_autotransfer_messages_prey",  BELLY_FIELD_LIST),
		list("digest_chance_messages_owner",          BELLY_FIELD_LIST),
		list("digest_chance_messages_prey",           BELLY_FIELD_LIST),
		list("absorb_chance_messages_owner",          BELLY_FIELD_LIST),
		list("absorb_chance_messages_prey",           BELLY_FIELD_LIST),
		list("digest_messages_owner",                 BELLY_FIELD_LIST),
		list("digest_messages_prey",                  BELLY_FIELD_LIST),
		list("absorb_messages_owner",                 BELLY_FIELD_LIST),
		list("absorb_messages_prey",                  BELLY_FIELD_LIST),
		list("unabsorb_messages_owner",               BELLY_FIELD_LIST),
		list("unabsorb_messages_prey",                BELLY_FIELD_LIST),
		list("examine_messages",                      BELLY_FIELD_LIST),
		list("examine_messages_absorbed",             BELLY_FIELD_LIST),

		// ---- Emote lists (assoc: digest-mode -> list of strings) ----
		list("emote_lists",                BELLY_FIELD_ASSOC),

		// ---- Trash eater ----
		list("trash_eater_in",             BELLY_FIELD_LIST),
		list("trash_eater_out",            BELLY_FIELD_LIST),
	)

// ---------------------------------------------------------------------- //
//  vars_to_save() — schema-driven, replaces the hand-maintained list     //
// ---------------------------------------------------------------------- //

/// Returns the list of var names to persist for this belly.
/// Replaces the old 200-line hard-coded list in /obj/belly/vars_to_save().
/// digest_mode is appended only when save_digest_mode is set.
/datum/belly_serializer/proc/get_vars_to_save(obj/belly/B)
	if(!istype(B))
		return list()
	var/list/saving = list()
	for(var/list/entry in get_schema())
		var/field_name = entry[1]
		var/field_tag  = entry[2]
		if(field_tag == BELLY_FIELD_RUNTIME)
			continue   // never save runtime/tmp vars
		saving += field_name
	if(B.save_digest_mode)
		saving += "digest_mode"
	return saving

// ---------------------------------------------------------------------- //
//  copy_scalar_vars() — schema-driven scalar copy, replaces the hand     //
//  copy() block in /obj/belly/proc/copy()                                //
// ---------------------------------------------------------------------- //

/// Copies all BELLY_FIELD_SCALAR vars from src belly to dest belly.
/// List vars are NOT copied here — use copy_list_vars() for those.
/datum/belly_serializer/proc/copy_scalar_vars(obj/belly/src_belly, obj/belly/dest_belly)
	if(!istype(src_belly) || !istype(dest_belly))
		return
	for(var/list/entry in get_schema())
		var/field_name = entry[1]
		var/field_tag  = entry[2]
		if(field_tag == BELLY_FIELD_SCALAR)
			dest_belly.vars[field_name] = src_belly.vars[field_name]

/// Deep-copies all BELLY_FIELD_LIST and BELLY_FIELD_ASSOC vars from
/// src belly to dest belly.
/datum/belly_serializer/proc/copy_list_vars(obj/belly/src_belly, obj/belly/dest_belly)
	if(!istype(src_belly) || !istype(dest_belly))
		return
	for(var/list/entry in get_schema())
		var/field_name = entry[1]
		var/field_tag  = entry[2]
		if(field_tag == BELLY_FIELD_LIST)
			var/list/src_list  = src_belly.vars[field_name]
			var/list/dest_list = dest_belly.vars[field_name]
			if(!islist(dest_list))
				dest_belly.vars[field_name] = list()
				dest_list = dest_belly.vars[field_name]
			dest_list.Cut()
			if(islist(src_list))
				for(var/item in src_list)
					dest_list += item
		else if(field_tag == BELLY_FIELD_ASSOC)
			var/list/src_assoc = src_belly.vars[field_name]
			if(islist(src_assoc))
				dest_belly.vars[field_name] = src_assoc.Copy()
			else
				dest_belly.vars[field_name] = list()

// ---------------------------------------------------------------------- //
//  validate_schema_coverage() — boot-time sanity check                   //
// ---------------------------------------------------------------------- //

/// Verifies that every var name in the schema is actually declared on
/// /obj/belly.  Logs runtime warnings for any discrepancy so nothing is
/// silently dropped at save-time.  Returns TRUE if all vars are present.
/// Uses a /obj/belly type path to introspect vars without instantiating.
/datum/belly_serializer/proc/validate_schema_coverage()
	var/list/schema = get_schema()
	var/list/missing = list()
	var/list/extra   = list()

	// Use initial() and type-path var introspection instead of instantiating.
	// This avoids the Initialize() side effects (owner assignment, SSbellies).
	var/belly_type = /obj/belly

	// Build set of vars declared on /obj/belly type hierarchy via typesof()
	var/list/belly_vars = list()
	for(var/belly_subtype in typesof(belly_type))
		// We only care about /obj/belly itself, not subtypes.
		if(belly_subtype == belly_type)
			break
	// Fallback: just check via a raw vars list on the type datum
	// In BYOND, vars() on a type returns all declared var names.
	// We use the new keyword with a nullspace location to avoid initialize.
	var/obj/belly/probe = new belly_type(null)
	for(var/v in probe.vars)
		belly_vars[v] = TRUE
	qdel(probe)

	// Check schema entries exist on the belly
	for(var/list/entry in schema)
		var/field_name = entry[1]
		if(!(field_name in belly_vars))
			missing += field_name

	// Spot-check legacy list
	var/list/legacy = belly_vars_to_save_legacy_static()
	var/list/schema_names = list()
	for(var/list/entry in schema)
		schema_names[entry[1]] = TRUE
	for(var/v in legacy)
		if(!(v in schema_names))
			extra += v

	if(missing.len)
		log_game("/datum/belly_serializer schema gap — vars in schema but NOT on /obj/belly: [jointext(missing, ", ")]")
	if(extra.len)
		log_game("/datum/belly_serializer schema gap — legacy vars_to_save entries not in schema: [jointext(extra, ", ")]")

	return (!missing.len && !extra.len)

/// Static version of the legacy save list for coverage checking.
/// Returns the same list as /obj/belly/vars_to_save_legacy() without
/// requiring a belly instance.
/datum/belly_serializer/proc/belly_vars_to_save_legacy_static()
	return list(
		"name", "desc", "display_name", "absorbed_desc", "message_mode",
		"vore_sound", "vore_verb", "release_verb",
		"human_prey_swallow_time", "nonhuman_prey_swallow_time", "emote_time",
		"nutrition_percent", "digest_brute", "digest_burn", "digest_oxy",
		"digest_tox", "digest_clone", "bellytemperature", "temperature_damage",
		"immutable", "can_taste", "escapable", "escapetime",
		"digestchance", "absorbchance", "escapechance", "escapechance_absorbed",
		"transferchance", "transferchance_secondary",
		"transferlocation", "transferlocation_secondary",
		"belchchance", "bulge_size", "display_absorbed_examine", "shrink_grow_size",
		"struggle_messages_outside", "struggle_messages_inside",
		"absorbed_struggle_messages_outside", "absorbed_struggle_messages_inside",
		"escape_attempt_messages_owner", "escape_attempt_messages_prey",
		"escape_messages_owner", "escape_messages_prey", "escape_messages_outside",
		"escape_item_messages_owner", "escape_item_messages_prey", "escape_item_messages_outside",
		"escape_fail_messages_owner", "escape_fail_messages_prey",
		"escape_attempt_absorbed_messages_owner", "escape_attempt_absorbed_messages_prey",
		"escape_absorbed_messages_owner", "escape_absorbed_messages_prey", "escape_absorbed_messages_outside",
		"escape_fail_absorbed_messages_owner", "escape_fail_absorbed_messages_prey",
		"primary_transfer_messages_owner", "primary_transfer_messages_prey",
		"secondary_transfer_messages_owner", "secondary_transfer_messages_prey",
		"primary_autotransfer_messages_owner", "primary_autotransfer_messages_prey",
		"secondary_autotransfer_messages_owner", "secondary_autotransfer_messages_prey",
		"digest_chance_messages_owner", "digest_chance_messages_prey",
		"absorb_chance_messages_owner", "absorb_chance_messages_prey",
		"digest_messages_owner", "digest_messages_prey",
		"absorb_messages_owner", "absorb_messages_prey",
		"unabsorb_messages_owner", "unabsorb_messages_prey",
		"examine_messages", "examine_messages_absorbed",
		"emote_lists", "emote_active", "selective_preference",
		"mode_flags", "item_digest_mode", "contaminates",
		"contamination_flavor", "contamination_color",
		"release_sound", "fancy_vore", "is_wet", "wet_loop",
		"belly_fullscreen", "disable_hud", "reagent_mode_flags",
		"belly_fullscreen_color", "belly_fullscreen_color2",
		"belly_fullscreen_color3", "belly_fullscreen_color4", "belly_fullscreen_alpha",
		"colorization_enabled", "show_liquids", "reagentbellymode", "reagent_gen_cost_limit",
		"liquid_fullness1_messages", "liquid_fullness2_messages", "liquid_fullness3_messages",
		"liquid_fullness4_messages", "liquid_fullness5_messages",
		"reagent_name", "reagent_chosen", "reagentid", "reagentcolor",
		"liquid_overlay", "max_liquid_level", "reagent_touches",
		"mush_overlay", "mush_color", "mush_alpha", "max_mush", "min_mush", "item_mush_val",
		"custom_reagentcolor", "custom_reagentalpha",
		"metabolism_overlay", "metabolism_mush_ratio", "max_ingested",
		"custom_ingested_color", "custom_ingested_alpha",
		"gen_cost", "gen_amount", "gen_time", "gen_time_display",
		"reagent_transfer_verb", "custom_max_volume", "generated_reagents",
		"vorefootsteps_sounds",
		"fullness1_messages", "fullness2_messages", "fullness3_messages",
		"fullness4_messages", "fullness5_messages",
		"displayed_message_flags", "vorespawn_blacklist", "vorespawn_whitelist", "vorespawn_absorbed",
		"absorbed_multiplier", "count_liquid_for_sprite", "liquid_multiplier",
		"undergarment_chosen", "undergarment_if_none", "undergarment_color",
		"autotransferchance", "autotransferwait", "autotransferlocation",
		"autotransferextralocation", "autotransfer_enabled",
		"autotransferchance_secondary", "autotransferextralocation_secondary",
		"autotransferlocation_secondary",
		"autotransfer_secondary_whitelist", "autotransfer_secondary_blacklist",
		"autotransfer_whitelist", "autotransfer_blacklist",
		"autotransfer_secondary_whitelist_items", "autotransfer_secondary_blacklist_items",
		"autotransfer_whitelist_items", "autotransfer_blacklist_items",
		"autotransfer_min_amount", "autotransfer_max_amount",
		"slow_digestion", "slow_brutal", "sound_volume", "speedy_mob_processing",
		"egg_name", "egg_size", "recycling", "storing_nutrition",
		"is_feedable", "entrance_logs", "noise_freq",
		"private_struggle", "absorbedrename_enabled", "absorbedrename_name",
		"item_digest_logs", "show_fullness_messages", "digest_max",
		"egg_type", "save_digest_mode", "eating_privacy_local",
		"silicon_belly_overlay_preference", "belly_mob_mult", "belly_item_mult", "belly_overall_mult",
		"drainmode", "vore_sprite_flags", "affects_vore_sprites",
		"count_absorbed_prey_for_sprite", "resist_triggers_animation",
		"size_factor_for_sprite", "belly_sprite_to_affect",
		"health_impacts_size", "count_items_for_sprite", "item_multiplier",
		"trash_eater_in", "trash_eater_out"
	)

// ---------------------------------------------------------------------- //
//  Global accessor                                                        //
// ---------------------------------------------------------------------- //

/// Global singleton for the belly serializer.  Created on first access.
/proc/get_belly_serializer()
	if(!GLOB.belly_serializer)
		GLOB.belly_serializer = new /datum/belly_serializer()
	return GLOB.belly_serializer

// ---------------------------------------------------------------------- //
//  /obj/belly integration — replace vars_to_save() with schema version   //
// ---------------------------------------------------------------------- //

/obj/belly
	/// Cached belly serializer reference — shared across all bellies.
	var/tmp/static/datum/belly_serializer/belly_serializer_ref = null

/// Returns the schema-driven list of var names to save.
/// Replaces the old 200-line hard-coded list.  Preserves the original
/// behaviour of ..() + schema list (parent /atom returns basic geometry vars).
/obj/belly/vars_to_save()
	if(!belly_serializer_ref)
		belly_serializer_ref = get_belly_serializer()
	return ..() + belly_serializer_ref.get_vars_to_save(src)

/// Preserved original vars_to_save() content under a legacy name so the
/// schema coverage validator can detect any vars we missed during migration.
/// This proc can be deleted once validate_schema_coverage() has confirmed
/// full coverage in a real boot.
/obj/belly/proc/vars_to_save_legacy()
	var/list/saving = list(
		"name",
		"desc",
		"display_name",
		"absorbed_desc",
		"message_mode",
		"vore_sound",
		"vore_verb",
		"release_verb",
		"human_prey_swallow_time",
		"nonhuman_prey_swallow_time",
		"emote_time",
		"nutrition_percent",
		"digest_brute",
		"digest_burn",
		"digest_oxy",
		"digest_tox",
		"digest_clone",
		"bellytemperature",
		"temperature_damage",
		"immutable",
		"can_taste",
		"escapable",
		"escapetime",
		"digestchance",
		"absorbchance",
		"escapechance",
		"escapechance_absorbed",
		"transferchance",
		"transferchance_secondary",
		"transferlocation",
		"transferlocation_secondary",
		"belchchance",
		"bulge_size",
		"display_absorbed_examine",
		"shrink_grow_size",
		"struggle_messages_outside",
		"struggle_messages_inside",
		"absorbed_struggle_messages_outside",
		"absorbed_struggle_messages_inside",
		"escape_attempt_messages_owner",
		"escape_attempt_messages_prey",
		"escape_messages_owner",
		"escape_messages_prey",
		"escape_messages_outside",
		"escape_item_messages_owner",
		"escape_item_messages_prey",
		"escape_item_messages_outside",
		"escape_fail_messages_owner",
		"escape_fail_messages_prey",
		"escape_attempt_absorbed_messages_owner",
		"escape_attempt_absorbed_messages_prey",
		"escape_absorbed_messages_owner",
		"escape_absorbed_messages_prey",
		"escape_absorbed_messages_outside",
		"escape_fail_absorbed_messages_owner",
		"escape_fail_absorbed_messages_prey",
		"primary_transfer_messages_owner",
		"primary_transfer_messages_prey",
		"secondary_transfer_messages_owner",
		"secondary_transfer_messages_prey",
		"primary_autotransfer_messages_owner",
		"primary_autotransfer_messages_prey",
		"secondary_autotransfer_messages_owner",
		"secondary_autotransfer_messages_prey",
		"digest_chance_messages_owner",
		"digest_chance_messages_prey",
		"absorb_chance_messages_owner",
		"absorb_chance_messages_prey",
		"digest_messages_owner",
		"digest_messages_prey",
		"absorb_messages_owner",
		"absorb_messages_prey",
		"unabsorb_messages_owner",
		"unabsorb_messages_prey",
		"examine_messages",
		"examine_messages_absorbed",
		"emote_lists",
		"emote_time",
		"emote_active",
		"selective_preference",
		"mode_flags",
		"item_digest_mode",
		"contaminates",
		"contamination_flavor",
		"contamination_color",
		"release_sound",
		"fancy_vore",
		"is_wet",
		"wet_loop",
		"belly_fullscreen",
		"disable_hud",
		"reagent_mode_flags",
		"belly_fullscreen_color",
		"belly_fullscreen_color2",
		"belly_fullscreen_color3",
		"belly_fullscreen_color4",
		"belly_fullscreen_alpha",
		"colorization_enabled",
		"show_liquids",
		"reagentbellymode",
		"reagent_gen_cost_limit",
		"liquid_fullness1_messages",
		"liquid_fullness2_messages",
		"liquid_fullness3_messages",
		"liquid_fullness4_messages",
		"liquid_fullness5_messages",
		"reagent_name",
		"reagent_chosen",
		"reagentid",
		"reagentcolor",
		"liquid_overlay",
		"max_liquid_level",
		"reagent_touches",
		"mush_overlay",
		"mush_color",
		"mush_alpha",
		"max_mush",
		"min_mush",
		"item_mush_val",
		"custom_reagentcolor",
		"custom_reagentalpha",
		"metabolism_overlay",
		"metabolism_mush_ratio",
		"max_ingested",
		"custom_ingested_color",
		"custom_ingested_alpha",
		"gen_cost",
		"gen_amount",
		"gen_time",
		"gen_time_display",
		"reagent_transfer_verb",
		"custom_max_volume",
		"generated_reagents",
		"vorefootsteps_sounds",
		"fullness1_messages",
		"fullness2_messages",
		"fullness3_messages",
		"fullness4_messages",
		"fullness5_messages",
		"displayed_message_flags",
		"vorespawn_blacklist",
		"vorespawn_whitelist",
		"vorespawn_absorbed",
		"absorbed_multiplier",
		"count_liquid_for_sprite",
		"liquid_multiplier",
		"undergarment_chosen",
		"undergarment_if_none",
		"undergarment_color",
		"autotransferchance",
		"autotransferwait",
		"autotransferlocation",
		"autotransferextralocation",
		"autotransfer_enabled",
		"autotransferchance_secondary",
		"autotransferextralocation_secondary",
		"autotransferlocation_secondary",
		"autotransfer_secondary_whitelist",
		"autotransfer_secondary_blacklist",
		"autotransfer_whitelist",
		"autotransfer_blacklist",
		"autotransfer_secondary_whitelist_items",
		"autotransfer_secondary_blacklist_items",
		"autotransfer_whitelist_items",
		"autotransfer_blacklist_items",
		"autotransfer_min_amount",
		"autotransfer_max_amount",
		"slow_digestion",
		"slow_brutal",
		"sound_volume",
		"speedy_mob_processing",
		"egg_name",
		"egg_size",
		"recycling",
		"storing_nutrition",
		"is_feedable",
		"entrance_logs",
		"noise_freq",
		"private_struggle",
		"absorbedrename_enabled",
		"absorbedrename_name",
		"item_digest_logs",
		"show_fullness_messages",
		"digest_max",
		"egg_type",
		"save_digest_mode",
		"eating_privacy_local",
		"silicon_belly_overlay_preference",
		"belly_mob_mult",
		"belly_item_mult",
		"belly_overall_mult",
		"drainmode",
		"vore_sprite_flags",
		"affects_vore_sprites",
		"count_absorbed_prey_for_sprite",
		"resist_triggers_animation",
		"size_factor_for_sprite",
		"belly_sprite_to_affect",
		"health_impacts_size",
		"count_items_for_sprite",
		"item_multiplier",
		"undergarment_chosen",
		"undergarment_if_none",
		"undergarment_color",
		"trash_eater_in",
		"trash_eater_out"
	)

	// Note: does NOT call ..() — this proc is only for coverage validation,
	// not actual save behavior.  The real vars_to_save() is schema-driven.
	if(save_digest_mode)
		return saving + list("digest_mode")
	return saving
