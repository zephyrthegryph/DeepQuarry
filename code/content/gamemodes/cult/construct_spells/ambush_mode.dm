/datum/spell/targeted/ambush_mode
	name = "Toggle Ambush"
	desc = "Phase yourself mostly out of this reality, minimizing your combat ability, but allowing for employance of ambush tactics."

	range = -1
	school = "evocation"
	charge_type = Sp_RECHARGE
	invocation_type = SpI_NONE

	spell_flags = CONSTRUCT_CHECK | INCLUDEUSER

	hud_state = "const_ambush"
	smoke_amt = 0

	charge_max = 100

/datum/spell/targeted/ambush_mode/cast(list/targets, mob/living/user)
	if(findNullRod(user))
		charge_counter = 50
		return
	if(user.has_body_effect(/datum/body_effect/ambush))
		user.remove_body_effect(/datum/body_effect/ambush)
		return
	user.apply_body_effect(/datum/body_effect/ambush, 0)
