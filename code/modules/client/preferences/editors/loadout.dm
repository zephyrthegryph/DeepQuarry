// Loadout / gear slot builder.
//
// Data model:
//   gear_list saves {loadout_slot_num_str: {gear_name: metadata}}. Multiple items can be
//   in one loadout slot, but the editor enforces one-per-body-slot (with SLOT_ID_TIE being
//   the multi-allowed exception). Items with no body slot land in an "other" bucket.
//
// Wire actions:
//   "switch_slot"      { slot: 1..N }                       — change active loadout slot
//   "toggle_gear"      { gear: "Display Name" }             — add/remove without slot logic
//   "set_body_slot"    { body_slot: int, gear: "Display" }  — replaces item in body slot
//   "clear_body_slot"  { body_slot: int }                   — empties one body slot
//   "clear_loadout"                                         — empties the whole loadout slot
//   "copy_to_slot"     { dest: 1..N }

#define DQ_LOADOUT_OTHER_SLOT "other"

/// Display label for a gear_tweak datum — what shows in the customize panel header.
/// Falls back to the type path's last component for any tweaks not enumerated here.
/proc/dq_gear_tweak_label(datum/gear_tweak/gt)
	if(istype(gt, /datum/gear_tweak/custom_name)) return "Custom Name"
	if(istype(gt, /datum/gear_tweak/custom_desc)) return "Custom Description"
	if(istype(gt, /datum/gear_tweak/color))       return "Color"
	if(istype(gt, /datum/gear_tweak/matrix_recolor)) return "Recolor"
	if(istype(gt, /datum/gear_tweak/path))        return "Variant"
	if(istype(gt, /datum/gear_tweak/toggle_digestable)) return "Digestable"
	if(istype(gt, /datum/gear_tweak/contents))    return "Contents"
	if(istype(gt, /datum/gear_tweak/reagents))    return "Reagents"
	if(istype(gt, /datum/gear_tweak/tablet))      return "Tablet Components"
	if(istype(gt, /datum/gear_tweak/laptop))      return "Laptop Components"
	if(istype(gt, /datum/gear_tweak/implant_location)) return "Implant Location"
	if(istype(gt, /datum/gear_tweak/collar_tag))  return "Collar Tag"
	if(istype(gt, /datum/gear_tweak/item_tf_spawn)) return "TF Spawn"
	if(istype(gt, /datum/gear_tweak/pda_ringtone)) return "Ringtone"
	// Fallback: stringify the type path's tail
	var/list/parts = splittext("[gt.type]", "/")
	return capitalize(parts[length(parts)])

/// Which React widget kind to render inline for the given tweak.
///   text / textarea / color / choice / boolean — full-width inline editors
///   tf_toggle — item_tf_spawn rendered as a binary toggle (Anyone ↔ Not Enabled).
///                The 3-state "Only Specific Players" option is dropped from the toggle;
///                users who want per-ckey gating can opt back into the modal flow later.
///   modal_button — renders as a compact bottom-row button that opens the legacy modal
///                  (currently just matrix_recolor — it has no good inline form).
///   modal — full-width legacy Change-button row (contents, tablet, laptop, etc.)
/proc/dq_gear_tweak_kind(datum/gear_tweak/gt)
	if(istype(gt, /datum/gear_tweak/custom_name))       return "text"
	if(istype(gt, /datum/gear_tweak/custom_desc))       return "textarea"
	if(istype(gt, /datum/gear_tweak/color))             return "color"
	if(istype(gt, /datum/gear_tweak/path))              return "choice"
	if(istype(gt, /datum/gear_tweak/toggle_digestable)) return "boolean"
	if(istype(gt, /datum/gear_tweak/reagents))          return "choice"
	if(istype(gt, /datum/gear_tweak/implant_location))  return "choice"
	if(istype(gt, /datum/gear_tweak/collar_tag))        return "text"
	if(istype(gt, /datum/gear_tweak/item_tf_spawn))     return "tf_toggle"
	if(istype(gt, /datum/gear_tweak/recolor))           return "recolor"
	if(istype(gt, /datum/gear_tweak/pda_ringtone))      return "choice"
	if(istype(gt, /datum/gear_tweak/matrix_recolor))    return "modal_button"
	return "modal"

/// Kinds that should render side-by-side as compact buttons in a single bottom row
/// instead of taking a full-width slot. Mirrors the "bottom four buttons on a single
/// line" pattern from the original bay-prefs loadout panel.
/proc/dq_gear_tweak_compact(kind)
	return (kind in list("boolean", "tf_toggle", "modal_button"))

/// Whether changing this tweak's metadata changes the *visual* worn appearance — i.e.
/// whether a preview rebuild is warranted. Color/recolor/matrix change pixel data,
/// /path/ changes the underlying subtype's icon. Everything else (custom name/desc,
/// collar tag, reagents, ringtone, implant location, digestable flag, tf spawn) is
/// metadata-only and a rebuild would burn ~100 ms per keystroke for no visible effect.
/proc/dq_gear_tweak_affects_preview(datum/gear_tweak/gt)
	return istype(gt, /datum/gear_tweak/color) \
		|| istype(gt, /datum/gear_tweak/recolor) \
		|| istype(gt, /datum/gear_tweak/path) \
		|| istype(gt, /datum/gear_tweak/matrix_recolor)

/// For "choice" tweaks, returns the list of valid choice labels. For others, returns null.
/proc/dq_gear_tweak_choices(datum/gear_tweak/gt)
	return gt?.get_inline_choices()

/datum/preference_editor/loadout
	key = "loadout"
	category = "loadout"
	group = "gear"
	sort_order = 50
	display_name = "Gear Loadout"
	pref_keys = list("gear_list", "gear_slot")
	// gear catalog is filtered by species/custom_base (whitelist gating) and
	// tail_style (taur gear gating). Only these prefs require a rebuild.
	static_invalidator_keys = list("species", "custom_base", "tail_style")

/// Body slot display table. Keep in head-down order; `multi` controls whether the slot can
/// hold more than one item (only SLOT_ID_TIE should). SLOT_ID_LEGS is generally fluff layer.
/// `group` collapses related slots into one section in the UI for visual scanability.
TYPE_TABLE_DECLARE(/datum/preference_editor/loadout, body_slot_table, list( \
		list("id" = SLOT_ID_HEAD,       "label" = "Head",         "group" = "Face & Head"), \
		list("id" = SLOT_ID_EYES,    "label" = "Eyes",         "group" = "Face & Head"), \
		list("id" = SLOT_ID_MASK,  "label" = "Mask",         "group" = "Face & Head"), \
		list("id" = SLOT_ID_EAR_L,      "label" = "Left Ear",     "group" = "Face & Head"), \
		list("id" = SLOT_ID_EAR_R,      "label" = "Right Ear",    "group" = "Face & Head"), \
		list("id" = SLOT_ID_UNIFORM,  "label" = "Uniform",      "group" = "Clothing"), \
		list("id" = SLOT_ID_SUIT,  "label" = "Outer Suit",   "group" = "Clothing"), \
		list("id" = SLOT_ID_TIE,        "label" = "Accessories",  "group" = "Clothing", "multi" = TRUE), \
		list("id" = SLOT_ID_GLOVES,     "label" = "Gloves",       "group" = "Hands & Feet"), \
		list("id" = SLOT_ID_SHOES,      "label" = "Shoes",        "group" = "Hands & Feet"), \
		list("id" = SLOT_ID_BACK,       "label" = "Back",         "group" = "Carry"), \
		list("id" = SLOT_ID_BELT,       "label" = "Belt",         "group" = "Carry"), \
		list("id" = SLOT_ID_ID,    "label" = "ID",           "group" = "Carry"), \
		list("id" = SLOT_ID_POCKET_L,    "label" = "Left Pocket",  "group" = "Pockets"), \
		list("id" = SLOT_ID_POCKET_R,    "label" = "Right Pocket", "group" = "Pockets"), \
		list("id" = SLOT_ID_SUIT_STORAGE,    "label" = "Suit Storage", "group" = "Pockets"), \
		list("id" = SLOT_ID_LEGS,       "label" = "Legs Layer",   "group" = "Other"), \
	))

/// Returns the body-slot key (numeric string or "other") for the given /datum/gear.
/datum/preference_editor/loadout/proc/slot_key_for(datum/gear/G)
	if(!G.slot)
		return DQ_LOADOUT_OTHER_SLOT
	return "[G.slot]"

/// Maps /datum/decl/hierarchy/outfit field name -> body slot id key used by the UI.
/// Used to translate the chosen job's outfit into ghost-placeholder slot labels.
// / l_ear/r_ear/back removed: those slots are filled at runtime by pre_equip()
/// from the indirect vars (headset, backpack), not declared statically on the outfit.
/// Resolved separately below in job_default_labels so the ghost shows the job's actual
/// themed kit instead of being blank.
TYPE_TABLE_DECLARE(/datum/preference_editor/loadout, loadout_outfit_field_to_slot, list( \
	"uniform"    = "[SLOT_ID_UNIFORM]", \
	"suit"       = "[SLOT_ID_SUIT]", \
	"belt"       = "[SLOT_ID_BELT]", \
	"gloves"     = "[SLOT_ID_GLOVES]", \
	"shoes"      = "[SLOT_ID_SHOES]", \
	"head"       = "[SLOT_ID_HEAD]", \
	"mask"       = "[SLOT_ID_MASK]", \
	"glasses"    = "[SLOT_ID_EYES]", \
	"l_pocket"   = "[SLOT_ID_POCKET_L]", \
	"r_pocket"   = "[SLOT_ID_POCKET_R]", \
	"suit_store" = "[SLOT_ID_SUIT_STORAGE]", \
))

/// Returns {body_slot_str: item_name} for the given job's outfit, using initial(.name)
/// instead of instantiating items. The straight slot mappings (uniform/suit/belt/etc.)
/// come from the loadout_outfit_field_to_slot table; the indirect slots — l_ear, back, wear_id, the
/// per-job pda_slot — are filled at runtime by pre_equip() from outfit.headset /
/// outfit.backpack / outfit.id_type / outfit.pda_type, so resolve those explicitly here.
/// `backbag_choice` is vestigial (the backbag pref was deleted) — kept in signature for
/// callers; ignored.
/datum/preference_editor/loadout/proc/job_default_labels(datum/job/job, backbag_choice)
	var/list/out = list()
	if(!job || !job.outfit_type)
		return out
	var/datum/decl/hierarchy/outfit/outfit = outfit_by_type(job.outfit_type)
	if(!outfit)
		return out
	var/list/mapping = TYPE_TABLE_GET(src, loadout_outfit_field_to_slot)
	for(var/field in mapping)
		var/path = outfit.vars[field]
		if(!path || !ispath(path))
			continue
		var/atom/A = path
		out[mapping[field]] = initial(A.name) || "[field]"

	// Ear slot (l_ear): canonical headset variant — the loadout layer is what equips
	// generic headsets; the job's themed kit is the default the ghost should show.
	if(outfit.headset && ispath(outfit.headset))
		var/atom/H = outfit.headset
		out["[SLOT_ID_EAR_L]"] = initial(H.name)
	// Back slot: canonical backpack.
	if(outfit.backpack && ispath(outfit.backpack))
		var/atom/B = outfit.backpack
		out["[SLOT_ID_BACK]"] = initial(B.name)
	// ID slot: outfit.id_slot says where the ID lands; outfit.id_type is what.
	if(outfit.id_slot && outfit.id_type && ispath(outfit.id_type))
		var/atom/I = outfit.id_type
		out["[outfit.id_slot]"] = initial(I.name)
	// PDA slot: outfit.pda_slot is per-job (belt for command, l_store for others, etc.).
	// Only render if the slot doesn't already have something (the job's ID can co-locate
	// with the PDA on SLOT_ID_ID for some outfits — let the more important ID win).
	if(outfit.pda_slot && outfit.pda_type && ispath(outfit.pda_type) && !out["[outfit.pda_slot]"])
		var/atom/P = outfit.pda_type
		out["[outfit.pda_slot]"] = initial(P.name)

	// Uniform accessories (multi → tie slot)
	if(LAZYLEN(outfit.uniform_accessories))
		var/list/tie_names = list()
		for(var/path in outfit.uniform_accessories)
			if(ispath(path))
				var/atom/A = path
				tie_names += initial(A.name)
		if(length(tie_names))
			out["[SLOT_ID_TIE]"] = tie_names.Join(", ")
	return out

/datum/preference_editor/loadout/build_ui_data(datum/preferences/preferences)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/loadout_key = _current_slot(preferences)
	// Editing a per-job loadout: by_body_slot reflects ONLY the per-job items. Default
	// items show as ghost subtext on slot cells (alongside the job's themed defaults),
	// matching how new players see "Engineering Backpack" before picking anything. The
	// merged set comes in via inherited_items so the UI can list them as ghosts without
	// counting them as actively-equipped here.
	var/list/active_gear_list
	var/list/inherited_items = list()
	if(loadout_key == "_default")
		active_gear_list = islist(gear_list["_default"]) ? gear_list["_default"] : list()
	else
		active_gear_list = islist(gear_list[loadout_key]) ? gear_list[loadout_key] : list()
		// Default items are inherited *visually* (as ghosts) — they're applied at spawn
		// time via get_loadout_for_job's merge, but the editor doesn't pretend they're
		// part of this per-job loadout's picks.
		var/list/merge = preferences.get_merged_loadout(loadout_key)
		var/list/all_inherited = merge["inherited"] || list()
		for(var/name in all_inherited)
			inherited_items[name] = TRUE

	// Group active items by body slot + collect per-item tweak data so the React
	// customize panel can render inline widgets (text input / dropdown / color
	// picker / boolean) with current values, plus get_contents display strings as a
	// fallback for "modal"-kind tweaks. Also send icon refs per item so SlotCell can
	// render the actual item sprite instead of just the HUD slot icon.
	var/list/by_body_slot = list()
	var/list/tweak_values_by_item = list()   // display strings: {name: {idx: "Color: red"}}
	var/list/tweak_meta_by_item = list()     // raw values:      {name: {idx: "#ff0000"}}
	var/list/icon_data_by_item = list()      // {name: {icon: ref, icon_state: str}}
	var/total_cost = 0
	for(var/gear_name in active_gear_list)
		var/datum/gear/G = GLOB.gear_datums[gear_name]
		if(!G)
			continue
		total_cost += G.cost
		var/slot_key = slot_key_for(G)
		if(!by_body_slot[slot_key])
			by_body_slot[slot_key] = list()
		by_body_slot[slot_key] += gear_name
		// Item icon for slot cell rendering. initial() returns the path-level default;
		// for variant-using gear datums the visible icon at spawn may differ slightly,
		// but the slot preview here is just a hint, not the spawn render.
		if(G.path)
			var/atom/A = G.path
			var/the_icon = initial(A.icon)
			var/the_state = initial(A.icon_state)
			if(the_icon)
				icon_data_by_item[gear_name] = list(
					"icon" = "[REF(the_icon)]",
					"icon_state" = the_state,
				)
		var/list/item_meta = active_gear_list[gear_name]
		if(length(G.gear_tweaks))
			var/list/per_tweak_display = list()
			var/list/per_tweak_raw = list()
			for(var/i in 1 to length(G.gear_tweaks))
				var/datum/gear_tweak/gt = LAZYACCESS(G.gear_tweaks, i)
				var/meta_value = islist(item_meta) ? item_meta["[i]"] : null
				try
					per_tweak_display["[i]"] = gt.get_contents(meta_value)
				catch(var/exception/e)
					log_world("loadout build_ui_data get_contents THREW for gear=[gear_name] gt=[gt?.type] meta=[meta_value]: [e?.name] @ [e?.file]:[e?.line]")
					per_tweak_display["[i]"] = "(error)"
				// Raw value — scalar metadata flows directly to React for inline widgets.
				// For item_tf_spawn the metadata is a list ({state, valid}); derive a
				// boolean so the tf_toggle widget can show enabled/disabled at a glance.
				// For the unified recolor tweak the metadata is the {mode, value} dict;
				// pass it through whole so the React widget can render its mode tabs +
				// per-mode body without a separate fetch.
				if(istype(gt, /datum/gear_tweak/item_tf_spawn))
					per_tweak_raw["[i]"] = (islist(meta_value) && meta_value["state"] && meta_value["state"] != "Not Enabled") ? TRUE : FALSE
				else if(istype(gt, /datum/gear_tweak/recolor))
					per_tweak_raw["[i]"] = islist(meta_value) ? meta_value : list("mode" = "off")
				else if(!isnull(meta_value) && !islist(meta_value))
					per_tweak_raw["[i]"] = meta_value
			tweak_values_by_item[gear_name] = per_tweak_display
			tweak_meta_by_item[gear_name] = per_tweak_raw

	// Inherited items (from the player's Default loadout when editing a per-job one).
	// Grouped by body slot so SlotCell can render them as italic ghost subtext under
	// the slot label, the same way job-default labels work. Also emit icon refs so a
	// SlotCell with only an inherited item can still preview its sprite.
	var/list/inherited_by_body_slot = list()
	for(var/inh_name in inherited_items)
		var/datum/gear/inh_gear = GLOB.gear_datums[inh_name]
		if(!inh_gear)
			continue
		var/inh_slot_key = slot_key_for(inh_gear)
		if(!inherited_by_body_slot[inh_slot_key])
			inherited_by_body_slot[inh_slot_key] = list()
		inherited_by_body_slot[inh_slot_key] += inh_name
		if(inh_gear.path)
			var/atom/IA = inh_gear.path
			var/inh_icon = initial(IA.icon)
			var/inh_state = initial(IA.icon_state)
			if(inh_icon)
				icon_data_by_item[inh_name] = list(
					"icon" = "[REF(inh_icon)]",
					"icon_state" = inh_state,
				)

	// Per-job loadout summary. Each entry: {key, label, count, cost}. The picker
	// in the React side renders this so the player can see "I have 3 picks in my Captain
	// loadout, 0 in my Cook loadout, 4 in default" at a glance.
	var/list/loadouts = list(
		list(
			"key"   = "_default",
			"label" = "Default",
			"count" = LAZYLEN(gear_list["_default"]),
			"cost"  = _list_cost(gear_list["_default"]),
		)
	)
	var/list/priorities = preferences.read_preference(/datum/preference/job_priorities) || list()
	// Order priorities by level (high → med → low) then alphabetical so the picker is stable.
	for(var/level in list("high", "med", "low"))
		var/list/titles_at_level = list()
		for(var/title in priorities)
			if(priorities[title] == level)
				titles_at_level += title
		sortList(titles_at_level)
		for(var/title in titles_at_level)
			loadouts += list(list(
				"key"      = title,
				"label"    = title,
				"priority" = level,
				"count"    = LAZYLEN(gear_list[title]),
				"cost"     = _list_cost(gear_list[title]),
			))

	// Job-default ghost slots — based on the job whose loadout is currently being edited.
	// "_default" is generic; for it we fall back to top-priority-job (or Intern) so the
	// ghosts give the player some context even on the default loadout.
	var/datum/job/preview_job
	if(loadout_key == "_default")
		preview_job = preferences.get_highest_job() || SSjob.get_job(JOB_INTERN)
	else
		preview_job = SSjob.get_job(loadout_key) || preferences.get_highest_job() || SSjob.get_job(JOB_INTERN)
	// backbag pref deleted; ignore the param. Kept the second arg for now in
	// case anything else still references the proc with two args (slated to drop).
	var/list/job_defaults = job_default_labels(preview_job, null)

	// Pull dynamic data from the (hidden) starting-kit and underwear editors so the
	// loadout panel can show all of it in one place. The editors themselves don't render on
	// their own; their action dispatch still works because they're registered.
	var/list/sk_data = list()
	var/list/uw_data = list()
	var/datum/preference_editor/sk = GLOB.preference_editors_by_key["starting_kit"]
	if(sk)
		sk_data = sk.build_ui_data(preferences)
	var/datum/preference_editor/uw = GLOB.preference_editors_by_key["underwear"]
	if(uw)
		uw_data = uw.build_ui_data(preferences)

	// Flat list of every job title at any non-off priority — React uses this when
	// filtering the catalog for the "_default" loadout (which fronts every prioritized
	// job, so any item allowed for any of them is fair game).
	var/list/prioritized_jobs = list()
	for(var/title in priorities)
		prioritized_jobs += title

	// Which slot the player's preview-job parks its PDA in — varies per job (SLOT_ID_BELT
	// for command, SLOT_ID_POCKET_L for engineering/cargo, SLOT_ID_POCKET_R for science, etc.).
	// The React side uses this so the ringtone control surfaces inside the right slot's
	// catalog header (instead of floating somewhere disconnected).
	var/pda_slot = null
	if(preview_job?.outfit_type)
		var/datum/decl/hierarchy/outfit/_outfit = outfit_by_type(preview_job.outfit_type)
		if(_outfit?.pda_slot)
			pda_slot = "[_outfit.pda_slot]"

	return list(
		"loadout_key" = loadout_key,
		"loadouts" = loadouts,
		"prioritized_jobs" = prioritized_jobs,
		"pda_slot" = pda_slot,
		"by_body_slot" = by_body_slot,
		"inherited_by_body_slot" = inherited_by_body_slot,
		"tweak_values_by_item" = tweak_values_by_item,
		"tweak_meta_by_item" = tweak_meta_by_item,
		"icon_data_by_item" = icon_data_by_item,
		"inherited_items" = assoc_to_keys(inherited_items),
		"total_cost" = total_cost,
		"max_gear_cost" = MAX_GEAR_COST,
		"job_defaults" = job_defaults,
		"preview_job" = preview_job ? preview_job.title : null,
		"starting_kit" = sk_data,
		"underwear" = uw_data,
	)

/datum/preference_editor/loadout/build_ui_static_data(datum/preferences/preferences)
	// Catalog grouped by category, but every item carries its body slot so the React side
	// can filter by slot when the user clicks one of the body-slot rows. Items whose
	// `whitelisted` field doesn't match the player's current species are hidden — same
	// check that real-spawn does, applied at the picker so the player doesn't waste a
	// pick on an item that won't equip. Also filter taur-only items by the player's
	// current tail style (Wolf-taur items hidden if the player's tail isn't a wolf-taur,
	// etc.) — same logic the per-item /mob_can_equip checks enforce at spawn.
	//
	// Species/taur gates are now centralized on /datum/gear/proc/is_pickable_by, which
	// reads the current prefs directly — no need to pre-resolve species/tail here.
	//
	// role filtering moved to React (LoadoutBuilder.tsx) so it can re-filter
	// instantly when the player switches the editing target between "_default" and a
	// specific job loadout. Static data ships every item that passes the species/taur
	// gates; the React side filters by allowed_roles against the current loadout_key.

	var/list/categories = list()
	for(var/category, value in GLOB.loadout_categories)
		var/datum/loadout_category/LC = value
		var/list/items = list()
		for(var/gear in LC.gear)
			var/datum/gear/G = LC.gear[gear]
			// Single source of truth for catalog visibility — same rule the write path
			// uses on toggle_gear / set_body_slot. See /datum/gear.is_pickable_by.
			if(!G.is_pickable_by(preferences))
				continue
			// Enumerate gear_tweaks so React can render a customize panel per item.
			// Each descriptor carries: stable index key, display label, widget kind
			// (text/textarea/color/choice/boolean/modal), and optional choices for "choice".
			var/list/tweak_descriptors = list()
			for(var/i in 1 to length(G.gear_tweaks))
				var/datum/gear_tweak/gt = LAZYACCESS(G.gear_tweaks, i)
				if(!istype(gt))
					log_world("loadout build_ui_static_data: gear=[G.display_name] has bad tweak at idx=[i]: [gt]")
					continue
				var/_kind = dq_gear_tweak_kind(gt)
				var/list/desc = list(
					"key"     = "[i]",
					"label"   = dq_gear_tweak_label(gt),
					"kind"    = _kind,
					"compact" = dq_gear_tweak_compact(_kind) ? TRUE : FALSE,
				)
				var/list/choices = dq_gear_tweak_choices(gt)
				if(choices)
					desc["choices"] = choices
				// Recolor tweak: send the gear's source-icon palette so the React widget
				// can render palette-swap swatches. Cached per gear-type so the scan only
				// runs once per session per type.
				if(_kind == "recolor")
					desc["palette"] = dq_get_gear_palette(G)
				tweak_descriptors += list(desc)
			items += list(list(
				"name" = G.display_name,
				"desc" = G.description,
				"cost" = G.cost,
				"allowed_roles" = G.allowed_roles,
				"show_roles" = G.show_roles ? TRUE : FALSE,
				"body_slot" = slot_key_for(G),
				"whitelisted" = G.whitelisted,
				"tweaks" = tweak_descriptors,
			))
		if(items.len)
			categories[category] = items

	// embed starting-kit and underwear static payloads so the loadout React side
	// can render those controls inline. The standalone editors are marked hidden=TRUE so
	// they don't render their own panels.
	var/list/sk_static = list()
	var/list/uw_static = list()
	var/datum/preference_editor/sk = GLOB.preference_editors_by_key["starting_kit"]
	if(sk)
		sk_static = sk.build_ui_static_data(preferences)
	var/datum/preference_editor/uw = GLOB.preference_editors_by_key["underwear"]
	if(uw)
		uw_static = uw.build_ui_static_data(preferences)

	return list(
		"categories" = categories,
		"body_slots" = TYPE_TABLE_GET(src, body_slot_table),
		"starting_kit" = sk_static,
		"underwear" = uw_static,
	)

/// Returns FALSE when `G` is a known taur-restricted item and the player's tail doesn't match.
/// Taur-half check moved to /datum/gear._is_taur_gear_allowed (entity-level rule).
/// This wrapper kept temporarily for any out-of-tree callers; new code should call
/// G._is_taur_gear_allowed(preferences) or, preferably, G.is_pickable_by(preferences).
/datum/preference_editor/loadout/proc/taur_item_allowed(datum/gear/G, datum/sprite_accessory/tail/player_tail)
	if(!G || !G.path)
		return TRUE
	if(ispath(G.path, /obj/item/clothing/suit/armor/vest/wolftaur))
		return istype(player_tail, /datum/sprite_accessory/tail/taur/wolf)
	if(ispath(G.path, /obj/item/clothing/suit/taur))
		return istype(player_tail, /datum/sprite_accessory/tail/taur/wolf) || istype(player_tail, /datum/sprite_accessory/tail/taur/horse)
	if(ispath(G.path, /obj/item/clothing/suit/drake_cloak))
		return istype(player_tail, /datum/sprite_accessory/tail/taur/drake)
	return TRUE

/// Server-side enforcement that defers to the gear datum's own pickability rule. The
/// rule lives on /datum/gear (is_pickable_by); this thin wrapper exists only because
/// "permitted to write into this loadout slot" historically lived on the editor. New
/// code should call G.is_pickable_by(preferences) directly.
/datum/preference_editor/loadout/proc/_gear_permitted_for(datum/gear/G, datum/preferences/preferences)
	return G?.is_pickable_by(preferences)

/// Returns the loadout key currently being edited ("_default" or a job title).
///
/// PURE — does not write. `build_ui_data` invokes this every UI tick, and an action
/// handler may call it many times per dispatch; a hidden write inside this proc would
/// race against the action's own preview rebuild and pile disk flushes onto every poll.
/// Stale-slot rewrite happens at action dispatch (see _validate_and_persist_slot below),
/// not here.
/datum/preference_editor/loadout/proc/_current_slot(datum/preferences/preferences)
	var/key = preferences.read_preference(/datum/preference/text/human/gear_slot)
	if(!istext(key) || !length(key))
		return "_default"
	if(key == "_default")
		return key
	// If the job dropped off the priority list since the slot was last saved, we still
	// return "_default" here so reads land on a defined loadout; the savefile rewrite
	// happens lazily on the next mutating action.
	var/list/priorities = preferences.read_preference(/datum/preference/job_priorities) || list()
	if(!(key in priorities))
		return "_default"
	return key

/// Called from action handlers (set_loadout_key, toggle_gear, set_body_slot, ...) to
/// migrate a stale saved key to "_default" exactly once, as part of the action's own
/// write batch. Separating read (`_current_slot`) from write (here) keeps build_ui_data
/// pure and lets stale-slot recovery share the action's save flush.
/datum/preference_editor/loadout/proc/_validate_and_persist_slot(datum/preferences/preferences)
	var/key = preferences.read_preference(/datum/preference/text/human/gear_slot)
	if(!istext(key) || !length(key) || key == "_default")
		return
	var/list/priorities = preferences.read_preference(/datum/preference/job_priorities) || list()
	if(!(key in priorities))
		preferences.update_preference_by_type(/datum/preference/text/human/gear_slot, "_default")

/datum/preference_editor/loadout/proc/_active_list(datum/preferences/preferences, loadout_key)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key]
	if(!active)
		active = list()
		gear_list[loadout_key] = active
		preferences.update_preference_by_type(/datum/preference/gear_list, gear_list)
	return active

/datum/preference_editor/loadout/proc/_save_active(datum/preferences/preferences, loadout_key, list/active)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	gear_list[loadout_key] = active
	preferences.update_preference_by_type(/datum/preference/gear_list, gear_list)

/// Allowed values for the gear_slot pref: "_default" plus any title in the player's
/// job_priorities map. Rejecting unknown keys keeps drift out of the savefile shape.
/datum/preference_editor/loadout/proc/_valid_loadout_key(datum/preferences/preferences, loadout_key)
	if(loadout_key == "_default")
		return TRUE
	var/list/priorities = preferences.read_preference(/datum/preference/job_priorities)
	return islist(priorities) && (loadout_key in priorities)

/// Sum the cost of an active list (helper). Skips unknown gear.
/datum/preference_editor/loadout/proc/_list_cost(list/active)
	var/cost = 0
	for(var/name in active)
		var/datum/gear/existing = GLOB.gear_datums[name]
		if(existing)
			cost += existing.cost
	return cost

/// A loadout gear tweak change: which prefs, gear, tweak and loadout slot it is for.
/datum/om/flow/ask_sequence/gear_tweak/loadout
	var/datum/preferences/preferences
	var/gear_name
	var/tweak_idx
	var/loadout_key

/datum/om/flow/ask_sequence/gear_tweak/loadout/New(datum/preferences/preferences, gear_name, tweak_idx, loadout_key)
	..()
	rel_set(src, nameof(preferences), preferences)
	src.gear_name = gear_name
	src.tweak_idx = tweak_idx
	src.loadout_key = loadout_key

/// A gear tweak's new value: the item must still be equipped in the same loadout.
/datum/preference_editor/loadout/proc/tweak_answered(mob/user, new_value, datum/om/flow/ask_sequence/gear_tweak/loadout/seq)
	var/datum/preferences/preferences = seq.preferences
	var/gear_name = seq.gear_name
	var/tweak_idx = seq.tweak_idx
	var/loadout_key = seq.loadout_key
	var/datum/gear/G = GLOB.gear_datums[gear_name]
	if(!preferences || !G || tweak_idx > length(G.gear_tweaks) || _current_slot(preferences) != loadout_key)
		return
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key] || list()
	if(!(gear_name in active))
		return
	var/list/item_meta = active[gear_name]
	if(!islist(item_meta))
		item_meta = list()
	item_meta["[tweak_idx]"] = new_value
	active[gear_name] = item_meta
	gear_list[loadout_key] = active
	preferences.update_preference_by_type(/datum/preference/gear_list, gear_list)
	preferences.update_preview_icon()
	SStgui.update_uis(preferences)

/// A colour for one of an equipped gear's tweaks. Re-checked on the answer: the same prefs, the
/// same loadout slot, and the gear still equipped in it.
/datum/prompt/color/prefs/gear_tweak
	var/gear_name
	var/tweak_idx
	var/loadout_key
	/// Palette swatches: the source colour being remapped.
	var/original

/datum/prompt/color/prefs/gear_tweak/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/preference_editor/loadout/editor = GLOB.preference_editors_by_key["loadout"]
	if(editor && editor._current_slot(preferences) != loadout_key)
		return "slot changed"
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key] || list()
	if(!(gear_name in active))
		return "not equipped"

/// Writes `value` as the tweak's metadata and refreshes the preview and the UI.
/datum/preference_editor/loadout/proc/write_tweak_meta(datum/prompt/color/prefs/gear_tweak/ask, value)
	var/datum/preferences/preferences = ask.preferences
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[ask.loadout_key] || list()
	var/list/item_meta = active[ask.gear_name]
	if(!islist(item_meta))
		item_meta = list()
	item_meta["[ask.tweak_idx]"] = value
	active[ask.gear_name] = item_meta
	gear_list[ask.loadout_key] = active
	preferences.update_preference_by_type(/datum/preference/gear_list, gear_list)
	preferences.update_preview_icon()
	SStgui.update_uis(preferences)

/datum/preference_editor/loadout/proc/tweak_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/prefs/gear_tweak/ask = A.answer
	write_tweak_meta(ask, sanitize_hexcolor(ask.value, default = ask.default))

/datum/preference_editor/loadout/proc/tint_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/prefs/gear_tweak/ask = A.answer
	write_tweak_meta(ask, list("mode" = "tint", "value" = sanitize_hexcolor(ask.value, default = ask.default)))

/datum/preference_editor/loadout/proc/swatch_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/prefs/gear_tweak/ask = A.answer
	var/list/gear_list = ask.preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[ask.loadout_key] || list()
	var/list/item_meta = active[ask.gear_name]
	var/list/cur_meta = islist(item_meta) ? item_meta["[ask.tweak_idx]"] : null
	var/list/cur_swaps = (islist(cur_meta) && cur_meta["mode"] == "palette" && islist(cur_meta["value"])) ? cur_meta["value"] : null
	var/list/swaps = cur_swaps ? cur_swaps.Copy() : list()
	var/original = ask.original
	var/sanitized = sanitize_hexcolor(ask.value, default = original)
	if(sanitized == original)
		swaps -= original  // identity entry — strip rather than persist
	else
		swaps[original] = sanitized
	write_tweak_meta(ask, list("mode" = "palette", "value" = swaps))

/datum/preference_editor/loadout/before_action(datum/preferences/preferences, mob/user, action)
	_validate_and_persist_slot(preferences)

/datum/preference_editor/loadout/proc/ui_act_set_loadout_key(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// was "switch_slot" + numeric index. Now switches which per-job loadout
	// is being edited. Validates against priorities + the "_default" sentinel.
	var/new_key = params["key"]
	if(!istext(new_key) || !_valid_loadout_key(preferences, new_key))
		return PREF_UPDATE_REJECTED
	preferences.update_preference_by_type(/datum/preference/text/human/gear_slot, new_key)
	_active_list(preferences, new_key)
	preferences.update_preview_icon()
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/loadout/proc/ui_act_toggle_gear(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/datum/gear/G = GLOB.gear_datums[params["gear"]]
	if(!G || !_gear_permitted_for(G, preferences))
		return PREF_UPDATE_REJECTED
	var/slot = _current_slot(preferences)
	var/list/active = _active_list(preferences, slot)
	if(G.display_name in active)
		active -= G.display_name
	else
		if(_list_cost(active) + G.cost > MAX_GEAR_COST)
			return PREF_UPDATE_REJECTED
		LAZYSET(active, G.display_name, list())
	_save_active(preferences, slot, active)
	preferences.update_preview_icon()
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/loadout/proc/ui_act_set_body_slot(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// Replaces (or adds, for multi-slots) the item occupying body_slot.
	var/datum/gear/G = GLOB.gear_datums[params["gear"]]
	if(!G || !_gear_permitted_for(G, preferences))
		return PREF_UPDATE_REJECTED
	var/body_slot_str = "[params["body_slot"]]"
	var/expected = slot_key_for(G)
	if(expected != body_slot_str)
		return PREF_UPDATE_REJECTED
	var/slot = _current_slot(preferences)
	var/list/active = _active_list(preferences, slot)
	var/multi = body_slot_str == "[SLOT_ID_TIE]" || body_slot_str == DQ_LOADOUT_OTHER_SLOT
	if(!multi)
		// Evict any item currently in this body slot.
		for(var/existing_name in active.Copy())
			var/datum/gear/existing = GLOB.gear_datums[existing_name]
			if(existing && slot_key_for(existing) == body_slot_str)
				active -= existing_name
	if(G.display_name in active)
		// already there — no-op
		return PREF_UPDATE_UNCHANGED
	if(_list_cost(active) + G.cost > MAX_GEAR_COST)
		return PREF_UPDATE_REJECTED
	LAZYSET(active, G.display_name, list())
	_save_active(preferences, slot, active)
	preferences.update_preview_icon()
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/loadout/proc/ui_act_clear_body_slot(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/body_slot_str = "[params["body_slot"]]"
	var/slot = _current_slot(preferences)
	var/list/active = _active_list(preferences, slot)
	for(var/existing_name in active.Copy())
		var/datum/gear/existing = GLOB.gear_datums[existing_name]
		if(existing && slot_key_for(existing) == body_slot_str)
			active -= existing_name
	_save_active(preferences, slot, active)
	preferences.update_preview_icon()
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/loadout/proc/ui_act_clear_loadout(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/slot = _current_slot(preferences)
	_save_active(preferences, slot, list())
	preferences.update_preview_icon()
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/loadout/proc/ui_act_set_tweak(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// opens the gear_tweak's input dialog and saves the returned value.
	var/gear_name = params["gear"]
	var/tweak_idx = params["tweak"]
	var/datum/gear/G = GLOB.gear_datums[gear_name]
	if(!G || !isnum(tweak_idx) || tweak_idx < 1 || tweak_idx > length(G.gear_tweaks))
		return PREF_UPDATE_REJECTED
	var/datum/gear_tweak/gt = LAZYACCESS(G.gear_tweaks, tweak_idx)
	var/loadout_key = _current_slot(preferences)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key] || list()
	if(!(gear_name in active))
		return PREF_UPDATE_REJECTED  // item must be equipped to customize
	var/list/item_meta = active[gear_name]
	if(!islist(item_meta))
		item_meta = list()
	var/cur_value = item_meta["[tweak_idx]"]
	// Asks, then tweak_answered() saves the new value.
	gt.ask_metadata(user, cur_value, G, null, src, PROC_REF(tweak_answered), new /datum/om/flow/ask_sequence/gear_tweak/loadout(preferences, gear_name, tweak_idx, loadout_key))
	return PREF_UPDATE_UNCHANGED

/datum/preference_editor/loadout/proc/ui_act_set_tweak_value(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// direct write from React inline widget (text/dropdown/color/boolean).
	// Bypasses get_metadata's tgui_input_X dialog because the React side already
	// did the input collection. Per-kind validation lives on /datum/gear_tweak
	// subtypes via validate_inline_value (see code/datums/gear/gear_tweaks.dm).
	var/gear_name = params["gear"]
	var/tweak_idx = params["tweak"]
	var/value = params["value"]
	var/datum/gear/G = GLOB.gear_datums[gear_name]
	if(!G || !isnum(tweak_idx) || tweak_idx < 1 || tweak_idx > length(G.gear_tweaks))
		return PREF_UPDATE_REJECTED
	var/datum/gear_tweak/gt = LAZYACCESS(G.gear_tweaks, tweak_idx)
	var/validated = gt.validate_inline_value(value, user)
	if(validated == PREF_UPDATE_REJECTED)
		return PREF_UPDATE_REJECTED
	value = validated
	var/loadout_key = _current_slot(preferences)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key] || list()
	if(!(gear_name in active))
		return PREF_UPDATE_REJECTED
	var/list/item_meta = active[gear_name]
	if(!islist(item_meta))
		item_meta = list()
	item_meta["[tweak_idx]"] = value
	active[gear_name] = item_meta
	gear_list[loadout_key] = active
	preferences.update_preference_by_type(/datum/preference/gear_list, gear_list)
	if(dq_gear_tweak_affects_preview(gt))
		preferences.update_preview_icon()
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/loadout/proc/ui_act_pick_tweak_color(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// opens BYOND's tgui_color_picker for a standalone /datum/gear_tweak/color
	// tweak (kind=color in React). Mirrors how the trait_picker editor handles its
	// blood color action — single explicit picker call, no JS-side color input.
	var/gear_name = params["gear"]
	var/tweak_idx = params["tweak"]
	var/datum/gear/G = GLOB.gear_datums[gear_name]
	if(!G || !isnum(tweak_idx) || tweak_idx < 1 || tweak_idx > length(G.gear_tweaks))
		return PREF_UPDATE_REJECTED
	var/datum/gear_tweak/gt = LAZYACCESS(G.gear_tweaks, tweak_idx)
	if(!istype(gt, /datum/gear_tweak/color))
		return PREF_UPDATE_REJECTED
	var/loadout_key = _current_slot(preferences)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key] || list()
	if(!(gear_name in active))
		return PREF_UPDATE_REJECTED
	var/list/item_meta = active[gear_name]
	if(!islist(item_meta))
		item_meta = list()
	var/cur = item_meta["[tweak_idx]"] || "#ffffff"
	open_request(src, /datum/prompt/color/prefs/gear_tweak, PROC_REF(tweak_color_picked), answerer = user, title = "[G.display_name]", question = "Pick a color", default = cur, preferences = preferences, gear_name = gear_name, tweak_idx = tweak_idx, loadout_key = loadout_key)
	return PREF_UPDATE_UNCHANGED

/datum/preference_editor/loadout/proc/ui_act_recolor_pick_tint(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// opens tgui_color_picker for the unified recolor tweak's tint mode.
	var/gear_name = params["gear"]
	var/tweak_idx = params["tweak"]
	var/datum/gear/G = GLOB.gear_datums[gear_name]
	if(!G || !isnum(tweak_idx) || tweak_idx < 1 || tweak_idx > length(G.gear_tweaks))
		return PREF_UPDATE_REJECTED
	var/datum/gear_tweak/gt = LAZYACCESS(G.gear_tweaks, tweak_idx)
	if(!istype(gt, /datum/gear_tweak/recolor))
		return PREF_UPDATE_REJECTED
	var/loadout_key = _current_slot(preferences)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key] || list()
	if(!(gear_name in active))
		return PREF_UPDATE_REJECTED
	var/list/item_meta = active[gear_name]
	if(!islist(item_meta))
		item_meta = list()
	var/list/cur_meta = item_meta["[tweak_idx]"]
	var/cur = (islist(cur_meta) && cur_meta["mode"] == "tint") ? cur_meta["value"] : "#ffffff"
	open_request(src, /datum/prompt/color/prefs/gear_tweak, PROC_REF(tint_color_picked), answerer = user, title = "[G.display_name]", question = "Tint color", default = cur, preferences = preferences, gear_name = gear_name, tweak_idx = tweak_idx, loadout_key = loadout_key)
	return PREF_UPDATE_UNCHANGED

/datum/preference_editor/loadout/proc/ui_act_recolor_pick_palette_swatch(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// palette-mode swatch picker. Takes `original` hex; opens tgui_color_picker
	// and updates the `original → new` mapping inside the recolor metadata's value dict.
	var/gear_name = params["gear"]
	var/tweak_idx = params["tweak"]
	var/original = params["original"]
	if(!istext(original))
		return PREF_UPDATE_REJECTED
	var/datum/gear/G = GLOB.gear_datums[gear_name]
	if(!G || !isnum(tweak_idx) || tweak_idx < 1 || tweak_idx > length(G.gear_tweaks))
		return PREF_UPDATE_REJECTED
	var/datum/gear_tweak/gt = LAZYACCESS(G.gear_tweaks, tweak_idx)
	if(!istype(gt, /datum/gear_tweak/recolor))
		return PREF_UPDATE_REJECTED
	var/loadout_key = _current_slot(preferences)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key] || list()
	if(!(gear_name in active))
		return PREF_UPDATE_REJECTED
	var/list/item_meta = active[gear_name]
	if(!islist(item_meta))
		item_meta = list()
	var/list/cur_meta = item_meta["[tweak_idx]"]
	var/list/cur_swaps = (islist(cur_meta) && cur_meta["mode"] == "palette" && islist(cur_meta["value"])) ? cur_meta["value"] : null
	var/list/swaps = cur_swaps ? cur_swaps.Copy() : list()
	var/cur_value = swaps[original] || original
	open_request(src, /datum/prompt/color/prefs/gear_tweak, PROC_REF(swatch_color_picked), answerer = user, title = "[G.display_name]", question = "Recolor source [original]", default = cur_value, preferences = preferences, gear_name = gear_name, tweak_idx = tweak_idx, loadout_key = loadout_key, original = original)
	return PREF_UPDATE_UNCHANGED

/datum/preference_editor/loadout/proc/ui_act_recolor_pick_matrix(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// opens the matrix colormatrix picker for the unified recolor tweak.
	var/gear_name = params["gear"]
	var/tweak_idx = params["tweak"]
	var/datum/gear/G = GLOB.gear_datums[gear_name]
	if(!G || !isnum(tweak_idx) || tweak_idx < 1 || tweak_idx > length(G.gear_tweaks))
		return PREF_UPDATE_REJECTED
	var/datum/gear_tweak/gt = LAZYACCESS(G.gear_tweaks, tweak_idx)
	if(!istype(gt, /datum/gear_tweak/recolor))
		return PREF_UPDATE_REJECTED
	var/loadout_key = _current_slot(preferences)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key] || list()
	if(!(gear_name in active))
		return PREF_UPDATE_REJECTED
	var/list/item_meta = active[gear_name]
	if(!islist(item_meta))
		item_meta = list()
	var/list/cur_meta = item_meta["[tweak_idx]"]
	var/list/cur_matrix = (islist(cur_meta) && cur_meta["mode"] == "matrix") ? cur_meta["value"] : null
	// The answer re-runs this action, so the item is checked again.
	var/list/new_matrix = rerun_ask(user, "matrix", PROC_REF(handle_action), args, /datum/om/prompt/colormatrix, message = "Pick a color matrix for this item", title = "Matrix Recolor", preview = G.path, default = cur_matrix, matrix_only = TRUE)
	if(!islist(new_matrix) || length(new_matrix) < 12)
		return PREF_UPDATE_UNCHANGED
	if(!user?.client?.prefs || user.client.prefs != preferences)
		return PREF_UPDATE_UNCHANGED
	item_meta["[tweak_idx]"] = list("mode" = "matrix", "value" = new_matrix)
	active[gear_name] = item_meta
	gear_list[loadout_key] = active
	preferences.update_preference_by_type(/datum/preference/gear_list, gear_list)
	preferences.update_preview_icon()
	SStgui.update_uis(preferences)
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/loadout/proc/ui_act_set_recolor(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	// direct write for the unified recolor tweak. value is a dict:
	//   {mode: "off"|"tint"|"palette"|"matrix", value: <mode-specific>}
	var/gear_name = params["gear"]
	var/tweak_idx = params["tweak"]
	var/list/value = params["value"]
	var/datum/gear/G = GLOB.gear_datums[gear_name]
	if(!G || !isnum(tweak_idx) || tweak_idx < 1 || tweak_idx > length(G.gear_tweaks))
		return PREF_UPDATE_REJECTED
	var/datum/gear_tweak/gt = LAZYACCESS(G.gear_tweaks, tweak_idx)
	if(!istype(gt, /datum/gear_tweak/recolor))
		return PREF_UPDATE_REJECTED
	if(!islist(value))
		return PREF_UPDATE_REJECTED
	var/mode = value["mode"]
	if(!(mode in list("off", "tint", "palette", "matrix")))
		return PREF_UPDATE_REJECTED
	// Validate-and-reconstruct: never persist the caller's dict directly — it may
	// carry stray params keys, and writing back the same reference would mutate the
	// React-supplied object visible to anything holding it. Always assemble a fresh
	// {mode, value} pair.
	switch(mode)
		if("off")
			value = list("mode" = "off")
		if("tint")
			var/c = value["value"]
			if(!istext(c) || length(c) < 4 || copytext(c, 1, 2) != "#")
				return PREF_UPDATE_REJECTED
			value = list("mode" = "tint", "value" = c)
		if("palette")
			var/list/swaps = value["value"]
			if(!islist(swaps))
				return PREF_UPDATE_REJECTED
			// Strip identity entries (no point persisting "red→red").
			var/list/cleaned = list()
			for(var/orig in swaps)
				var/new_color = swaps[orig]
				if(istext(orig) && istext(new_color) && orig != new_color)
					cleaned[orig] = new_color
			value = list("mode" = "palette", "value" = cleaned)
		if("matrix")
			// Initial switch to matrix mode sends an empty list — that's fine, the
			// matrix picker fills it. Only reject if value is *set* but malformed
			// (something other than null/empty or a 12+ element list).
			var/list/m = value["value"]
			if(islist(m) && length(m) > 0 && length(m) < 12)
				return PREF_UPDATE_REJECTED
			value = list("mode" = "matrix", "value" = islist(m) ? m : list())
	var/loadout_key = _current_slot(preferences)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key] || list()
	if(!(gear_name in active))
		return PREF_UPDATE_REJECTED
	var/list/item_meta = active[gear_name]
	if(!islist(item_meta))
		item_meta = list()
	item_meta["[tweak_idx]"] = value
	active[gear_name] = item_meta
	gear_list[loadout_key] = active
	preferences.update_preference_by_type(/datum/preference/gear_list, gear_list)
	preferences.update_preview_icon()
	return PREF_UPDATE_ACCEPTED

/datum/preference_editor/loadout/proc/ui_act_reset_tweaks(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
	var/gear_name = params["gear"]
	var/loadout_key = _current_slot(preferences)
	var/list/gear_list = preferences.read_preference(/datum/preference/gear_list) || list()
	var/list/active = gear_list[loadout_key] || list()
	if(!(gear_name in active))
		return PREF_UPDATE_REJECTED
	active[gear_name] = list()
	gear_list[loadout_key] = active
	preferences.update_preference_by_type(/datum/preference/gear_list, gear_list)
	preferences.update_preview_icon()
	return PREF_UPDATE_ACCEPTED

// copy_to_slot was a dead remnant of the numeric-slot model. Under the title-keyed
// shape it would text2num("Captain") → null → write gear_list["1"] (garbage key).
// React never called it; removed.

#undef DQ_LOADOUT_OTHER_SLOT

/// /datum/preference_editor/loadout's actions (the character setup window's "dq_editor_action" messages): each one's arguments go through their schemas first.
/datum/preference_editor/loadout/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	var/list/typed
	switch(action)
		if("set_loadout_key")
			typed = payload_args(src, params, list("key" = schema_text(4096)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_loadout_key(user, typed, preferences, null, action)
		if("toggle_gear")
			typed = payload_args(src, params, list("gear" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_toggle_gear(user, typed, preferences, null, action)
		if("set_body_slot")
			typed = payload_args(src, params, list("body_slot" = schema_text(4096), "gear" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_body_slot(user, typed, preferences, null, action)
		if("clear_body_slot")
			typed = payload_args(src, params, list("body_slot" = schema_text(4096)))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_clear_body_slot(user, typed, preferences, null, action)
		if("clear_loadout")
			typed = payload_args(src, params, list())
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_clear_loadout(user, typed, preferences, null, action)
		if("set_tweak")
			typed = payload_args(src, params, list("gear" = null, "tweak" = num()))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_tweak(user, typed, preferences, null, action)
		if("set_tweak_value")
			typed = payload_args(src, params, list("gear" = null, "tweak" = num(), "value" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_tweak_value(user, typed, preferences, null, action)
		if("pick_tweak_color")
			typed = payload_args(src, params, list("gear" = null, "tweak" = num()))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_pick_tweak_color(user, typed, preferences, null, action)
		if("recolor_pick_tint")
			typed = payload_args(src, params, list("gear" = null, "tweak" = num()))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_recolor_pick_tint(user, typed, preferences, null, action)
		if("recolor_pick_palette_swatch")
			typed = payload_args(src, params, list("gear" = null, "original" = schema_text(4096), "tweak" = num()))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_recolor_pick_palette_swatch(user, typed, preferences, null, action)
		if("recolor_pick_matrix")
			typed = payload_args(src, params, list("gear" = null, "tweak" = num()))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_recolor_pick_matrix(user, typed, preferences, null, action)
		if("set_recolor")
			typed = payload_args(src, params, list("gear" = null, "tweak" = num(), "value" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_set_recolor(user, typed, preferences, null, action)
		if("reset_tweaks")
			typed = payload_args(src, params, list("gear" = null))
			if(!typed)
				return PREF_UPDATE_REJECTED
			before_action(preferences, user, action)
			return ui_act_reset_tweaks(user, typed, preferences, null, action)
	return ..()
