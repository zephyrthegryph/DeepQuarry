/obj/structure/droppod_door
	name = "pod door"
	desc = "A drop pod door. Opens rapidly using explosive bolts."
	icon = 'icons/obj/structures.dmi'
	icon_state = "droppod_door_closed"
	anchored = TRUE
	density = TRUE
	opacity = 1
	layer = TURF_LAYER + 0.1
	var/deploying
	var/deployed

/// A door that opens by itself after landing (its constructor param).
/obj/structure/droppod_door/var/autoopen = FALSE

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/structure/droppod_door/proc/arm_autoopen(opens)
	if(opens)
		after(src, 10 SECONDS, PROC_REF(deploy))

/// Old attack_ai: an adjacent silicon opens it as by hand.
/obj/structure/droppod_door/proc/droppod_door_silicon_use(datum/act/op/A)
	var/mob/user = A.actor
	if(user.Adjacent(src))
		attack_hand(user)
	return TRUE

CAPABILITIES(/obj/structure/droppod_door)
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	param(nameof(autoopen), pos = 1, apply = PROC_REF(arm_autoopen))
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("droppod_door_silicon_use", remote(), label("Open"), then(PROC_REF(droppod_door_silicon_use)))

/// A simple mob's (or a xeno's) generic hit on it, taken over (the hit/generic action): HOOK_DECLINE lets the default generic attack land.
/obj/structure/droppod_door/proc/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	attack_hand(user)
	return OP_OK

/// Old attack_hand.
/obj/structure/droppod_door/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(deploying) return TRUE
	deploying = TRUE
	to_chat(user, span_danger("You prime the explosive bolts. Better get clear!"))
	after(src, 3 SECONDS, PROC_REF(deploy))
	return TRUE

/obj/structure/droppod_door/proc/deploy()
	if(deployed)
		return

	deploying = FALSE
	deployed = TRUE
	visible_message(span_danger("The explosive bolts on \the [src] detonate, throwing it open!"))
	play_sfx(src, SFX_EFFECTS_BANG, extrarange = 5)

	// This is shit but it will do for the sake of testing.
	for(var/obj/structure/droppod_door/D in orange(1,src))
		if(D.deployed)
			continue
		D.deploy()

	// Overwrite turfs.
	var/turf/origin = get_turf(src)
	origin.ChangeTurf(/turf/simulated/floor/reinforced)
	origin.set_light(0) // Forcing updates
	var/turf/T = get_step(origin, src.dir)
	T.ChangeTurf(/turf/simulated/floor/reinforced)
	T.set_light(0) // Forcing updates

	// Destroy turf contents.
	for(var/obj/O in turf_contents_of_type(origin, /obj))
		if(!O.simulated)
			continue
		spent(O) //crunch
	for(var/obj/O in turf_contents_of_type(T, /obj))
		if(!O.simulated)
			continue
		spent(O) //crunch

	// Hurl the mobs away.
	for(var/mob/living/M in turf_contents_of_type(T, /mob/living))
		M.throw_at(get_edge_target_turf(T,src.dir),rand(0,3),50)
	for(var/mob/living/M in turf_contents_of_type(origin, /mob/living))
		M.throw_at(get_edge_target_turf(origin,src.dir),rand(0,3),50)

	// Create a decorative ramp bottom and flatten out our current ramp.
	set_density(FALSE)
	set_opacity(0)
	icon_state = "ramptop"
	var/obj/structure/droppod_door/door_bottom = new(T)
	door_bottom.deployed = TRUE
	door_bottom.set_density(FALSE)
	door_bottom.set_opacity(0)
	door_bottom.set_dir(src.dir)
	door_bottom.icon_state = "rampbottom"
