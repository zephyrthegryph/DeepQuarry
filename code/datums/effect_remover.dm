/// Lets an item delete certain effects by hitting them (the anomaly neutralizer).
/// (Was /datum/component/effect_remover; now a plain datum owned by the item.)
/datum/effect_remover
	/// The item doing the removing.
	var/obj/item/owner
	/// Line sent to the user on successful removal.
	var/success_feedback
	/// Line forcesaid by the user on successful removal.
	var/success_forcesay
	/// A PROC_REF on the owning item, called as owner.on_clear(effect, user) when an effect is removed (holder_call()).
	var/on_clear
	/// A typecache of all effects we can clear with our item.
	var/list/effects_we_clear // typecache
	/// If above 0, how long it takes while standing still to remove the effect.
	var/time_to_remove = 0 SECONDS

/datum/effect_remover/New(obj/item/new_owner, success_forcesay, success_feedback, on_clear, effects_we_clear, time_to_remove)
	..()
	if(!isitem(new_owner))
		log_world("[type] was created for a non-item ([new_owner]); it does nothing.")
		return
	if(!effects_we_clear)
		stack_trace("[type] was instantiated without any valid removable effects!")
		return

	rel_set(src, nameof(owner), new_owner)
	src.on_clear = on_clear
	src.effects_we_clear = typecacheof(effects_we_clear)
	src.time_to_remove = time_to_remove
	observe(owner, /datum/notice/pre_attacked, src, then(PROC_REF(try_remove_effect)))

/datum/effect_remover/proc/try_remove_effect(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/pre_attacked/event = N
	var/atom/target = event.target_
	var/mob/living/user = event.user

	if(!isliving(user))
		return NONE

	if(is_type_in_typecache(target, effects_we_clear))
		do_remove_effects(target, user)
		return

/datum/effect_remover/proc/do_remove_effects(obj/effect/target, mob/living/user)
	if(on_clear && !QDELETED(owner))
		holder_call(owner, on_clear, target, user)

	if(!QDELETED(target))
		spent(target, user)

