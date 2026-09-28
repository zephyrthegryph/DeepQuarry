/// Lets an item delete certain effects by hitting them (the anomaly neutralizer).
/// (Was /datum/component/effect_remover; now a plain datum owned by the item.)
/datum/effect_remover
	/// The item doing the removing.
	var/obj/item/owner
	/// Line sent to the user on successful removal.
	var/success_feedback
	/// Line forcesaid by the user on successful removal.
	var/success_forcesay
	/// Callback invoked with removal is done.
	var/datum/callback/on_clear_callback
	/// A typecache of all effects we can clear with our item.
	var/list/effects_we_clear // typecache
	/// If above 0, how long it takes while standing still to remove the effect.
	var/time_to_remove = 0 SECONDS

/datum/effect_remover/New(obj/item/new_owner, success_forcesay, success_feedback, on_clear_callback, effects_we_clear, time_to_remove)
	..()
	if(!isitem(new_owner))
		log_world("[type] was created for a non-item ([new_owner]); it does nothing.")
		return
	if(!effects_we_clear)
		stack_trace("[type] was instantiated without any valid removable effects!")
		return

	owner = new_owner
	//src.success_feedback = success_feedback
	//src.success_forcesay = success_forcesay
	src.on_clear_callback = on_clear_callback
	src.effects_we_clear = typecacheof(effects_we_clear)
	src.time_to_remove = time_to_remove
	om_hook(owner, /datum/om/event/before/item_pre_attack, src, PROC_REF(try_remove_effect))

// ALLOW(lifecycle): owned state datum (was a component) unhooks and detaches from its owner.
/datum/effect_remover/Destroy(force)
	if(owner)
		om_unhook(owner, /datum/om/event/before/item_pre_attack, src)
	owner = null
	return ..()

/datum/effect_remover/proc/try_remove_effect(datum/source, datum/om/event/before/item_pre_attack/event)
	EVENT_HANDLER
	var/atom/target = event.target
	var/mob/living/user = event.user

	if(!isliving(user))
		return NONE

	if(is_type_in_typecache(target, effects_we_clear))
		do_remove_effects(target, user)
		return

/datum/effect_remover/proc/do_remove_effects(obj/effect/target, mob/living/user)
	on_clear_callback?.Invoke(target, user)

	if(!QDELETED(target))
		qdel(target)

REF_OWNED(/datum/effect_remover, "on_clear_callback")
REF_BACK(/datum/effect_remover, list("owner" = null))
