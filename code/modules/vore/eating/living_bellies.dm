/*
 * Vore fullness: how full the bellies of a mob look.
 *
 * vore_fullness and vore_fullness_ex are TRACKED: a mob's draw reads them, so a change redraws it with no call.
 * The bellies announce what they show of the body: PUBLISH(owner, belly_change) when prey or items enter or leave,
 * when a belly's liquid or a prey's health moves its size, and when its sprite settings are edited. The mob hears
 * /datum/notice/belly_changed (CAPABILITIES(/mob)) and recomputes both from the bellies in update_fullness(), which writes
 * through the setters. Nothing redraws by hand.
 *
 * Shared helper:  vore_fullness_states(state)
 *   The belly-class fullness overlay states (e.g. "wolf_stomach-2") of a state, for a draw.
 */

/// The owner's bellies changed what they show of its body: recompute the tracked fullness.
/mob/proc/belly_changed(datum/act/A)
	update_fullness()

/// vore_fullness_ex is a list whose content a change compares (a fresh equal list is no change).
/mob/proc/set_vore_fullness_ex(list/value)
	if(fullness_buckets_match(vore_fullness_ex, value))
		return FALSE
	vore_fullness_ex = value
	tracked_changed(src, nameof(vore_fullness_ex))
	return TRUE
SETTER(/mob, vore_fullness_ex)

TRACKED(/mob, vore_fullness)
TRACKED(/mob, vore_icons)

/mob/proc/update_fullness()
	if(updating_fullness)
		return
	updating_fullness = TRUE
	var/list/new_fullness = list()
	var/total = 0
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
	var/list/classes = vore_fullness_ex.Copy()
	for(var/belly_class in vore_icon_bellies)
		new_fullness[belly_class] /= size_multiplier //Divided by pred's size so a macro mob won't get macro belly from a regular prey.
		new_fullness[belly_class] *= belly_size_multiplier // Some mobs are small even at 100% size. Let's account for that.
		new_fullness[belly_class] = round(new_fullness[belly_class], 1) // Because intervals of 0.25 are going to make sprite artists cry.
		classes[belly_class] = min(vore_capacity_ex[belly_class], new_fullness[belly_class])
		total += new_fullness[belly_class]
	set_vore_fullness_ex(classes)
	set_vore_fullness(min(vore_capacity, max(total, 0)))
	updating_fullness = FALSE
	return new_fullness

/mob/living/proc/vs_animate(belly_to_animate)
	return

/// The overlay states of the belly classes that show fullness in `state`: "[state]_[belly_class]-[fullness]" for each class above 0
/// (the sprite sheets' convention for simple mobs).
/mob/living/proc/vore_fullness_states(state)
	. = list()
	for(var/belly_class in vore_fullness_ex)
		var/vs_fullness = vore_fullness_ex[belly_class]
		if(vs_fullness > 0)
			. += "[state]_[belly_class]-[vs_fullness]"

/mob/proc/fullness_buckets_match(list/old_ex, list/new_ex)
	if(length(old_ex) != length(new_ex))
		return FALSE
	for(var/belly_class in new_ex)
		if(old_ex[belly_class] != new_ex[belly_class])
			return FALSE
	return TRUE
