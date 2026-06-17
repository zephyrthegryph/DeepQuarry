// Wounding — a melee hit to a specific limb does more than damage: it applies an effect
// tied to that limb. Aim at the legs to slow a fleeing mob, the arms to spoil its offense
// (and disarm a player), or the head to daze it. The "cost" of a targeted wound is just
// aiming there; only a solid hit (DQ_WOUND_MIN_FORCE+) from a weapon wounds — light taps
// don't cripple. Works on humans (real organ tags) and simple_mobs (single health pool,
// effects applied as status/modifier) alike, so the same swing reads the same against both.

/// Apply the limb-effect for a melee hit `src` landed on `victim` at `hit_zone`. Called
/// from the player swing path right after the hit resolves.
/mob/living/proc/apply_wound_effect(mob/living/victim, obj/item/weapon, hit_zone)
	if(!victim || victim.stat >= DEAD)
		return
	if(!istype(weapon) || weapon.force < DQ_WOUND_MIN_FORCE)
		return // unarmed / light taps don't wound a limb
	var/zone = hit_zone
	if(!zone && zone_sel)
		zone = zone_sel.selecting // clientless/edge fallback to the aimed zone
	switch(zone)
		if(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)
			victim.add_modifier(/datum/modifier/dq_wound_leg, DQ_WOUND_DURATION)
			victim.visible_message(span_warning("\The [victim] buckles as the blow tears into their leg!"))
			playsound(victim, pick('sound/effects/wounds/crack1.ogg', 'sound/effects/wounds/crack2.ogg'), 40, 1, -1)
		if(BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND)
			// Spoil the victim's offense: a brief attack lockout, and a chance to knock a
			// held weapon out of a player's grip.
			victim.melee_locked_until = max(victim.melee_locked_until, world.time + DQ_WOUND_ARM_LOCK)
			if(ishuman(victim))
				var/mob/living/carbon/human/H = victim
				var/obj/item/held = (zone == BP_R_ARM || zone == BP_R_HAND) ? H.r_hand : H.l_hand
				if(held && prob(45))
					H.drop_from_inventory(held)
					victim.visible_message(span_warning("\The [victim] loses their grip on \the [held]!"))
				else
					victim.visible_message(span_warning("\The [victim]'s arm goes limp under the blow!"))
			else
				victim.visible_message(span_warning("\The [victim]'s limb buckles under the blow!"))
			playsound(victim, 'sound/effects/wounds/pierce1.ogg', 35, 1, -1)
		if(BP_HEAD)
			victim.Confuse(DQ_WOUND_HEAD_DAZE)
			victim.eye_blurry = max(victim.eye_blurry || 0, 5)
			victim.add_stagger(round(victim.max_stagger * 0.15), src) // headshots rattle poise extra
			victim.visible_message(span_warning("\The [victim] reels, dazed by the blow to the head!"))
			playsound(victim, 'sound/weapons/genhit.ogg', 45, 1, -1)

/datum/modifier/dq_wound_leg
	name = "wounded leg"
	desc = "A leg wound is slowing you down."
	slowdown = 2
	stacks = MODIFIER_STACK_EXTEND // re-hitting the leg extends the limp rather than no-oping
	on_created_text = span_warning("Your leg screams — you can't move at full speed!")
	on_expired_text = span_notice("The ache in your leg finally fades.")
