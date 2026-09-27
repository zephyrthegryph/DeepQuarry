/*
 * Vore icon update — three tiers, ordered cheapest→most expensive:
 *
 * Tier 1 (fullness):  update_fullness()
 *   Recalculates vore_fullness and vore_fullness_ex from current belly
 *   contents.  Pure math; no visual side effects.  Called automatically by
 *   handle_belly_update() and by Tier 2 paths before rebuilding sprites.
 *
 * Tier 2 (belly contents changed):  handle_belly_update()
 *   Called whenever prey enters or leaves a belly (Entered, Exited,
 *   digest-death, absorb, autotransfer, etc.).  For humans this calls
 *   update_fullness() and then lets update_icons() pick up the new values
 *   on the next icon refresh; for all other mobs it calls update_icon() which
 *   does a full icon rebuild.  Use this instead of a raw update_icon() call
 *   anywhere that cares about belly contents.
 *
 * Tier 3 (full icon rebuild):  update_icon()
 *   Cuts all overlays, resets icon_state, and reapplies every overlay layer
 *   from scratch.  Calls update_fullness() internally for simple_mob types.
 *   For human mobs the heavy lifting is in update_icons_body(); for
 *   simple_mob the fullness-driven icon_state suffix ("-N") and per-belly
 *   overlays are applied here.  Avoid calling directly if
 *   handle_belly_update() is sufficient — the extra cut_overlays() is costly.
 *
 * Shared helper:  add_vore_fullness_overlays()
 *   Appends belly-class fullness overlays (e.g. "wolf_stomach-2") to the
 *   current mob.  Used by the simple_mob update_icon() path.  Extracted here
 *   to eliminate the duplicated inline loop.
 */

/mob/proc/update_fullness()
	if(updating_fullness)
		return
	updating_fullness = TRUE
	var/list/new_fullness = list()
	vore_fullness = 0
	for(var/belly_class in vore_icon_bellies)
		new_fullness[belly_class] = 0
	for(var/obj/belly/B as anything in vore_organs)
		if(DM_FLAG_VORESPRITE_BELLY & B.vore_sprite_flags)
			new_fullness[B.belly_sprite_to_affect] += B.GetFullnessFromBelly()
		if(ishuman(src) && DM_FLAG_VORESPRITE_ARTICLE & B.vore_sprite_flags)
			if(!new_fullness[B.undergarment_chosen])
				new_fullness[B.undergarment_chosen] = 1
			new_fullness[B.undergarment_chosen] += B.GetFullnessFromBelly()
			new_fullness[B.undergarment_chosen + "-ifnone"] = B.undergarment_if_none
			new_fullness[B.undergarment_chosen + "-color"] = B.undergarment_color
	for(var/belly_class in vore_icon_bellies)
		new_fullness[belly_class] /= size_multiplier //Divided by pred's size so a macro mob won't get macro belly from a regular prey.
		new_fullness[belly_class] *= belly_size_multiplier // Some mobs are small even at 100% size. Let's account for that.
		new_fullness[belly_class] = round(new_fullness[belly_class], 1) // Because intervals of 0.25 are going to make sprite artists cry.
		vore_fullness_ex[belly_class] = min(vore_capacity_ex[belly_class], new_fullness[belly_class])
		vore_fullness += new_fullness[belly_class]
	if(vore_fullness < 0)
		vore_fullness = 0
	vore_fullness = min(vore_capacity, vore_fullness)
	updating_fullness = FALSE
	return new_fullness

/mob/living/proc/vs_animate(belly_to_animate)
	return

/// Appends per-belly-class fullness overlays to the current mob's appearance.
/// The overlay name format is "[current icon_state]_[belly_class]-[fullness]",
/// matching the sprite convention used by simple_mob vore sprite sheets.
/// Only overlays with a positive fullness value are added.
///
/// Callers are responsible for setting the correct icon_state before calling
/// this proc so the overlay names resolve correctly.
/mob/living/proc/add_vore_fullness_overlays()
	for(var/belly_class in vore_fullness_ex)
		var/vs_fullness = vore_fullness_ex[belly_class]
		if(vs_fullness > 0)
			add_overlay("[icon_state]_[belly_class]-[vs_fullness]")

// use this instead of update_fullness where you need to directly update a belly size
/mob/proc/handle_belly_update()
	if(ishuman(src))
		update_fullness()
		return
	update_icon()

// Like handle_belly_update(), but skips the (expensive, for non-humans) icon
// rebuild when the rounded fullness buckets haven't actually changed. Use this
// on per-tick paths (e.g. digestion driving health_impacts_size) where the
// underlying value drifts continuously but the displayed sprite only changes
// when a fullness bucket crosses an integer boundary.
/mob/proc/handle_belly_update_buckets()
	// update_fullness() is pure math (rounds into integer buckets); always run it.
	if(ishuman(src))
		update_fullness()
		return
	var/old_fullness = vore_fullness
	var/list/old_fullness_ex = vore_fullness_ex.Copy()
	update_fullness()
	if(old_fullness == vore_fullness && fullness_buckets_match(old_fullness_ex, vore_fullness_ex))
		return
	update_icon()

/mob/proc/fullness_buckets_match(list/old_ex, list/new_ex)
	if(length(old_ex) != length(new_ex))
		return FALSE
	for(var/belly_class in new_ex)
		if(old_ex[belly_class] != new_ex[belly_class])
			return FALSE
	return TRUE
