////////////////////////////////////////
// Vars and Default tesla_act behavior
////////////////////////////////////////

/obj/proc/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	being_shocked = TRUE
	var/power_bounced = power / 2
	tesla_zap(src, zap_range = 3, power = power_bounced, explosive = explosive, current_jumps = current_jumps)
	after(src, 1 SECOND, TYPE_PROC_REF(/obj, reset_shocked))

/obj/proc/reset_shocked()
	being_shocked = FALSE

// Overrides for behavior on specific types

/obj/structure/blob/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	..()
	adjust_integrity(-power/400)

/obj/machinery/nuclearbomb/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	..()
	if(explosive)
		// ALLOW(lifecycle): the tesla destroys the bomb so it cannot blow up again
		qdel(src)//like the singulo, tesla deletes it. stops it from exploding over and over

/obj/machinery/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	..()
	if(prob(85) && explosive)
		explosion(loc, 0, 2, 4, /*flame_range = 2,*/ adminlog = FALSE/*smoke = FALSE*/) // No devastation range
	else if(prob(50))
		emp_act(EMP_MEDIUM)
	else
		ex_act(2)

/obj/machinery/camera/tesla_act(power, explosive = FALSE, current_jumps = current_jumps) //EMP proof upgrade also makes it tesla immune
	if(isEmpProof())
		return
	..()
	// ALLOW(lifecycle): the tesla destroys the camera so it cannot blow up again
	qdel(src) //to prevent bomb testing camera from exploding over and over forever

/obj/machinery/light/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	if(explosive)
		explosion(loc, 0, 0, 0/*flame_range = 5*/, adminlog = FALSE)
		// ALLOW(lifecycle): the tesla bursts the light
		qdel(src)
		return
	set_on(TRUE)
	broken()

/obj/structure/closet/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	..() //extend the zap
	visible_message(span_danger("[src] is blown apart by the bolt of electricity!"), span_danger("You hear a metallic screeching sound."))
	dump_contents()
	// ALLOW(lifecycle): the tesla blows the closet apart
	qdel(src)

/obj/structure/reagent_dispensers/fueltank/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	..() //extend the zap
	explode()

/obj/mecha/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	..()
	take_damage(power / 200, "energy") // A surface lightning strike will do 100 damage.

/obj/structure/flora/tree/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	adjust_health(-power / 100, TRUE) // Kills most trees in one lightning strike.
	..()

/obj/machinery/gravity_generator/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	..()
	// ALLOW(lifecycle): the tesla destroys the generator part so it cannot blow up again
	qdel(src)//like the singulo, tesla deletes it. stops it from exploding over and over

/obj/machinery/power/rtg/abductor/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	..() //extend the zap
	asplod()

/obj/machinery/power/rtg/kugelblitz/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	..() //extend the zap
	asplod()

/obj/machinery/power/rtg/antimatter_core/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	..() //extend the zap
	asplod()

/obj/machinery/the_singularitygen/tesla/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	if(explosive)
		set_energy(energy + power)

/obj/machinery/power/tesla_coil/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	if(anchored && !panel_open)
		being_shocked = TRUE
		coil_act(power, explosive, current_jumps)
		after(src, zap_cooldown, TYPE_PROC_REF(/obj, reset_shocked))
	else if(anchored && panel_open) //Doing maintenance. Just act like a grounding rod.
		being_shocked = TRUE
		after(src, zap_cooldown, TYPE_PROC_REF(/obj, reset_shocked))
	else
		..()

/obj/machinery/power/grounding_rod/tesla_act(power, explosive = FALSE, current_jumps = current_jumps)
	if(anchored && !panel_open)
		flick("grounding_rodhit", src)
	else
		..()
