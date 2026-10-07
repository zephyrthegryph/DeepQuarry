/obj/structure/grille
	name = "grille"
	desc = "A flimsy lattice of metal rods, with screws to secure it to the floor."
	icon = 'icons/obj/structures.dmi'
	icon_state = "grille"
	density = TRUE
	anchored = TRUE
	pressure_resistance = 5*ONE_ATMOSPHERE
	layer = TABLE_LAYER
	explosion_resistance = 1
	// 16 integrity with a 6-point "broken" buffer: 10 damage to break it into a passable
	// stub (integrity_failure), then 6 more to clear it entirely (atom_destruction).
	max_integrity = 16
	integrity_failure = 0.375
	var/destroyed = FALSE

/// The look (the draw sweep: from its template).
/obj/structure/grille/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][destroyed ? "-b" : ""]")

CAPABILITIES(/obj/structure/grille)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	extend(/datum/act/hit/blob, instead(then(PROC_REF(blob_destroys))))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	op("hand", hand(), label("Kick"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// A blob's hit destroys the grille outright.
/obj/structure/grille/proc/blob_destroys(datum/act/hit/blob/A)
	destroyed(src)
	return OP_OK

/// Something walked into it (the bump action's notice).
/obj/structure/grille/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/user = N.bumper
	if(ismob(user)) shock(user, 70)

/obj/structure/grille/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor

	user.setClickCooldown(user.get_attack_speed())
	play_sfx(src, SFX_EFFECTS_GRILLEHIT, 1.6)
	user.do_attack_animation(src)

	var/damage_dealt = 1
	var/attack_message = "kicks"
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.species.can_shred(H, FALSE, 10))
			attack_message = "mangles"
			damage_dealt = 5

	if(shock(user, 70))
		return TRUE

	if(user.has_mutation(HULK))
		damage_dealt += 5
	else
		damage_dealt += 1

	generic_hit(src, user, damage_dealt, attack_message)
	return TRUE

/obj/structure/grille/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGRILLE))
		return TRUE
	if(istype(mover, /obj/item/projectile))
		return prob(30)
	return !density

/obj/structure/grille/bullet_act(obj/item/projectile/Proj)
	if(!Proj)	return

	//Flimsy grilles aren't so great at stopping projectiles. However they can absorb some of the impact
	var/damage = Proj.get_structure_damage()
	var/passthrough = FALSE

	if(!damage) return

	//20% chance that the grille provides a bit more cover than usual. Support structure for example might take up 20% of the grille's area.
	//If they click on the grille itself then we assume they are aiming at the grille itself and the extra cover behaviour is always used.
	switch(Proj.obj_damage_type())
		if(BRUTE)
			//bullets
			if(Proj.original() == src || prob(20))
				Proj.damage *= between(0, Proj.damage/60, 0.5)
				if(prob(max((damage-10)/25, 0))*100)
					passthrough = TRUE
			else
				Proj.damage *= between(0, Proj.damage/60, 1)
				passthrough = TRUE
		if(BURN)
			//beams and other projectiles are either blocked completely by grilles or stop half the damage.
			if(!(Proj.original() == src || prob(20)))
				Proj.damage *= 0.5
				passthrough = TRUE

	if(passthrough)
		. = PROJECTILE_CONTINUE
		damage = between(0, (damage - Proj.damage)*(Proj.obj_damage_type() == BRUTE? 0.4 : 1), 10) //if the bullet passes through then the grille avoids most of the damage

	if(damage > 0)
		var/datum/damage_packet/packet = damage_packet(Proj, Proj.firer, null, null, DAMAGE_PACKET_PROJECTILE, Proj.armor_penetration, Proj.dir)
		receive_split(packet, Proj.injury_kind, Proj.injury_kinds, damage * 0.2)

/obj/structure/grille/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/rcd)) // To stop us from hitting the grille when building windows, because grilles don't let parent handle it properly.
		return TRUE
	//window placing begin //TODO CONVERT PROPERLY TO MATERIAL DATUM
	else if(istype(W,/obj/item/stack/material))
		var/obj/item/stack/material/ST = W
		if(!ST.material.created_window)
			return TRUE

		var/dir_to_set = 1
		if(loc == user.loc)
			dir_to_set = user.dir
		else
			if( ( x == user.x ) || (y == user.y) ) //Only supposed to work for GLOB.cardinal directions.
				if( x == user.x )
					if( y > user.y )
						dir_to_set = 2
					else
						dir_to_set = 1
				else if( y == user.y )
					if( x > user.x )
						dir_to_set = 8
					else
						dir_to_set = 4
			else
				to_chat(user, span_notice("You can't reach."))
				return TRUE //Only works for GLOB.cardinal direcitons, diagonals aren't supposed to work like this.
		for(var/obj/structure/window/WINDOW in contents_of(loc))
			if(WINDOW.dir == dir_to_set)
				to_chat(user, span_notice("There is already a window facing this way there."))
				return TRUE
		to_chat(user, span_notice("You start placing the window."))
		task_start(/datum/task/timed/grille_attackby, user, src, ST = ST, dir_to_set = dir_to_set)
		return TRUE

//window placing end

	else if((W.flags & NOCONDUCT) || !shock(user, 70))
		user.setClickCooldown(user.get_attack_speed(W))
		user.do_attack_animation(src)
		play_sfx(src, SFX_EFFECTS_GRILLEHIT, 1.6)
		switch(W.obj_damage_type())
			if(BURN)
				receive_weapon_hit(W, user, W.force, INJURY_BURN)
			if(BRUTE)
				receive_weapon_hit(W, user, W.force * 0.1)
	return TRUE

/datum/task/timed/grille_attackby
	duration = 2 SECONDS
	complete_proc = /obj/structure/grille/proc/attackby_timed_done
	var/obj/item/stack/material/ST
	var/dir_to_set

/obj/structure/grille/proc/attackby_timed_done(datum/task/timed/grille_attackby/task)
	var/mob/user = task.actor
	var/obj/item/stack/material/ST = task.ST
	var/dir_to_set = task.dir_to_set
	for(var/obj/structure/window/WINDOW in contents_of(loc))
		if(WINDOW.dir == dir_to_set)//checking this for a 2nd time to check if a window was made while we were waiting.
			to_chat(user, span_notice("There is already a window facing this way there."))
			return

	var/wtype = ST.material.created_window
	if (ST.use(1))
		var/obj/structure/window/WD = new wtype(loc, dir_to_set, 1)
		to_chat(user, span_notice("You place the [WD] on [src]."))
		WD.update_icon()

// Crossing the integrity_failure threshold turns the grille into a passable broken stub.
/obj/structure/grille/atom_break(damage_flag)
	. = ..()
	if(!destroyed)
		set_density(FALSE)
		destroyed = TRUE
		changed(src)
		new /obj/item/stack/rods(get_turf(src))

// Reaching 0 integrity clears the grille entirely, dropping its last rod.
/obj/structure/grille/atom_destruction(damage_flag)
	new /obj/item/stack/rods(get_turf(src))
	return ..()

/obj/structure/grille/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!shock(user, 100))
		playsound(src, W.usesound, 100, 1)
		replace_with(src, /obj/item/stack/rods, destroyed ? 1 : 2)
	return OP_OK

/obj/structure/grille/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!istype(loc, /turf/simulated) && !anchored)
		return OP_OK
	if(!shock(user, 90))
		playsound(src, W.usesound, 100, 1)
		set_anchored(!anchored)
		act_message(user, null, MSG_SELF(span_notice("You have [anchored ? "fastened the grille to" : "unfastened the grille from"] the floor.")), \
			MSG_OTHERS(span_notice("%U% [anchored ? "fastens" : "unfastens"] the grille.")))
	return OP_OK

// shock user with probability prb (if all connections & power are working)
// returns 1 if shocked, 0 otherwise

/obj/structure/grille/proc/shock(mob/user as mob, prb)

	if(!anchored || destroyed)		// anchored/destroyed grilles are never connected
		return 0
	if(!prob(prb))
		return 0
	if(!in_range(src, user))//To prevent TK and mech users from getting shocked
		return 0
	var/turf/T = get_turf(src)
	var/obj/structure/cable/C = T.get_cable_node()
	if(C)
		if(electrocute_mob(user, C, src))
			power_warn(C.get_power_region())
			fx_sparks(src, 3)
			if(user.has_status(STAT_STUNNED))
				return 1
		else
			return 0
	return 0


/obj/structure/grille/attack_generic(mob/user, damage, attack_verb)
	act_message(user, src, others = span_danger("%U% [attack_verb] %T%!"))
	user.do_attack_animation(src)
	receive_generic_attack(user, damage)
	return 1

// Used in mapping to avoid
/obj/structure/grille/broken
	destroyed = TRUE
	icon_state = "grille-b"
	density = FALSE

/obj/structure/grille/broken/Initialize(mapload)
	. = ..()
	update_integrity(rand(1, 5)) //In the broken-but-not-cleared band (below integrity_failure).
	atom_break() //Drop into the passable broken stub state.

/obj/structure/grille/cult
	name = "cult grille"
	desc = "A matrice built out of an unknown material, with some sort of force field blocking air around it."
	icon_state = "grillecult"
	max_integrity = 46 // Strong enough to avoid people breaking in too easily (40 + 6 broken buffer).
	integrity_failure = 0.13
	can_atmos_pass = ATMOS_PASS_NO // Make sure air doesn't drain.

/obj/structure/grille/broken/cult
	icon_state = "grillecult-b"

/obj/structure/grille/rustic
	name = "rustic grille"
	desc = "A lattice of metal, arranged in an old, rustic fashion."
	icon_state = "grillerustic"

/obj/structure/grille/broken/rustic
	icon_state = "grillerustic-b"

/obj/structure/grille/occult_act(mob/living/user)
	replace_with(src, /obj/structure/grille/cult)
	return TRUE
