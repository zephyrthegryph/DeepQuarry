GLOBAL_LIST_EMPTY_TYPED(loadout_categories, /datum/loadout_category)
GLOBAL_LIST_EMPTY_TYPED(gear_datums, /datum/gear)

/datum/loadout_category
	var/category = ""
	var/list/gear = list()

/datum/loadout_category/New(cat)
	category = cat
	..()

/hook/startup/proc/populate_gear_list()

	//create a list of gear datums to sort
	for(var/datum/gear/G as anything in subtypesof(/datum/gear))
		if(initial(G.type_category) == G)
			continue
		var/use_name = initial(G.display_name)
		var/use_category = initial(G.sort_category)

		if(!use_name)
			log_world("## ERROR Loadout - Missing display name: [G]")
			continue

		// Skip subtypes that merely INHERIT their parent's display_name instead of declaring
		// their own — these are abstract intermediate types (e.g. /datum/gear/uniform/dept,
		// which only sets whitelisted/sort_category for its named children) or unnamed leaves.
		// GLOB.gear_datums is keyed by display_name, so instantiating an inheritor overwrites
		// the real item that declared that name. That made "blazer, blue" resolve to the
		// Teshari-only /datum/gear/uniform/dept/undercoat on the write path while the catalog
		// still showed the real /datum/gear/uniform — so adding it was silently rejected for
		// non-Teshari players. Properly-named leaves (parent has a different name) are kept.
		var/datum/gear/parent_gear = G.parent_type
		if(parent_gear && initial(parent_gear.display_name) == use_name)
			continue
		if(isnull(initial(G.cost)))
			log_world("## ERROR Loadout - Missing cost: [G]")
			continue
		if(!initial(G.path))
			log_world("## ERROR Loadout - Missing path definition: [G]")
			continue

		if(!GLOB.loadout_categories[use_category])
			GLOB.loadout_categories[use_category] = new /datum/loadout_category(use_category)
		var/datum/loadout_category/LC = GLOB.loadout_categories[use_category]
		GLOB.gear_datums[use_name] = new G
		LC.gear[use_name] = GLOB.gear_datums[use_name]

	return 1

// /datum/category_item/player_setup_item/loadout/loadout (the Bay loadout tab)
// deleted. /datum/preference_editor/loadout owns the new UI.

/datum/gear
	var/display_name       //Name/index. Must be unique.
	var/description        //Description of this gear. If left blank will default to the description of the pathed item.
	var/path               //Path to item.
	var/variant // variant key for consolidated parent types
	var/cost = 1           //Number of points used. Items in general cost 1 point, storage/armor/gloves/special use costs 2 points.
	var/slot               //Slot to equip to.
	var/list/allowed_roles //Roles that can spawn with this item.
	var/show_roles = TRUE	//Show the role restrictions on this item?
	var/whitelisted        //Term to check the whitelist for..
	var/sort_category = "General"
	var/list/gear_tweaks = list() //List of datums which will alter the item after it has been spawned.
	var/exploitable = 0		//Does it go on the exploitable information list?
	var/type_category = null
	var/list/ckeywhitelist	//restricted based on these ckeys?
	var/list/character_name	//restricted to these character names?

// Entity-level pickability rule. The single source of truth for "can this
// player legitimately have this gear in their loadout?" Read at write time
// (loadout editor) and at spawn time (preferences_setup / SSjob.equip_rank); both
// places previously had drift-prone copies of this check.
//
// Static — reads only gear-declared fields plus a few prefs the gear-system cares about
// (species for whitelist, tail style for taur-only items). Override on specific gear
// datums when the rule needs more (e.g. ckey gating for admin items).
/datum/gear/proc/is_pickable_by(datum/preferences/prefs)
	if(!prefs)
		return TRUE

	// Species whitelist (gear-declared)
	if(whitelisted)
		var/pref_species = prefs.read_preference(/datum/preference/choiced/species)
		var/datum/species/spec = pref_species ? GLOB.all_species[pref_species] : null
		var/base_species = spec?.base_species
		if(pref_species && whitelisted != pref_species && whitelisted != base_species)
			return FALSE

	// Ckey allowlist (legacy hand-curated gear)
	if(ckeywhitelist && length(ckeywhitelist))
		if(!prefs.client || !(prefs.client.ckey in ckeywhitelist))
			return FALSE

	// Taur-half check for known taur-locked items. We can't put this on /datum/gear as
	// a declared field without restructuring every taur item, so it lives here as a
	// path-based static rule. Kept in lockstep with the loadout editor's previous helper.
	if(!_is_taur_gear_allowed(prefs))
		return FALSE

	return TRUE

/// Internal: returns FALSE only when `src` is a known taur-restricted item AND the
/// player's tail doesn't match. Returns TRUE for items with no taur restriction (the
/// common case). Mirrors the wolf/horse/drake gates the loadout panel was applying.
/datum/gear/proc/_is_taur_gear_allowed(datum/preferences/prefs)
	if(!path)
		return TRUE
	if(ispath(path, /obj/item/clothing/suit/armor/vest/wolftaur))
		var/tail = _resolve_player_tail(prefs)
		return istype(tail, /datum/sprite_accessory/tail/taur/wolf)
	if(ispath(path, /obj/item/clothing/suit/taur))
		var/tail = _resolve_player_tail(prefs)
		return istype(tail, /datum/sprite_accessory/tail/taur/wolf) || istype(tail, /datum/sprite_accessory/tail/taur/horse)
	if(ispath(path, /obj/item/clothing/suit/drake_cloak))
		var/tail = _resolve_player_tail(prefs)
		return istype(tail, /datum/sprite_accessory/tail/taur/drake)
	return TRUE

/datum/gear/proc/_resolve_player_tail(datum/preferences/prefs)
	var/tail_style = prefs.read_preference(/datum/preference/text/human/tail_style)
	if(tail_style && GLOB.tail_styles_list)
		return GLOB.tail_styles_list[tail_style]
	return null

/datum/gear/New()
	..()
	if(!description)
		var/obj/O = path
		description = initial(O.desc)
	// gear_tweak_free_matrix_recolor swapped for gear_tweak_unified_recolor,
	// which packs tint / palette-swap / matrix into one mode-selectable tweak (see
	// code/datums/gear/gear_tweak_recolor.dm).
	gear_tweaks = list(GLOB.gear_tweak_free_name, GLOB.gear_tweak_free_desc, GLOB.gear_tweak_item_tf_spawn, GLOB.gear_tweak_unified_recolor, GLOB.gear_tweak_free_digestable)

/datum/gear_data
	var/path
	var/location

/datum/gear_data/New(path, location)
	src.path = path
	src.location = location

/datum/gear/proc/spawn_item(location, metadata)
	var/datum/gear_data/gd = new(path, location)
	// propagate variant from gear to gear_data so tweaks can override it.
	gd.variant = variant
	// key metadata by 1-based gear_tweaks index instead of `"[gt]"` (the datum's
	// runtime text rep), so values persist across server restarts. The DQ loadout editor
	// also writes by index.
	if(length(gear_tweaks) && metadata)
		for(var/i in 1 to length(gear_tweaks))
			var/datum/gear_tweak/gt = gear_tweaks[i]
			gt.tweak_gear_data(metadata["[i]"], gd)
	// spawn via helper to apply variant.
	var/item = spawn_with_variant(gd.path, gd.location, gd.variant)
	if(length(gear_tweaks) && metadata)
		for(var/i in 1 to length(gear_tweaks))
			var/datum/gear_tweak/gt = gear_tweaks[i]
			gt.tweak_item(item, metadata["[i]"])
	var/mob/M = location
	if(istype(M) && exploitable) //Update exploitable info records for the mob without creating a duplicate object at their feet.
		M.amend_exploitable(item)
	return item
