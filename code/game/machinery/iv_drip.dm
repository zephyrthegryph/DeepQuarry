/// The fill overlay of a drip or feeder container: `state` of `icon` with the reagent colour added (the legacy icon add, built once per colour).
DECLARE_SHARED_CACHE(reagent_fill_overlays, GLOBAL_PROC_REF(build_reagent_fill_overlay), SC_NEVER)

/proc/build_reagent_fill_overlay(icon, state, colour)
	var/icon/filled = icon(icon, state)
	if(colour)
		filled += colour
	return image(filled)

/obj/machinery/iv_drip
	name = "\improper IV drip"
	desc = "Helpful for giving someone blood! Or taking it away. It giveth, it taketh."
	icon = 'icons/obj/iv_drip.dmi'
	anchored = FALSE
	density = FALSE

/obj/machinery/iv_drip/var/mob/living/carbon/human/attached
/datum/scheduler_field_definition/obj/machinery/iv_drip/attached
	of = /obj/machinery/iv_drip
	field = "attached"
	channel = CHANGE_MACHINE_OCCUPANT
/// Drips (or draws) while hooked up to a patient.
/obj/machinery/iv_drip/mode = 1 // 1 is injecting, 0 is taking blood.
/obj/machinery/iv_drip/var/obj/item/reagent_containers/beaker = null

TRACKED(/obj/machinery/iv_drip, fill_state)
TRACKED(/obj/machinery/iv_drip, fill_color)
/// The fill overlay of the container (a "reagentN" state) and its reagent colour, or null for none: refresh_fill() writes them as the level moves.
/obj/machinery/iv_drip/var/fill_state
/obj/machinery/iv_drip/var/fill_color

/// Writes the fill overlay the container's level and colour show.
/obj/machinery/iv_drip/proc/refresh_fill()
	var/datum/reagents/reagents = beaker?.reagents
	if(!reagents?.total_volume)
		set_fill_state(null)
		return
	var/percent = round((reagents.total_volume / beaker.volume) * 100)
	switch(percent)
		if(0 to 9)
			set_fill_state("reagent0")
		if(10 to 24)
			set_fill_state("reagent10")
		if(25 to 49)
			set_fill_state("reagent25")
		if(50 to 74)
			set_fill_state("reagent50")
		if(75 to 79)
			set_fill_state("reagent75")
		if(80 to 90)
			set_fill_state("reagent80")
		if(91 to INFINITY)
			set_fill_state("reagent100")
	set_fill_color(reagents.get_color())

/// What it shows: hooked up while attached to a patient, and its container's fill in the reagent's colour.
/obj/machinery/iv_drip/draw(datum/look/look)
	..()
	look.state(attached() ? "hooked" : "")
	if(fill_state)
		look.overlay(CACHED_KEY(reagent_fill_overlays, "[icon]|[fill_state]|[fill_color]", icon, fill_state, fill_color))

CAPABILITIES(/obj/machinery/iv_drip)
	ref_one(nameof(attached), /mob/living/carbon/human)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(attached), wakes_on = list(nameof(attached)))
	drag_onto(PROC_REF(drop_input))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), starts(PROC_REF(screwdriver_used)), wait(1.5 SECONDS), then(PROC_REF(screwdriver_act_timed_done)))
	op("iv_drip_interaction_item", item(/obj/item/reagent_containers), priority(OP_PRIORITY_DEFAULT - 1), label("Attach container"), needs(req_is(nameof(beaker), FALSE, because = MSG(iv_drip/beaker))), then(PROC_REF(iv_drip_interaction_item)))
	op("iv_drip_interaction_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Remove container"), then(PROC_REF(iv_drip_interaction_hand)))
	op("iv_drip_toggle_mode", menu(), label("Toggle Mode"), needs(req_adjacent(), req_capable(), req_actor_kind(/mob/living, because = MSG(iv_drip/actor_type))), then(PROC_REF(iv_drip_toggle_mode)))

/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm). A drop onto a patient attaches them,
/// then the native drop goes on.
/obj/machinery/iv_drip/proc/drop_input(datum/act/input/A)
	drop_patient_with_actor(A.actor, A.over)
	return INPUT_FALLTHROUGH

/obj/machinery/iv_drip/proc/drop_patient_with_actor(mob/user, atom/over_object)
	if(!isliving(user))
		return

	if(attached())
		visible_message("[attached()] is detached from \the [src]")
		rel_clear(src, nameof(attached))
		refresh_fill()
		return

	if(in_range(src, user) && ishuman(over_object) && get_dist(over_object, src) <= 1)
		act_message(user, src, others = "%U% attaches %T% to \the [over_object].")
		rel_set(src, nameof(attached), over_object)
		refresh_fill()

MSG_DEF_SELF(iv_drip/beaker, "there is already a reagent container loaded")

MSG_DEF_SELF(iv_drip/actor_type, "you can't do that")

/// Old attackby.
/obj/machinery/iv_drip/proc/iv_drip_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!istype(W, /obj/item/reagent_containers))
		return OP_DECLINE

	if(!move_into(src, nameof(src.beaker), W, user))
		return OP_DECLINE
	to_chat(user, "You attach \the [W] to \the [src].")
	refresh_fill()
	return OP_OK

/obj/machinery/iv_drip/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_notice("You start to dismantle the IV drip."))
	return OP_OK

/obj/machinery/iv_drip/proc/screwdriver_act_timed_done(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You dismantle the IV drip."))
	var/obj/item/stack/rods/rods = new(loc, 6)
	if(beaker)
		beaker.forceMove(get_turf(src))
		rel_take(src, nameof(beaker))
	replace_with(src, rods)

/obj/machinery/iv_drip/proc/work_step(datum/act/timer/A)
	set background = 1
	if(attached())

		if(!(get_dist(src, attached()) <= 1 && isturf(attached().loc)))
			visible_message("The needle is ripped out of [attached()], doesn't that hurt?")
			attached().injure(INJURY_CUT, 3, pick(BP_R_ARM, BP_L_ARM), src)
			rel_clear(src, nameof(attached))
			refresh_fill()
			return PROCESS_KILL

	if(attached() && beaker)
		// Give blood
		if(mode)
			if(beaker.volume > 0)
				var/transfer_amount = REM
				if(istype(beaker, /obj/item/reagent_containers/blood))
					// speed up transfer on blood packs
					transfer_amount = 4
				beaker.reagents.trans_to_mob(attached(), transfer_amount, CHEM_BLOOD)
				refresh_fill()

		// Take blood
		else
			var/amount = beaker.reagents.maximum_volume - beaker.reagents.total_volume
			amount = min(amount, 4)
			// If the beaker is full, ping
			if(amount == 0)
				if(prob(5))
					visible_message("\The [src] pings.")
				return

			var/mob/living/carbon/human/T = attached()

			if(!istype(T))
				return
			if(!T.dna)
				return
			if(T.has_mutation(NOCLONE))
				return

			if(!T.should_have_organ(O_HEART))
				return

			// If the human is losing too much blood, beep.
			if(T.vessel.get_reagent_amount(REAGENT_ID_BLOOD) < T.species.blood_volume*T.species.blood_level_safe)
				visible_message("\The [src] beeps loudly.")

			var/datum/reagent/B = T.take_blood(beaker,amount)

			if(B)
				beaker.reagents.adopt_reagent(B)
				beaker.reagents.update_total()
				beaker.on_reagent_change()
				beaker.reagents.handle_reactions()
				refresh_fill()
				if(SScontracts)
					emit_contract_event(CONTRACT_EVENT_BLOOD_DONATED, list(
						"department" = DEPARTMENT_MEDICAL,
						"subject_id" = SScontracts.subject_identity(T)?.id,
						"container_id" = REF(beaker),
						"blood_type" = B.data?["blood_type"] || "unknown",
						"amount" = amount,
						"detail" = "Collected [amount] units of [B.data?["blood_type"] || "untyped"] blood from [T].",
					), "blood-donation:[REF(beaker)]:[round(beaker.reagents.total_volume, 0.1)]", src, null, T)

/// Old attack_hand: take the container off before the machinery gate; with none, the touch goes on.
/obj/machinery/iv_drip/proc/iv_drip_interaction_hand(datum/act/op/A)
	if(!beaker)
		return OP_DECLINE
	beaker.forceMove(get_turf(src))
	rel_take(src, nameof(beaker))
	refresh_fill()
	return OP_OK

/// Old verb "Toggle Mode".
/obj/machinery/iv_drip/proc/iv_drip_toggle_mode(datum/act/op/A)
	var/mob/user = A.actor
	if(user.stat)
		return

	set_mode(!mode)
	to_chat(user, "The IV drip is now [mode ? "injecting" : "taking blood"].")

/obj/machinery/iv_drip/examine(mob/user)
	. = ..()

	if(get_dist(user, src) <= 2)
		. += "The IV drip is [mode ? "injecting" : "taking blood"]."

		if(beaker)
			if(beaker.reagents?.reagent_list?.len)
				. += span_notice("Attached is \a [beaker] with [beaker.reagents.total_volume] units of liquid.")
			else
				. += span_notice("Attached is an empty [beaker].")
		else
			. += span_notice("No chemicals are attached.")

		. += span_notice("[attached() ? attached() : "No one"] is attached.")

/obj/machinery/iv_drip/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE)) //allow bullets, beams, thrown objects, mice, drones, and the like through.
		return TRUE
	return ..()

/obj/machinery/iv_drip/ownership()
	. = ..()
	. += owns(nameof(beaker), policy = OWN_CONTAINED)

/// attached (a relation view: it reads null once the target is deleted).
/obj/machinery/iv_drip/proc/attached() as /mob/living/carbon/human
	return attached
