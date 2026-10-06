//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:33

/obj/machinery/containment_field
	// This is an energy field represented as machinery, not a physical machinery shell.
	resistance_flags = INDESTRUCTIBLE
	name = "Containment Field"
	desc = "An energy field."
	icon = 'icons/obj/machines/field_generator.dmi'
	icon_state = "Contain_F"
	anchored = TRUE
	density = FALSE
	unacidable = TRUE
	use_power = USE_POWER_OFF
	light_on = TRUE
	light_range = 2
	light_power = 0.5
	light_color = "#5BA8FF"
	var/tmp/obj/machinery/field_generator/FG1
	var/tmp/obj/machinery/field_generator/FG2
	var/list/shockdirs
	COOLDOWN_DECLARE(hasShocked) //Used to add a delay between shocks. In some cases this used to crash servers by spawning hundreds of sparks every second.

// The containment field (doc/rewrite/final_api.html section 16): an energy field between two field generators (FG1, FG2). It shocks and throws
// whoever touches it or stands beside it (at most every 2 s), destroys any dense object that crosses it, and falls when either generator is
// gone. A singularity cannot step onto it (/obj/singularity/proc/can_move()).
CAPABILITIES(/obj/machinery/containment_field)
	ref_one(nameof(FG1), /obj/machinery/field_generator)
	ref_one(nameof(FG2), /obj/machinery/field_generator)
	op("touch", hand(), when(req_empty_hand()), label("Touch"), ungated(), wait(0), then(PROC_REF(touched)))

/obj/machinery/containment_field/Initialize(mapload)
	. = ..()
	shockdirs = list(turn(dir,90),turn(dir,-90))
	sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))

/obj/machinery/containment_field/set_dir(new_dir)
	. = ..()
	if(.)
		shockdirs = list(turn(dir,90),turn(dir,-90))

// its generators clean up the rest of the field.
/obj/machinery/containment_field/on_destroy(force)
	unsense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))
	if(FG1() && !FG1().clean_up)
		FG1().cleanup()
	if(FG2() && !FG2().clean_up)
		FG2().cleanup()
	..()

/// Whoever touches it is shocked.
/obj/machinery/containment_field/proc/touched(datum/act/op/A)
	shock(A.actor)
	return OP_OK

/obj/machinery/containment_field/Crossed(atom/A)
	if(!istype(A) || A.is_incorporeal())
		return
	if(isliving(A))
		var/mob/living/L = A
		shock(L)
		return
	if(A.density)
		if(istype(A,/obj/machinery/containment_field) || istype(A,/obj/effect) || istype(A,/obj/singularity))
			return
		else
			destroyed(A)

/obj/machinery/containment_field/HasProximity(turf/T, WF, old_loc)
	if(isnull(WF))
		return
	var/atom/movable/AM = WF
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
		return
	if(!isliving(AM) || AM.is_incorporeal())
		return 0
	if(!(get_dir(src,AM) in shockdirs))
		return 0
	if(issilicon(AM) ? prob(40) : prob(50))
		shock(AM)
		return 1
	return 0

/obj/machinery/containment_field/shock(mob/living/user as mob)
	if(!COOLDOWN_FINISHED(src, hasShocked))
		return 0
	if(!FG1() || !FG2())
		spent(src, user)
		return 0
	if(isliving(user))
		COOLDOWN_START(src, hasShocked, 2 SECONDS)
		var/shock_damage = min(rand(30,40),rand(30,40))
		user.electrocute_act(shock_damage, src, 1, BP_TORSO)

		var/atom/target = get_edge_target_turf(user, get_dir(src, get_step_away(user, src)))
		user.throw_at(target, 200, 4)


/obj/machinery/containment_field/proc/set_master(master1,master2)
	if(!master1 || !master2)
		return 0
	rel_set(src, nameof(FG1), master1)
	rel_set(src, nameof(FG2), master2)
	return 1

/// the FG1 this refers to: a relation view, null once that is deleted.
/obj/machinery/containment_field/proc/FG1() as /obj/machinery/field_generator
	return FG1

/// the FG2 this refers to: a relation view, null once that is deleted.
/obj/machinery/containment_field/proc/FG2() as /obj/machinery/field_generator
	return FG2
