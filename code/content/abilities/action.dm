/**
 * # The ability list
 *
 * Every mob has one ordered list of abilities (`/mob::actions`), shown as the Abilities tab of the stat panel (ability_panel.dm).
 * An entry is a /datum/action: an item's toggle (flashlight, jetpack, internals), an innate power (a mecha's controls, a xenomorph's
 * spit), an ability op the mob was granted (shadekin phase shift, a cyborg's module toggles: op_ability.dm). A source adds an entry with
 * Grant() when the mob gains the ability and takes it away with Remove() when it is lost; the panel is told at once, nothing polls.
 *
 * What an entry tells the panel: its name, description, icon, category (which source it is), cost, cooldown, whether it is a toggle that is
 * on, the progress of a channel in progress, and whether it can be used now with the reason when it cannot. A subtype overrides the
 * ability_*() procs it has something to say about; state that changes while the entry stays (a toggle flips, a cooldown starts) tells the
 * panel with ability_changed().
 */
/datum/action
	/// The name of the action
	var/name = "Generic Action"
	/// The description of what the action does, shown when the player hovers its button
	var/desc
	/// The datum the action is attached to (action_target()): if it is deleted, the action is as well. Set in New() via link_to().
	/// PLEASE set a target if you're making an action.
	var/datum/acts_for
	/// Who currently owns the action (action_owner()), and most often who is using it when it is triggered. It can be the same as the
	/// target but is not ALWAYS the same: Grant() and Remove() set and unset it, and the owner being deleted removes the action from them.
	var/mob/granted_to
	/// Flags that will determine of the owner / user of the action can... use the action
	var/check_flags = NONE
	/// Which source the ability is: ABILITY_CATEGORY_*. It groups the entry in the Abilities tab.
	var/ability_category = ABILITY_CATEGORY_ITEMS

	/// This is the file for the icon that appears on the button (null: the target's own appearance)
	var/button_icon = 'icons/mob/actions.dmi'
	/// This is the icon state for the icon that appears on the button
	var/button_icon_state = "default"

CAPABILITIES(/datum/action)
	ref_one(nameof(acts_for), /datum, on_other_deleted = OTHER_DELETE_ME)
	ref_one(nameof(granted_to), /mob, on_unlink = PROC_REF(owner_unlinked))

/// The datum this action acts for, or null.
/datum/action/proc/action_target() as /datum
	return acts_for

/// The mob this action is granted to, or null.
/datum/action/proc/action_owner() as /mob
	return granted_to

/// The owner link went: when the owner is the one being deleted, the action leaves it.
/datum/action/proc/owner_unlinked(mob/owner)
	if(QDELETED(src) || QDELETED(owner))
		Remove(owner)

/// The action leaves its owner when it is deleted.
/datum/action/on_destroy(force)
	if(granted_to)
		Remove(granted_to)
	..()

/datum/action/New(Target)
	link_to(Target)

/// Links the passed target to our action (the action_for relation: its deletion deletes us)
/datum/action/proc/link_to(Target)
	if(Target)
		rel_set(src, nameof(acts_for), Target)

/// From /datum/action/Grant(): (datum/action)
ACTION(mob_granted_action, datum/action/action, FIXED, notice = /datum/notice/mob_granted_action)

/// Grants the action to the passed mob, making it the owner: it joins the mob's ability list.
/datum/action/proc/Grant(mob/grant_to)
	if(!grant_to)
		Remove(action_owner())
		return
	var/mob/owner = action_owner()
	if(owner)
		if(owner == grant_to)
			return
		Remove(owner)

	PUBLISH(grant_to, mob_granted_action, action = src)
	rel_set(src, nameof(granted_to), grant_to)
	rel_add(grant_to, nameof(/mob::actions), src)
	if(grant_to.client)
		log_input("Ability: [key_name(grant_to)] gained [ability_id()] ([ability_category]).")
	grant_to.abilities_changed()

/// From /datum/action/Remove(): (datum/action)
ACTION(mob_removed_action, datum/action/action, FIXED, notice = /datum/notice/mob_removed_action)

/// Remove the passed mob from being owner of our action: it leaves the mob's ability list.
/datum/action/proc/Remove(mob/remove_from)
	SHOULD_CALL_PARENT(TRUE)

	if(remove_from)
		rel_remove(remove_from, nameof(/mob::actions), src)

	// While the owner relation is being torn down (either end deleted) the edge is already gone.
	var/mob/owner = action_owner() || remove_from
	if(owner)
		PUBLISH(owner, mob_removed_action, action = src)
		rel_set(src, nameof(granted_to), null)
		if(owner.client)
			log_input("Ability: [key_name(owner)] lost [ability_id()] ([ability_category]).")
		owner.abilities_changed()

/// Actually triggers the effects of the action.
/// Called when the ability is used from the Abilities tab or its hotkey, for example.
/datum/action/proc/Trigger(trigger_flags)
	if(!IsAvailable())
		return FALSE
	return TRUE

/// Whether our action is currently available to use or not
/datum/action/proc/IsAvailable()
	var/mob/owner = action_owner()
	if(!owner)
		return FALSE
	if(check_flags & AB_CHECK_RESTRAINED)
		if(owner.restrained())
			return FALSE
	if(check_flags & AB_CHECK_STUNNED)
		if(owner.has_status(STAT_STUNNED))
			return FALSE
	if(check_flags & AB_CHECK_LYING)
		if(owner.lying)
			return FALSE
	if(check_flags & AB_CHECK_CONSCIOUS)
		if(owner.stat)
			return FALSE
	return TRUE

/// The state of the ability changed (a toggle flipped, a cooldown began, its icon changed): the owner's Abilities tab is told.
/datum/action/proc/ability_changed()
	var/mob/owner = action_owner()
	owner?.abilities_changed()

// ---- What the Abilities tab shows ----

/// The id that names this ability in a player's saved order and in the hotkey log: the same ability gets the same id every round.
/// Two entries with one id (two flashlights) keep the order they were gained in.
/datum/action/proc/ability_id()
	var/datum/target = action_target()
	return target ? "[ability_category]/[type]/[target.type]" : "[ability_category]/[type]"

/// The hover text: the action's description, or its name.
/datum/action/proc/ability_desc()
	return desc || name

/// The cost to use it as short text ("40 energy"), or null.
/datum/action/proc/ability_cost()
	return null

/// Deciseconds until it can be used again, 0 when it is ready.
/datum/action/proc/ability_cooldown_left()
	return 0

/// Null when it is not a toggle, else whether it is on.
/datum/action/proc/ability_toggled()
	return null

/// Progress (0 to 1) of what the ability is doing now when it is a channel in progress, or null.
/datum/action/proc/ability_channel()
	return null

/// Null when the ability can be used now, else why not (shown greyed on hover). `menu_rows`: the owner's op_menu() rows when the caller has
/// them already (an op's entry reads its refusal there).
/datum/action/proc/ability_refusal(list/menu_rows)
	var/mob/owner = action_owner()
	if(!owner)
		return "nobody has this ability"
	if(ability_cooldown_left() > 0)
		return "recharging"
	if(IsAvailable())
		return null
	if((check_flags & AB_CHECK_CONSCIOUS) && owner.stat)
		return "you are not conscious"
	if((check_flags & AB_CHECK_STUNNED) && owner.has_status(STAT_STUNNED))
		return "you are stunned"
	if((check_flags & AB_CHECK_RESTRAINED) && owner.restrained())
		return "you are restrained"
	if((check_flags & AB_CHECK_LYING) && owner.lying)
		return "you cannot do that lying down"
	return "not available now"

/// The thing whose appearance is the ability's icon: its target when it has one and the action names no icon state of its own, else null
/// (the icon file and state are used).
/datum/action/proc/ability_icon_source() as /atom
	var/datum/target = action_target()
	if(isnull(button_icon_state) && isatom(target))
		return target
	return null
