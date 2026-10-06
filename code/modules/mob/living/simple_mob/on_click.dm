/*
	Animals
*/
/mob/living/simple_mob/UnarmedAttack(atom/A, proximity, stance = I_HURT)
	if(!(. = ..()))
		return


	if(has_hands && istype(A,/obj) && stance != I_HURT)
		var/obj/O = A
		return O.attack_hand(src)

	switch(stance)
		if(I_HELP)

			if(isliving(A))
				var/mob/living/L = A
				if(istype(L) && (!has_hands || !L.attempt_to_scoop(src)))
					if(src.zone_sel.selecting == BP_GROIN)
						if(src.vore_bellyrub(A))
							return
					automatic_custom_emote(VISIBLE_MESSAGE,"[pick(friendly)] \the [A]!", check_stat = TRUE)
			if(istype(A,/obj/structure/micro_tunnel))	//Allows simplemobs to click on mouse holes, mice should be allowed to go in mouse holes, and other mobs
				var/obj/structure/micro_tunnel/t = A	//should be allowed to drag the mice out of the mouse holes!
				perform_op(src, t, micro_tunnel_holds(t, src) ? "inside_use" : "use", null, ORIGIN_SYSTEM)

		if(I_HURT)
			if(can_special_attack(A) && special_attack_target(A, stance))
				return

			else if(melee_damage_upper == 0 && isliving(A))
				automatic_custom_emote(VISIBLE_MESSAGE,"[pick(friendly)] \the [A]!", check_stat = TRUE)

			else
				attack_target(A, stance)

		if(I_GRAB)
			if(has_hands)
				A.attack_hand(src)
			else if(isliving(A) && src.client && !vore_attack_override)
				animal_nom(A)
			else
				attack_target(A, stance)

		if(I_DISARM)
			if(has_hands)
				A.attack_hand(src)
			else
				attack_target(A, stance)

/mob/living/simple_mob/RangedAttack(atom/A, params, stance = I_HURT)

	if(can_special_attack(A) && special_attack_target(A, stance))
		return

	if(projectiletype)
		shoot_target(A)
