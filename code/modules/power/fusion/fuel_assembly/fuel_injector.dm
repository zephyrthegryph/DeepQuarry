
/obj/machinery/fusion_fuel_injector
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	name = "fuel injector"
	icon = 'icons/obj/machines/power/fusion.dmi'
	icon_state = "injector0"
	density = TRUE
	anchored = FALSE
	req_access = list(ACCESS_ENGINE)
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 500

	circuit = /obj/item/circuitboard/fusion_injector

	var/fuel_usage = 30
	var/id_tag
	var/obj/item/fuel_assembly/cur_assembly

	/// It is firing its rod into the field (its console's switch).
	var/injecting = FALSE

TRACKED(/obj/machinery/fusion_fuel_injector, injecting)

MSG_DEF_SELF(fuel_injector/running, "Shut it off before playing with the fuel rod.")
MSG_DEF_SELF(fuel_injector/no_rod, "There is no fuel rod in it.")
MSG_DEF(fuel_injector/rod_in, "You insert %I% into %T%.", "%U% inserts %I% into %T%.")

// The fuel injector (doc/rewrite/final_api.html section 16): a fuel rod in, switched on by its console, it fires one particle per fuel in
// the rod every machine service interval (inject_step()) and burns fuel_usage of each. Its rod is its own; the rod and its parts are worked
// only while it is off. A blitz rod asks first, and shakes it apart.
TRACKED(/obj/machinery/fusion_fuel_injector, id_tag)

CAPABILITIES(/obj/machinery/fusion_fuel_injector)
	registry(REGISTRY_FUEL_INJECTORS, key = nameof(id_tag))
	rotatable()
	owns_one(nameof(cur_assembly), /obj/item/fuel_assembly, on_destroy = ON_DESTROY_SPILL)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(inject_step)), when = nameof(injecting))
	part_replacement()
	extend("part_replacement.replace", needs(req_is(nameof(injecting), FALSE, because = MSG(fuel_injector/running))))
	op("set_id", tool(TOOL_MULTITOOL), label("Set ident tag"), wait(0),
		asks(/datum/prompt/text, fields = list("title" = "Fuel Injector", "question" = "Enter a new ident tag.", "default" = nameof(id_tag), "max_len" = MAX_NAME_LEN)),
		then(PROC_REF(ident_entered)))
	op("insert", item(/obj/item/fuel_assembly), label("Insert fuel rod"), wait(0), when(cond_not(req(/obj/item/fuel_assembly/blitz))),
		needs(req_is(nameof(injecting), FALSE, because = MSG(fuel_injector/running))), then(PROC_REF(rod_inserted)))
	op("insert_blitz", item(/obj/item/fuel_assembly/blitz), label("Insert fuel rod"), wait(0),
		needs(req_is(nameof(injecting), FALSE, because = MSG(fuel_injector/running))),
		confirms("Are you sure you want to put the blitz rod in the fuel injector? This definitely wasn't meant to be used like this, and could only end badly."),
		then(PROC_REF(blitz_inserted)))
	op("take", hand(), when(req_empty_hand()), label("Take fuel rod"), ungated(), wait(0),
		needs(req_is(nameof(injecting), FALSE, because = MSG(fuel_injector/running)), req_is(nameof(cur_assembly), TRUE, because = MSG(fuel_injector/no_rod))),
		then(PROC_REF(rod_taken)))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(crowbar_used)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(screwdriver_used)))

/obj/machinery/fusion_fuel_injector/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/fusion_fuel_injector/mapped
	anchored = TRUE

/// One step while it injects: it stops when it cannot work, else it fires.
/obj/machinery/fusion_fuel_injector/proc/inject_step(datum/act/timer/A)
	if(!operable())
		StopInjecting()
		return
	Inject()

/obj/machinery/fusion_fuel_injector/proc/ident_entered(datum/act/op/A)
	var/datum/prompt/text/answer = A.answer
	if(answer?.value && A.actor?.Adjacent(src))
		set_id_tag(answer.value)
	return OP_OK

/obj/machinery/fusion_fuel_injector/proc/rod_inserted(datum/act/op/A)
	return swap_rod(A.actor, A.held)

/obj/machinery/fusion_fuel_injector/proc/blitz_inserted(datum/act/op/A)
	. = swap_rod(A.actor, A.held)
	if(cur_assembly == A.held)
		visible_message(span_warning("The fuel injector begins to shake and whirr violently as it tries to accept the blitz rod!"))
		after(src, 3 SECONDS, PROC_REF(blitz_boom))

/// The held rod goes in; the one it held comes out into the actor's hands.
/obj/machinery/fusion_fuel_injector/proc/swap_rod(mob/user, obj/item/fuel_assembly/held)
	if(cur_assembly)
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " swaps %T%'s [cur_assembly] for \a [held]."))
	else
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " inserts \a [held] into %T%."))
	var/obj/item/fuel_assembly/old_assembly = rel_take(src, nameof(cur_assembly))
	if(!move_into(src, nameof(cur_assembly), held, user))
		rel_set(src, nameof(cur_assembly), old_assembly)
		return OP_OK
	if(old_assembly)
		old_assembly.forceMove(get_turf(src))
		user.put_in_hands(old_assembly)
	return OP_OK

/obj/machinery/fusion_fuel_injector/proc/rod_taken(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/fuel_assembly/removed = rel_take(src, nameof(cur_assembly))
	removed.forceMove(get_turf(src))
	user.put_in_hands(removed)
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " removes \the [removed] from %T%."))
	return OP_OK

/obj/machinery/fusion_fuel_injector/proc/maintenance_available(mob/user)
	if(!injecting)
		return TRUE
	to_chat(user, span_warning("Shut \the [src] off first!"))
	return FALSE

/obj/machinery/fusion_fuel_injector/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!maintenance_available(user))
		return OP_OK
	return OP_DECLINE

/obj/machinery/fusion_fuel_injector/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!maintenance_available(user))
		return OP_OK
	return OP_DECLINE

/obj/machinery/fusion_fuel_injector/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!maintenance_available(user))
		return OP_OK
	return OP_DECLINE

/obj/machinery/fusion_fuel_injector/proc/BeginInjecting()
	if(!injecting && cur_assembly)
		icon_state = "injector1"
		set_injecting(TRUE)
		set_use_power(USE_POWER_IDLE)

/obj/machinery/fusion_fuel_injector/proc/StopInjecting()
	if(injecting)
		set_injecting(FALSE)
		icon_state = "injector0"
		set_use_power(USE_POWER_OFF)

/obj/machinery/fusion_fuel_injector/proc/Inject()
	if(!injecting)
		return
	if(cur_assembly)
		var/amount_left = 0
		for(var/reagent in cur_assembly.rod_quantities)
			if(cur_assembly.rod_quantities[reagent] > 0)
				var/numparticles = fuel_usage
				if(numparticles < 1)
					numparticles = 1
				var/obj/effect/accelerated_particle/A = new/obj/effect/accelerated_particle(get_turf(src), dir)
				A.particle_type = reagent
				A.additional_particles = numparticles - 1
				if(cur_assembly)
					cur_assembly.rod_quantities[reagent] -= fuel_usage
					amount_left += cur_assembly.rod_quantities[reagent]
		if(cur_assembly)
			cur_assembly.percent_depleted = amount_left / cur_assembly.initial_amount
		flick("injector-emitting",src)
	else
		StopInjecting()

/obj/machinery/fusion_fuel_injector/proc/blitz_boom()
	explosion(loc,2,3,4,8)
	spent(src)
