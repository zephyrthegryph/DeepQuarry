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
	qdel(Proj) //No piercing. No.

/obj/machinery/door/blast/puzzle/Initialize(mapload)
	. = ..()
	implicit_material = get_material_by_name(MAT_ALIEN_DUNGEON)
	if(length(locks))
		return
	var/check_range = world.view * checkrange_mult
	for(var/obj/structure/prop/lock/L in orange(src, check_range))
		if(L.lockID == lockID)
			LAZYOR(L.linked_objects, src)
			LAZYOR(locks, L)

/obj/machinery/door/blast/puzzle/Destroy()
	if(length(locks))
		for(var/obj/structure/prop/lock/L in locks)
			LAZYREMOVE(L.linked_objects, src)
			LAZYREMOVE(locks, L)
	. = ..()

/obj/machinery/door/blast/puzzle/attack_hand(mob/user as mob)
	if(check_locks())
		force_toggle(1, user)
	else
		to_chat(user, span_notice("\The [src] does not respond to your touch."))

/obj/machinery/door/blast/puzzle/attackby(obj/item/C as obj, mob/user as mob)
	if(istype(C, /obj/item))
		if(C.pry == 1 && (!IS_HARMING(user) || (stat & BROKEN)))
			if(istype(C,/obj/item/material/twohanded/fireaxe))
				var/obj/item/material/twohanded/fireaxe/F = C
				if(!F.wielded)
					to_chat(user, span_warning("You need to be wielding \the [F] to do that."))
					return

			if(check_locks())
				force_toggle(1, user)

			else
				to_chat(user, span_notice("[src]'s arcane workings resist your effort."))
			return

		else if(src.density && (IS_HARMING(user)))
			var/obj/item/W = C
			user.setClickCooldown(user.get_attack_speed(W))
			if(W.obj_damage_type())
				user.do_attack_animation(src)
				user.visible_message(span_danger("\The [user] hits \the [src] with \the [W] with no visible effect."))

		else if(istype(C, /obj/item/plastique))
			to_chat(user, span_danger("On contacting \the [src], a flash of light envelops \the [C] as it is turned to ash. Oh."))
			qdel(C)
			return 0

/obj/machinery/door/blast/puzzle/attack_generic(mob/user, damage)
	if(check_locks())
		force_toggle(1, user)

/obj/machinery/door/blast/puzzle/attack_alien(mob/user)
	if(check_locks())
		force_toggle(1, user)

