/datum/technomancer/spell/apportation
	name = "Apportation"
	desc = "This allows you to teleport objects into your hand, or to pull people towards you.  If they're close enough, the function \
	will grab them automatically."
	enhancement_desc = "Range is unlimited."
	cost = 25
	obj_path = /obj/item/spell/apportation
	category = UTILITY_SPELLS

/obj/item/spell/apportation
	name = "apportation"
	icon_state = "apportation"
	desc = "Allows you to reach through Bluespace with your hand, and grab something, bringing it to you instantly."
	cast_methods = CAST_RANGED
	aspect = ASPECT_TELE

/obj/item/spell/apportation/on_ranged_cast(atom/hit_atom, mob/user)
	if(istype(hit_atom, /atom/movable))
		var/atom/movable/AM = hit_atom

		if(!AM.loc) //Don't teleport HUD telements to us.
			return
		if(AM.anchored)
			to_chat(user, span_warning("\The [hit_atom] is firmly secured and anchored, you can't move it!"))
			return

		if(!within_range(hit_atom) && !check_for_scepter())
			to_chat(user, span_warning("\The [hit_atom] is too far away."))
			return

		//Teleporting an item.
		if(istype(hit_atom, /obj/item))
			var/obj/item/I = hit_atom

			fx_sparks(user, 2)
			fx_sparks(I, 2)
			I.visible_message(span_danger("\The [I] vanishes into thin air!"))
			I.forceMove(get_turf(user))
			user.drop_item(src)
			src.moveToNullspace()
			user.put_in_hands(I)
			act_message(user, null, others = span_notice("\A [I] appears in %U%'s hand!"))
			add_attack_logs(user,I,"Stolen with [src]")
			consume(src, user)
		//Now let's try to teleport a living mob.
		else if(isliving(hit_atom))
			var/mob/living/L = hit_atom
			to_chat(L, span_danger("You are teleported towards \the [user]."))
			fx_sparks(user, 2)
			fx_sparks(L, 2)
			L.throw_at(get_step(get_turf(src),get_turf(L)), 4, 1, src)
			user.drop_item(src)
			src.moveToNullspace()
			after(src, 1 SECOND, PROC_REF(finish_apportation_grab), with = list(user, L))

/obj/item/spell/apportation/proc/finish_apportation_grab(mob/living/user, mob/living/L)
	if(QDELETED(user) || QDELETED(L) || !user.Adjacent(L))
		to_chat(user, span_warning("\The [L] is out of your reach."))
		consume(src, user)
		return

	L.status_at_least(STAT_WEAKENED, 3)
	act_message(user, L, others = span_warning(span_bold("%U%") + " seizes %T%!"))

	var/obj/item/grab/G = new(user, L)

	user.put_in_hands(G)

	G.state = GRAB_PASSIVE
	G.icon_state = "grabbed1"
	G.synch()
	consume(src, user)
