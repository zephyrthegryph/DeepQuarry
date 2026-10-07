GLOBAL_VAR_INIT(Recycled_Items, 0)

/obj/machinery/v_garbosystem
	icon = 'icons/obj/machines/other.dmi'
	icon_state = "cronchy_off"
	name = "garbage grinder"
	desc = "Mind your fingers. Filter access hatch can be opened with crowbar to release trapped contents within."
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER
	anchored = TRUE
	idle_power_usage = 5
	active_power_usage = 100
	var/tmp/obj/machinery/recycling/crusher/crusher	//Connects to regular crusher
	var/tmp/obj/machinery/button/garbosystem/button
	var/list/affecting
	var/voracity = 5 //How much stuff is swallowed at once.

/obj/machinery/v_garbosystem/var/operating = FALSE
TRACKED(/obj/machinery/v_garbosystem, operating)
/// Grinds what sits on it every frame while operating and operable.
/obj/machinery/v_garbosystem/Initialize(mapload)
	. = ..()
	add_hose_connector(/datum/hose_connector/output)
	for(var/dir in GLOB.cardinal)
		rel_set(src, nameof(crusher), locate(/obj/machinery/recycling/crusher, get_step(src, dir)))
		if(src.crusher())
			crusher().hand_fed = FALSE
			break
	for(var/dir in GLOB.cardinal)
		rel_set(src, nameof(button), locate(/obj/machinery/button/garbosystem, get_step(src, dir)))
		if(src.button())
			rel_set(button(), nameof(/obj/machinery/button/garbosystem::grinder), src)
			break
	return

/obj/machinery/v_garbosystem/examine(mob/user, infix, suffix)
	. = ..()
	. += span_infoplain("The internal fluid tank reads: [reagents.total_volume]/[reagents.maximum_volume]")
	if(contents_count(src) || has_latent()) // ALLOW(latent): latent entries checked
		. += span_warning("There are items in the filter's trap!")

/// Old attack_hand: never called ..().
/obj/machinery/v_garbosystem/proc/interaction_toggle(datum/act/op/A)
	set_operating(!operating)
	update()
	return OP_OK

/obj/machinery/v_garbosystem/power_change()
	if((. = ..()))
		update()

/obj/machinery/v_garbosystem/proc/update()
	if(!operable())
		set_operating(FALSE)
		icon_state = "cronchy_off"
		set_use_power(USE_POWER_OFF)
		return
	if(!operating)
		icon_state = "cronchy_off"
		set_use_power(USE_POWER_OFF)
		return
	icon_state = "cronchy_active"
	set_use_power(USE_POWER_ACTIVE)

// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/v_garbosystem)
	reagents(CARGOTANKER_VOLUME * 2)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(operating), gate = PROC_REF(operable), wakes_on = list(nameof(operating), STAT_OPERABLE))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	op("v_garbosystem_toggle", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), then(PROC_REF(interaction_toggle)))
	op("v_garbosystem_crowbar_open", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), label("Open filter hatch"), wait(0), then(PROC_REF(interaction_crowbar_open)))

/obj/machinery/v_garbosystem/proc/work_step(datum/act/timer/A)
	if(!crusher() || (crusher().power_lost() || crusher().broken_now()))
		icon_state = "cronchy_off"
		return PROCESS_KILL
	icon_state = "cronchy_active"

	affecting = loc.contents - src
	after(src, 0.1 SECONDS, PROC_REF(grind_affecting))

/obj/machinery/v_garbosystem/proc/on_emag(datum/act/op/A)
	set_emagged(!emagged)
	update()
	return OP_OK

/obj/machinery/v_garbosystem/proc/interaction_crowbar_open(datum/act/op/A)
	var/mob/user = A.actor
	if(!operating)
		to_chat(user, span_notice("You crowbar the filter hatch open, releasing the items trapped within."))
		latent_materialize_all() // a walk needs real things (C5)
		for(var/atom/movable/item in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
			item.forceMove(loc)
	else
		to_chat(user, span_warning("Unable to empty filter while the machine is running."))
	return OP_OK

/obj/machinery/v_garbosystem/proc/transfer_reagent_to_tank(datum/reagents/reg,multiplier)
	var/volume_magic = reg.total_volume * multiplier
	volume_magic -= rand(2,10) // reagent tax
	if(volume_magic > 0)
		reg.trans_to_holder( reagents, volume_magic)
		transfer_sludge_to_tank(rand(1,5))

/obj/machinery/v_garbosystem/proc/transfer_ore_to_tank(obj/item/ore/R,multiplier)
	if(GLOB.ore_reagents[R.type])
		var/list/ore_components = GLOB.ore_reagents[R.type]
		if(islist(ore_components))
			var/amount_to_take = (REAGENTS_PER_ORE/(ore_components.len))
			for(var/i in ore_components)
				reagents.add_reagent(i, amount_to_take * multiplier)
		else
			reagents.add_reagent(ore_components, REAGENTS_PER_ORE * multiplier)
		transfer_sludge_to_tank(rand(1,5))

/obj/machinery/v_garbosystem/proc/transfer_sludge_to_tank(amt)
	if(prob(10) || amt >= 5)
		reagents.add_reagent(REAGENT_ID_TOXIN, amt)
		visible_message("\The [src] gurgles.")

/obj/machinery/button/garbosystem
	name = "garbage grinder switch"
	desc = "A power button for the big grinder."
	icon = 'icons/obj/machines/doorbell_vr.dmi'
	icon_state = "doorbell-standby"
	var/tmp/obj/machinery/v_garbosystem/grinder

CAPABILITIES(/obj/machinery/button/garbosystem)
	op("press_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Press"), then(PROC_REF(interaction_press_impl)))

/obj/machinery/button/garbosystem/proc/interaction_press_impl(datum/act/op/A)
	var/mob/user = A.actor
	if(grinder())
		grinder().attack_hand(user)
	return TRUE

/obj/machinery/v_garbosystem/proc/grind_affecting()
	var/items_taken = 0
	for(var/atom/movable/A in affecting)
		if(!isobj(A) && !isliving(A))
			continue
		if(istype(A, /obj/effect/decal/cleanable) || istype(A, /mob/living/voice))
			destroyed(A, src, BRUTE)
		if(!A.anchored)
			if(A.loc == src.loc)
				if(isliving(A))
					var/mob/living/L = A
					if(!emagged && ishuman(L) && L.mind)
						play_sfx(src, SFX_MACHINES_WARNING_BUZZER)
						visible_message(span_warning("POSSIBLE CREW MEMBER DETECTED! EMERGENCY STOP ENGAGED!"))
						GLOB.global_announcer.autosay("Possible crew member detected in grinder feed. Emergency Stop Protocols engaged!", "Recycling Grinder Alert", "Supply")
						set_operating(FALSE)
						update()
						break
					if(L.stat == DEAD)
						play_sfx(src, SFX_EFFECTS_SPLAT)
						if(L.meat_amount && L.meat_type) // Get all the goobs outta this goober
							while(L.meat_amount > 0)
								var/obj/item/meat = new L.meat_type(src)
								if(meat.reagents) // Reagents are set on init, might be randomized per meat chunk too so it needs to be done on a per case basis
									transfer_reagent_to_tank(meat.reagents,1)
								consumed(meat, src)
								L.meat_amount--
						L.gib()
						items_taken++
						if(ishuman(L))
							// Splorch
							var/mob/living/carbon/human/H = L
							transfer_reagent_to_tank(H.bloodstr,1)
							transfer_reagent_to_tank(H.ingested,1)
							transfer_reagent_to_tank(H.vessel,0.5)
						transfer_sludge_to_tank(rand(4,9))
					else
						L.injure(INJURY_CUT, 25, null, src)
						items_taken++
						break
				for(var/atom/movable/C in contents_of(A))
					if(C.anchored)
						C.set_anchored(FALSE)
					C.forceMove(loc)
				if(isitem(A))
					A.SpinAnimation(5,3)
					after(src, 1.5 SECONDS, PROC_REF(crunch_item), with = list(A), keeps_dead = TRUE)
					items_taken++
				else
					A.SpinAnimation(5,3)
					after(src, 1.5 SECONDS, PROC_REF(crunch_thing), with = list(A), keeps_dead = TRUE)
					items_taken++
		if(items_taken >= voracity)
			break
	if(items_taken) //Lazy coder sound design moment.
		GLOB.Recycled_Items = GLOB.Recycled_Items + items_taken
		play_sfx(src, SFX_ITEMS_POSTER_BEING_CREATED)
		play_sfx(src, SFX_ITEMS_ELECTRONIC_ASSEMBLY_EMPTYING)
		play_sfx(src, SFX_EFFECTS_METALSCRAPE2)

/obj/machinery/v_garbosystem/proc/crunch_item(atom/movable/A)
	if(A && A.loc == loc)
		if(A.reagents)
			transfer_reagent_to_tank(A.reagents,1)
		if(istype(A,/obj/item/ore))
			transfer_ore_to_tank(A,1)
		A.forceMove(src)
		if(!is_type_in_list(A, GLOB.item_digestion_blacklist))
			crusher().take_item(A) //Force feed the poor bastard.

/obj/machinery/v_garbosystem/proc/crunch_thing(atom/movable/A)
	if(A)
		A.forceMove(src)
		if(A.reagents)
			transfer_reagent_to_tank(A.reagents,1)
		if(istype(A, /obj/structure/closet))
			new /obj/item/stack/material/steel(loc, 2)
		destroyed(A, src, BRUTE)

/// Connects to regular crusher (a relation view: it reads null once the target is deleted).
/obj/machinery/v_garbosystem/proc/crusher() as /obj/machinery/recycling/crusher
	return crusher

/// the grinder this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/button/garbosystem/proc/grinder() as /obj/machinery/v_garbosystem
	return grinder

/// the button this refers to (a relation view: it reads null once the target is deleted).
/obj/machinery/v_garbosystem/proc/button() as /obj/machinery/button/garbosystem
	return button
