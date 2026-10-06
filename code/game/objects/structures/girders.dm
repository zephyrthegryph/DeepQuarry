/obj/structure/girder
	name = "girder"
	icon_state = "girder"
	anchored = TRUE
	density = TRUE
	layer = TABLE_LAYER // moved so that they render above catwalks.
	w_class = ITEMSIZE_HUGE
	var/state = 0
	max_integrity = 200
	var/displaced_health = 50
	var/cover = 50 //how much cover the girder provides against projectiles.
	var/default_material = MAT_STEEL
	var/datum/material/girder_material
	var/datum/material/reinf_material
	var/reinforcing = 0
	var/upgrading = FALSE
	var/applies_material_colour = 1
	var/wall_type = /turf/simulated/wall

/// TRUE while its material needs processing (radioactive or similar); set by set_material().
OM_FIELD(/obj/structure/girder, material_processing, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/structure/girder, PERIODIC_SLOW, "material_processing")

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/structure/girder/proc/build_of(material_key)
	var/our_material = get_material_by_name(material_key)
	if(!our_material)
		spent(src)
		return
	set_material(our_material)

/obj/structure/girder/periodic_step()
	if(!radiate())
		return PROCESS_KILL

/obj/structure/girder/proc/radiate()
	// radioactivity moved to a component on /datum/material.
	var/total_radiation = dq_material_radioactivity(girder_material) + (reinf_material ? dq_material_radioactivity(reinf_material) / 2 : 0)
	if(!total_radiation)
		return FALSE

	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_MEDIUM_INSULATION,
		chance = URANIUM_IRRADIATION_CHANCE,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = total_radiation
	)
	return total_radiation

/obj/structure/girder/proc/set_material(datum/material/new_material)
	girder_material = new_material
	name = "[girder_material.display_name] [initial(name)]"
	max_integrity = round(girder_material.integrity) //Should be 150 with default integrity (steel). Weaker than ye-olden Girders now.
	update_integrity(max_integrity)
	displaced_health = round(max_integrity/4)
	update_rad_insulation()
	if(applies_material_colour)
		color = girder_material.icon_colour
	set_material_processing(girder_material.products_need_process() ? TRUE : FALSE) //Am I radioactive or some other? Process me!

/obj/structure/girder/get_material()
	return girder_material

/obj/structure/girder/draw(datum/look/look)
	..()
	if(anchored)
		look.state(initial(icon_state))
	else
		look.state("displaced")

/// Spawned by the random reinforced-girder mapping spawner.
/obj/structure/girder/reinforced

/obj/structure/girder/displaced
	icon_state = "displaced"
	anchored = FALSE
	cover = 25

/obj/structure/girder/displaced/Initialize(mapload, material_key)
	. = ..()
	displace()

/obj/structure/girder/proc/displace()
	name = "displaced [girder_material.display_name] [initial(name)]"
	icon_state = "displaced"
	set_anchored(FALSE)
	update_integrity(displaced_health)
	cover = 25

/obj/structure/girder/attack_generic(mob/user, damage, attack_message = "smashes apart")
	if(damage < STRUCTURE_MIN_DAMAGE_THRESHOLD)
		return 0
	user.do_attack_animation(src)
	act_message(user, src, others = span_danger("%U% [attack_message] %T%!"))
	after(src, 0.1 SECONDS, PROC_REF(dismantle))
	return 1

/obj/structure/girder/bullet_act(obj/item/projectile/Proj)
	//Girders only provide partial cover. There's a chance that the projectiles will just pass through. (unless you are trying to shoot the girder)
	if(Proj.original() != src && !prob(cover))
		return PROJECTILE_CONTINUE //pass through

	if(!Proj.get_structure_damage())
		return

	. = ..()
	if(!istype(Proj, /obj/item/projectile/beam) || !girder_is_reflective())
		return

	// Reflect lasers: the girder kept its share of the beam in projectile_damage().
	Proj.damage -= Proj.damage * girder_material.reflectivity
	visible_message(span_danger("\The [src] reflects \the [Proj]!"))

	// Find a turf near or on the original location to bounce to
	var/new_x = Proj.starting.x + pick(0, 0, 0, -1, 1, -2, 2)
	var/new_y = Proj.starting.y + pick(0, 0, 0, -1, 1, -2, 2)
	var/turf/curloc = get_step(src, get_dir(src, Proj.starting))

	Proj.penetrating += 1 // Needed for the beam to get out of the girder.

	// redirect the projectile
	Proj.redirect(new_x, new_y, curloc, null)

/obj/structure/girder/proc/girder_is_reflective()
	return girder_material && girder_material.reflectivity >= 0.5

/// Non-beams mostly pass through the frame; a reflective girder keeps only its share of a beam.
/obj/structure/girder/projectile_damage(obj/item/projectile/P, def_zone)
	if(!istype(P, /obj/item/projectile/beam))
		return receive_projectile(P, def_zone, 0.4)
	if(girder_is_reflective())
		return receive_projectile(P, def_zone, girder_material.reflectivity)
	return receive_projectile(P, def_zone)

CAPABILITIES(/obj/structure/girder)
	extend(/datum/act/hit/blob, instead(then(PROC_REF(girder_blob))))
	param(nameof(default_material), pos = 1, apply = PROC_REF(build_of))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("hulk_smash", hand(), label("Smash"), when(req_mutation(HULK)), then(PROC_REF(interaction_hulk_smash)))

/// A blob pulls the girder apart.
/obj/structure/girder/proc/girder_blob(datum/act/hit/blob/A)
	dismantle()
	return TRUE

/obj/structure/girder/proc/reset_girder()
	name = "[girder_material.display_name] [initial(name)]"
	set_anchored(TRUE)
	cover = initial(cover)
	// Rebuild the frame allowance before applying the reinforcement still present.
	max_integrity = round(girder_material.integrity)
	repair_damage(max_integrity)
	state = 0
	icon_state = initial(icon_state)
	reinforcing = 0
	if(reinf_material)
		reinforce_girder()

// Tool steps (secure, dislodge, disassemble, struts): girder_construction.dm.

/// Old attackby: cut/drill apart, reinforce, or build up into a wall.
/obj/structure/girder/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/pickaxe/plasmacutter))
		to_chat(user, span_notice("Now slicing apart the girder..."))
		om_task_timed(user, 3 SECONDS * W.toolspeed, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user))

	else if(istype(W, /obj/item/pickaxe/diamonddrill))
		to_chat(user, span_notice("You drill through the girder!"))
		dismantle()

	else if(istype(W, /obj/item/stack/material))
		if(reinforcing && !reinf_material)
			reinforce_with_material(W, user)
		else
			if(upgrading)
				return OP_OK
			upgrading = TRUE
			if(!construct_wall(W, user))
				upgrading = FALSE
				return OP_OK
			upgrading = FALSE

	return OP_OK

/obj/structure/girder/proc/attackby_timed_done(mob/user)
	if(!src) return
	to_chat(user, span_notice("You slice apart the girder!"))
	dismantle()

// Reaching 0 integrity dismantles the girder back into its material.
/obj/structure/girder/atom_destruction(damage_flag)
	dismantle()
	return ..()

/obj/structure/girder/proc/construct_wall(obj/item/stack/material/S, mob/user)
	var/amount_to_use = reinf_material ? 1 : 2
	var/time_to_reinforce = 4 SECONDS
	if(isrobot(user)) //Robots get a speed boost.
		time_to_reinforce = 1.5 SECONDS
	if(S.get_amount() < amount_to_use)
		to_chat(user, span_notice("There isn't enough material here to construct a wall."))
		return FALSE

	var/datum/material/M = GLOB.name_to_material[S.default_type]
	if(!istype(M))
		return FALSE

	var/wall_fake
	add_hiddenprint(user)

	if(M.integrity < 50)
		to_chat(user, span_notice("This material is too soft for use in wall construction."))
		return FALSE

	to_chat(user, span_notice("You begin adding the plating..."))

	om_task_start(/datum/om/task/timed/girder_construct_wall, user, src, duration = time_to_reinforce, S = S, amount_to_use = amount_to_use, M = M, wall_fake = wall_fake)
	return TRUE

/datum/om/task/timed/girder_construct_wall
	complete_proc = /obj/structure/girder/proc/construct_wall_timed_done
	var/obj/item/stack/material/S
	var/amount_to_use
	var/datum/material/M
	var/wall_fake

/obj/structure/girder/proc/construct_wall_timed_done(datum/om/task/timed/girder_construct_wall/task)
	var/obj/item/stack/material/S = task.S
	var/mob/user = task.actor
	var/amount_to_use = task.amount_to_use
	var/datum/material/M = task.M
	var/wall_fake = task.wall_fake
	if(!S.use(amount_to_use))
		return

	if(anchored)
		to_chat(user, span_notice("You added the plating!"))
	else
		to_chat(user, span_notice("You create a false wall! Push on it to open or close the passage."))
		wall_fake = 1

	var/turf/Tsrc = get_turf(src)
	Tsrc.ChangeTurf(wall_type)
	var/turf/simulated/wall/T = get_turf(src)
	T.set_material(M, reinf_material, girder_material)
	if(wall_fake)
		T.can_open = 1
	T.add_hiddenprint(user)
	spent(src)
	return TRUE

/obj/structure/girder/proc/reinforce_with_material(obj/item/stack/material/S, mob/user) //if the verb is removed this can be renamed.
	if(reinf_material)
		to_chat(user, span_notice("\The [src] is already reinforced."))
		return 0

	if(S.get_amount() < 1)
		to_chat(user, span_notice("There isn't enough material here to reinforce the girder."))
		return 0

	var/datum/material/M = GLOB.name_to_material[S.default_type]
	if(!istype(M) || M.integrity < 50)
		to_chat(user, "You cannot reinforce \the [src] with that; it is too soft.")
		return 0

	to_chat(user, span_notice("Now reinforcing..."))
	om_task_start(/datum/om/task/timed/girder_reinforce_with_material, user, src, S = S, M = M)
	return TRUE

/datum/om/task/timed/girder_reinforce_with_material
	duration = 4 SECONDS
	complete_proc = /obj/structure/girder/proc/reinforce_with_material_timed_done
	var/obj/item/stack/material/S
	var/datum/material/M

/obj/structure/girder/proc/reinforce_with_material_timed_done(datum/om/task/timed/girder_reinforce_with_material/task)
	var/obj/item/stack/material/S = task.S
	var/mob/user = task.actor
	var/datum/material/M = task.M
	if(!S.use(1))
		return
	to_chat(user, span_notice("You added reinforcement!"))

	reinf_material = M
	reinforce_girder()
	return 1

/// Shielding derived from the frame material plus any reinforcement.
/obj/structure/girder/proc/update_rad_insulation()
	var/transmission = girder_material ? girder_material.radiation_transmission(RAD_GIRDER_THICKNESS_MM) : RAD_NO_INSULATION
	if(reinf_material)
		transmission *= reinf_material.radiation_transmission(RAD_GIRDER_REINFORCEMENT_THICKNESS_MM)
	set_rad_insulation(transmission)

/obj/structure/girder/proc/reinforce_girder()
	cover = reinf_material.hardness
	update_rad_insulation()
	var/bonus = round(reinf_material.integrity/2)
	max_integrity += bonus
	repair_damage(bonus)
	state = 2
	icon_state = "reinforced"
	reinforcing = 0

/obj/structure/girder/proc/dismantle()
	girder_material.place_dismantled_product(get_turf(src), 2)
	consume(src)

/// Old attack_hand: a Hulk smashes the girder apart.
/obj/structure/girder/proc/interaction_hulk_smash(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_danger("%U% smashes %T% apart!"))
	dismantle()
	return OP_OK

/obj/structure/girder/cult
	name = "column"
	icon= 'icons/obj/cult.dmi'
	icon_state= "cultgirder"
	max_integrity = 250
	cover = 70
	girder_material = "cult"
	applies_material_colour = 0

/obj/structure/girder/cult/draw(datum/look/look)
	..()
	if(anchored)
		look.state("cultgirder")
	else
		look.state("displaced")

/obj/structure/girder/cult/dismantle()
	replace_with(src, /obj/effect/decal/remains/human)

/// Overrides girder's interaction_item(): a cult girder just slices/drills apart, no reinforcing.
/obj/structure/girder/cult/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/pickaxe/plasmacutter))
		to_chat(user, span_notice("Now slicing apart the girder..."))
		om_task_timed(user, 3 SECONDS * W.toolspeed, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done2), done_args = list(user))
	else if(istype(W, /obj/item/pickaxe/diamonddrill))
		to_chat(user, span_notice("You drill through the girder!"))
		new /obj/effect/decal/remains/human(get_turf(src))
		dismantle()
	return OP_OK

/obj/structure/girder/cult/proc/attackby_timed_done2(mob/user)
	to_chat(user, span_notice("You slice apart the girder!"))
	dismantle()

/obj/structure/girder/resin
	name = "soft girder"
	icon_state = "girder_resin"
	max_integrity = 225
	cover = 60
	girder_material = MAT_RESIN

/obj/structure/girder/bay
	wall_type = /turf/simulated/wall/bay

/obj/structure/girder/eris
	wall_type = /turf/simulated/wall/eris
