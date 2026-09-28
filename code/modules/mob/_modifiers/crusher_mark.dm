/// A kinetic crusher's destabilizer mark. The origin is the crusher that fired it: only that
/// crusher can detonate the mark. Per-application state: the underlay drawn on the mob.
/datum/body_effect/crusher_mark
	name = "destabilized"
	desc = "You've been struck by a destabilizing bolt. By all accounts, this is probably a bad thing."
	stacks = MODIFIER_STACK_EXTEND
	on_created_text = span_warning("You feel physically unstable.")
	on_expired_text = span_notice("You feel physically stable again.")

/datum/body_effect/crusher_mark/can_apply(mob/living/L, suppress_output = FALSE)
	var/obj/item/kinetic_crusher/hammer = L.body_effect_origin(type)
	return istype(hammer) ? hammer.can_mark(L) : TRUE

/datum/body_effect/crusher_mark/on_start(mob/living/L)
	var/mutable_appearance/marked_underlay = mutable_appearance('icons/effects/effects.dmi', "shield2")
	marked_underlay.pixel_x = -L.pixel_x
	marked_underlay.pixel_y = -L.pixel_y
	L.underlays += marked_underlay
	L.set_body_effect_state(type, marked_underlay)

/datum/body_effect/crusher_mark/on_end(mob/living/L, expired)
	L.underlays -= L.body_effect_state(type)
