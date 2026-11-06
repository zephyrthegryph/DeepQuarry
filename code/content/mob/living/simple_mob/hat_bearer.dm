// hat_bearer(slot_var, allowed =): a small creature that can wear a hat you put on it (the armadillo, the slime, the catslug).
//
//   CAPABILITIES(/mob/living/simple_mob/slime)
//       owns_one(nameof(hat), on_destroy = ON_DESTROY_SPILL)
//       hat_bearer(nameof(hat))
//   CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug)
//       owns_one(nameof(hat), on_destroy = ON_DESTROY_SPILL)
//       hat_bearer(nameof(hat), allowed = nameof(can_wear_hat))
//
// The ops, keyed hat_bearer.<var>.<name>:
//   put    a hat in hand goes on the creature (refused while it wears one, or while its `allowed` var is false).
//   take   an empty hand in the grab stance takes the hat off (refused, and the click goes on, when it has none).
// The var is the creature's owns_one(): what happens to the hat when the creature goes is said there. The creature draws the hat itself (look.hat()).

MSG_DEF_SELF(hat_bearer/put, "You place %I% on %T%.  How adorable!")
MSG_DEF_SELF(hat_bearer/taken, "You take away the hat from %T%.  How mean.")
MSG_DEF_SELF(hat_bearer/already, "%T% is already wearing a hat.")
MSG_DEF_SELF(hat_bearer/none, "%T% doesn't have a hat to remove.")
MSG_DEF_SELF(hat_bearer/unable, "%T% is unable to wear a hat.")

CAPABILITY_TYPE(hat_bearer, CAP_HAT_BEARER, /datum/capability/hat_bearer, key = slot_var, slot_var = null, allowed = null)

/datum/capability/hat_bearer

/datum/capability/hat_bearer/entries()
	var/list/put_needs = list(req_empty(slot_var, because = MSG(hat_bearer/already)))
	if(allowed)
		put_needs += req_is(allowed, TRUE, because = MSG(hat_bearer/unable))
	return list(
		op("put", item(/obj/item/clothing/head), priority(OP_PRIORITY_NORMAL), label("Put hat on"), needs(arglist(put_needs)), put_in(slot_var), says(MSG(hat_bearer/put))),
		op("take", hand(), ungated(), stance(I_GRAB), priority(OP_PRIORITY_NORMAL), label("Take hat off"), needs(req_full(slot_var, because = MSG(hat_bearer/none))), take_out(slot_var), says(MSG(hat_bearer/taken))))
