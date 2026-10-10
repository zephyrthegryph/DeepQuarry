// An indestructible blast door that can only be opened once its puzzle requirements are completed.

/obj/machinery/door/blast/puzzle
	// Puzzle geometry is a scenario boundary, not destructible station machinery.
	resistance_flags = INDESTRUCTIBLE
	name = "puzzle door"
	desc = "A large, virtually indestructible door that will not open unless certain requirements are met."
	icon_state_open = "pdoor0"
	icon_state_opening = "pdoorc0"
	icon_state_closed = "pdoor1"
	icon_state_closing = "pdoorc1"
	icon_state = "pdoor1"

	explosion_resistance = 100

	max_integrity = 9999999 //No.
	heat_proof = 1 //just so repairing them doesn't try to fireproof something that never takes fire damage

	var/list/locks
	var/lockID = null
	var/checkrange_mult = 1

/obj/machinery/door/blast/puzzle/proc/check_locks()
	if(!locks || length(locks) <= 0) // Puzzle doors with no locks will only listen to boring buttons.
		return 0

	for(var/obj/structure/prop/lock/L in locks)
		if(!L.enabled)
			return 0
	return 1

/obj/machinery/door/blast/puzzle/bullet_act(obj/item/projectile/Proj)
	if(!istype(Proj, /obj/item/projectile/test))
		visible_message(span_cult("\The [src] is completely unaffected by \the [Proj]."))
	destroyed(Proj) //No piercing. No.

/obj/machinery/door/blast/puzzle/Initialize(mapload)
	. = ..()
	implicit_material = get_material_by_name(MAT_ALIEN_DUNGEON)
	if(length(locks))
		return
	var/check_range = world.view * checkrange_mult
	for(var/obj/structure/prop/lock/L in orange(src, check_range))
		if(L.lockID == lockID)
			rel_add(src, nameof(locks), L) // the pair adds us to L.linked_objects

// many-to-many with locks (declared on the lock, projectile_lock.dm): a dying door leaves each lock's door list and vice versa.
CAPABILITIES(/obj/machinery/door/blast/puzzle)
	// the puzzle door answers to its locks: its own touch and its own item use replace the blast door's open, close, pry and swallow
	without("doors.open")
	without("doors.close")
	without("pry")
	without("pry_broken")
	op("touch", hand(), ungated(), label("Open"), then(PROC_REF(interaction_touch)))
	op("use", item(/obj/item), stance(I_HELP, I_DISARM, I_GRAB), label("Use"), then(PROC_REF(interaction_use)))
	op("puzzle_strike", item(/obj/item), stance(I_HURT), label("Strike"), then(PROC_REF(interaction_strike)))

/// Old attack_hand (never called ..()): try the puzzle door's locks.
/obj/machinery/door/blast/puzzle/proc/interaction_touch(datum/act/op/A)
	var/mob/user = A.actor
	if(check_locks())
		force_toggle(1, user)
	else
		to_chat(user, span_notice("\The [src] does not respond to your touch."))
	return OP_OK

/// Old attackby: pry it (only the locks open it), hit it, or lose a plastique to it.
/obj/machinery/door/blast/puzzle/proc/interaction_use(datum/act/op/A)
	return puzzle_item_used(A, FALSE)

/// Combat mode: a strike leaves no mark (a broken door still pries).
/obj/machinery/door/blast/puzzle/proc/interaction_strike(datum/act/op/A)
	return puzzle_item_used(A, TRUE)

/obj/machinery/door/blast/puzzle/proc/puzzle_item_used(datum/act/op/A, harming)
	var/mob/user = A.actor
	var/obj/item/C = A.held
	if(C.pry == 1 && (!harming || (broken_now())))
		if(istype(C,/obj/item/material/twohanded/fireaxe))
			var/obj/item/material/twohanded/fireaxe/F = C
			if(!F.wielded)
				to_chat(user, span_warning("You need to be wielding \the [F] to do that."))
				return OP_OK

		if(check_locks())
			force_toggle(1, user)

		else
			to_chat(user, span_notice("[src]'s arcane workings resist your effort."))
		return OP_OK

	else if(src.density && harming)
		var/obj/item/W = C
		user.setClickCooldown(user.get_attack_speed(W))
		if(W.obj_damage_type())
			user.do_attack_animation(src)
			act_message(user, src, others = span_danger("%U% hits %T% with %I% with no visible effect."), item = W)

	else if(istype(C, /obj/item/plastique))
		to_chat(user, span_danger("On contacting \the [src], a flash of light envelops \the [C] as it is turned to ash. Oh."))
		consume(C, user)
		return OP_OK
	return OP_OK

/obj/machinery/door/blast/puzzle/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	if(check_locks())
		force_toggle(1, user)
	return OP_OK

/obj/machinery/door/blast/puzzle/attack_alien(mob/user)
	if(check_locks())
		force_toggle(1, user)

