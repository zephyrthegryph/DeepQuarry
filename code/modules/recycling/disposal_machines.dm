// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

// Disposal bin
// Holds items for disposal into pipe system
// Draws air from turf, gradually charges internal reservoir
// Once full (~1 atm), uses air resv to flush items into the pipes
// Automatically recharges air (unless off), will flush when ready if pre-set
// Can hold items and human size things, no other draggables
// Toilets are a type of disposal bin for small objects only and work on magic. By magic, I mean torque rotation
#define SEND_PRESSURE (0.05 + ONE_ATMOSPHERE) //kPa - assume the inside of a dispoal pipe is 1 atm, so that needs to be added.
#define PRESSURE_TANK_VOLUME 150	//L
#define PUMP_MAX_FLOW_RATE 11.25	//L/s - 4 m/s using a 15 cm by 15 cm inlet //NOTE: I reduced the send pressure from 801 to 101.05 which is about 1/8 there was originally, and this was 90 before that. 90/8 is about 11.25, so that's the new value. -Reo
#define DISPOSALMODE_EJECTONLY -1
#define DISPOSALMODE_OFF 0
#define DISPOSALMODE_CHARGING 1
#define DISPOSALMODE_CHARGED 2

/obj/machinery/disposal
	name = "disposal unit"
	desc = "A pneumatic waste disposal unit."
	icon = 'icons/obj/pipes/disposal.dmi'
	icon_state = "disposal"
	var/controls_iconstate = "disposal"
	anchored = TRUE
	density = TRUE
	var/datum/gas_mixture/air_contents	// internal reservoir
	/// While a charging bin sleeps: a gas watch on the air of its turf, which it draws from (gas_watch_many()).
	var/list/datum/native_watch/gas/intake_watches
	mode = DISPOSALMODE_CHARGING
	var/flush = FALSE	// true if flush handle is pulled
	var/flushing = FALSE	// true if flushing in progress
	var/flush_every_ticks = 30 //Every 30 ticks it will look whether it is ready to flush
	var/flush_count = 0 //this var adds 1 once per tick. When it reaches flush_every_ticks it resets and tries to flush.
	active_power_usage = 2200	//the pneumatic pump power. 3 HP ~ 2200W
	idle_power_usage = 100
	var/stat_tracking = TRUE
	flags = REMOTEVIEW_ON_ENTER

CAPABILITIES(/obj/machinery/disposal)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	owns_one(nameof(air_contents), /datum/gas_mixture)
	owns_many(nameof(intake_watches), /datum/native_watch/gas)
	interface("DisposalBin")
	without("ui_open")
	op("pumpOn", ui_act("pumpOn"), then(PROC_REF(ui_act_pumpon)))
	op("pumpOff", ui_act("pumpOff"), then(PROC_REF(ui_act_pumpoff)))
	op("engageHandle", ui_act("engageHandle"), then(PROC_REF(ui_act_engagehandle)))
	op("disengageHandle", ui_act("disengageHandle"), then(PROC_REF(ui_act_disengagehandle)))
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	param(nameof(built_from_construct), pos = 1, apply = PROC_REF(take_construct), keep = FALSE)
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(multitool_used)))
	op("use_welder", tool(TOOL_WELDER), priority(OP_PRIORITY_DEFAULT), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("disposal_insert", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Insert"), then(PROC_REF(interaction_disposal_insert)))
	op("disposal_dunk", item(/obj/item/grab), priority(OP_PRIORITY_DEFAULT), label("Put in"), when(req(PROC_REF(grabs_mob))), needs(req(PROC_REF(not_broken), silent = TRUE)), starts(PROC_REF(dunk_started)), begins(PROC_REF(dunk_begins)), wait(2 SECONDS), then(PROC_REF(dunk_done)))
	op("disposal_stuff_mob", item(/mob/living), gesture(GESTURE_DRAG), priority(OP_PRIORITY_NORMAL), label("Insert"), needs(req(PROC_REF(can_stuff_mob), silent = TRUE)), starts(PROC_REF(stuff_started)), begins(PROC_REF(stuff_begins)), wait(2 SECONDS), then(PROC_REF(stuff_mob_done)))
	op("disposal_drag_insert", item(/atom/movable), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Insert"), then(PROC_REF(interaction_disposal_drag_insert)))
	op("disposal_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_disposal_use)))
	op("disposal_flush", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle flush"), then(PROC_REF(interaction_disposal_flush)))
	op("disposal_force_eject", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Force Eject"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_disposal_force_eject)))

// C11: one slot, accepting anything (any movable dropped, thrown or grabbed
// into the bin before a flush). Drop policy is left to this type's own
// Destroy() below, which already calls eject() -- emptying the bin onto the
// floor -- before ..() reaches the base Destroy()'s generic drop-policy pass.
/datum/relation_definition/slot/disposal_bin
	holder = /obj/machinery/disposal
	slot_id = CONTAINER_SLOT_DISPOSAL
	name = "contents"
	drop_policy = SLOT_DROP_HOLDER
	exposure = SLOT_EXPOSURE_INTERNAL

// create a new disposal
// find the attached trunk (if present) and init gas resvr.
DECLARE_GAS(/obj/machinery/disposal, "air_contents", PRESSURE_TANK_VOLUME, T20C, null)

/// The construct a bin is built from (its constructor param, used up at init).
/obj/machinery/disposal/var/tmp/obj/structure/disposalconstruct/built_from_construct

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A bin built from a construct faces its way, uses it up and starts off.
/obj/machinery/disposal/proc/take_construct(obj/structure/disposalconstruct/make_from)
	if(!make_from)
		return
	set_dir(make_from.dir)
	consumed(make_from, src)
	set_mode(DISPOSALMODE_OFF)

// ALLOW(init/INSTANCE_STATE): a bin joins its trunk and the disposal network, and a mapped one primes its reservoir from the room
/obj/machinery/disposal/Initialize(mapload)
	. = ..()

	var/obj/structure/disposalpipe/trunk/trunk = locate_on(loc, /obj/structure/disposalpipe/trunk)

	add_disposal_connection()
	face(dir)
	observe(src, /datum/notice/disposal_receive, src, then(PROC_REF(on_disposal_receive)))
	if(trunk)
		PUBLISH_LEGACY(src, /datum/notice/disposal_link, trunk)

	// air_contents is declared (DECLARE_GAS). Map-loaded bins are installed infrastructure, not freshly constructed
	// empty vessels. Prime their tiny reservoir from the mapped room atmosphere
	// so hundreds of bins do not all perform identical FFI pump transactions for
	// the first minute of every round. Constructed/repaired bins still charge
	// through the normal physical pump path.
	if(mapload)
		var/datum/gas_mixture/environment = loc.return_air()
		var/environment_pressure = environment?.return_pressure() || 0
		var/environment_volume = environment?.return_volume() || 0
		if(environment_pressure > 0 && environment_volume > 0)
			var/fill_ratio = (PRESSURE_TANK_VOLUME / environment_volume) * (SEND_PRESSURE / environment_pressure)
			air_contents.copy_from_ratio(environment, fill_ratio)
			air_contents.set_volume(PRESSURE_TANK_VOLUME)
			set_mode(DISPOSALMODE_CHARGED)

// it unlinks and ejects its contents.
/obj/machinery/disposal/on_destroy(force)
	clear_gas_dependency()
	PUBLISH_LEGACY(src, /datum/notice/disposal_unlink)
	eject()
	..()

/// Contents are the only reason a charged disposal needs periodic autoflush work.
/obj/machinery/disposal/Entered(atom/movable/thing, atom/old_loc)
	. = ..()
	wake_for_state_change()

/obj/machinery/disposal/proc/wake_for_state_change()
	clear_gas_dependency()
	changed(src, CHANGE_MACHINE_SETTINGS)
	work_start(src)

// The intake subscription is keyed by the mixture of the turf we sit on; after a
// move it is stale. (A ChangeTurf() underneath us also swaps the mixture with no
// Moved() and no contents hook — see the matching note in firedoor.dm.)
/obj/machinery/disposal/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(mode == DISPOSALMODE_CHARGING)
		wake_for_state_change()

/// Wakes only once a charging disposal can actually draw air from its turf.
/obj/machinery/disposal/proc/hibernate_until_intake_changes()
	var/datum/gas_mixture/environment = loc.return_air()
	// Callers stop it themselves: work_step() returns PROCESS_KILL right after.
	gas_watch_many(src, nameof(intake_watches), list(environment), GAS_DEPENDENCY_PRESSURE, PROC_REF(intake_heard))

/// The turf's air changed: the bin wakes when it can draw from it now (its own eligibility rule, not every change).
/obj/machinery/disposal/proc/intake_heard(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index)
	if(gas_wake_condition())
		wake_from_gas()

/obj/machinery/disposal/proc/gas_wake_condition()
	if(mode != DISPOSALMODE_CHARGING || (!operable()))
		return FALSE
	var/datum/gas_mixture/environment = loc?.return_air()
	return environment && can_pressurize_from(environment)

/obj/machinery/disposal/proc/clear_gas_dependency()
	gas_watch_many_clear(src, nameof(intake_watches))

/obj/machinery/disposal/proc/wake_from_gas()
	clear_gas_dependency()
	work_start(src)

/obj/machinery/disposal/proc/can_pressurize_from(datum/gas_mixture/environment)
	if(!air_contents || !environment || environment.return_temperature() <= 0 || environment.total_moles() < MINIMUM_MOLES_TO_PUMP)
		return FALSE
	var/transfer_moles = min(environment.total_moles(), (PUMP_MAX_FLOW_RATE / environment.return_volume()) * environment.total_moles())
	var/specific_power = vg_specific_power(environment, air_contents) / ATMOS_PUMP_EFFICIENCY
	if(specific_power > 0)
		transfer_moles = min(transfer_moles, active_power_usage / specific_power)
	return transfer_moles >= MINIMUM_MOLES_TO_PUMP

/obj/machinery/disposal/singularity_pull(S, current_size)
	..()
	if(current_size >= STAGE_FIVE)
		atom_deconstruct(TRUE)

// attack by item places it in to disposal
/// Requirement: the grab holds a mob.
/obj/machinery/disposal/proc/grabs_mob(datum/act/op/A)
	var/obj/item/grab/G = A.held
	return istype(G) && ismob(G.grab_target())

/// Requirement: the bin is not broken.
/obj/machinery/disposal/proc/not_broken(datum/act/op/A)
	return !broken_now()

/obj/machinery/disposal/proc/dunk_started(datum/act/op/A)
	wake_for_state_change()
	add_fingerprint(A.actor)

/obj/machinery/disposal/proc/dunk_begins(datum/act/op/A)
	var/obj/item/grab/G = A.held
	var/mob/GM = G.grab_target()
	return msg_text(null, "%U% starts putting [GM.name] into the disposal.")

/obj/machinery/disposal/proc/dunk_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/grab/G = A.held
	var/mob/GM = G.grab_target()
	if(!GM)
		return OP_OK
	GM.forceMove(src)
	for (var/mob/C in viewers(src))
		C.show_message(span_red("[GM.name] has been placed in the [src] by [user]."), 3)
	consume(G, user)

	add_attack_logs(user,GM,"Disposals dunked")
	return OP_OK

/obj/machinery/disposal/proc/interaction_disposal_insert(datum/act/op/A)
	disposal_insert(A.actor, A.held)
	return OP_OK

/// An item placed in the bin, by hand or dragged onto it (borgs may only drag).
/obj/machinery/disposal/proc/disposal_insert(mob/user, obj/item/I, drag_dropped = FALSE)
	wake_for_state_change()
	if(broken_now() || !I || !user || !istype(I))
		return

	add_fingerprint(user)

	if(istype(I, /obj/item/storage/bag/trash))
		var/obj/item/storage/bag/trash/T = I
		to_chat(user, span_blue("You empty the bag."))
		for(var/obj/item/O in T.slot_contents())
			T.remove_from_storage(O,src)
		sync_occupied()
		return

	if(istype(I, /obj/item/material/ashtray))
		var/obj/item/material/ashtray/A = I
		if(contents_count(A) > 0)
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " empties %I% into %T%."), item = A)
			for(var/obj/item/O in contents_of(A))
				O.forceMove(src)
			A.sync_butts()
			sync_occupied()
			return

	if(istype(I, /obj/item/grab)) // a grabbed mob is put in by the "disposal_dunk" op
		return

	if(isrobot(user) && !drag_dropped) //Borgs are allowed to drag-drop items into the disposal unit.
		return
	if(!I || I.anchored || !I.canremove)
		return

	if(!drag_dropped)
		user.drop_item()
	if(I)
		if(istype(I, /obj/item/holder))
			var/obj/item/holder/holder = I
			var/mob/victim = holder.held_mob
			if(victim)
				if(victim.client)
					log_and_message_admins("placed [victim] inside \the [src]", user)
				victim.forceMove(src)
			consume(I, user)
			act_message(user, victim, MSG_SELF(span_danger("You toss %T% into \the [src].")), \
				MSG_OTHERS(span_danger("%U% tosses %T% into \the [src].")), \
				MSG_BLIND(span_warning("Pr-Thunk")))
			sync_occupied()
			return

		I.forceMove(src)

	act_message(user, src, MSG_SELF("You place %I% into %T%."), MSG_OTHERS("%U% places %I% into %T%."), MSG_BLIND("Ca-Clunk"), item = I)
	sync_occupied()
	return

/obj/machinery/disposal/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	wake_for_state_change()
	if(mode > DISPOSALMODE_OFF)
		return OP_OK
	alter_bin_type(user)
	return OP_OK

/obj/machinery/disposal/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	wake_for_state_change()
	if(mode > DISPOSALMODE_OFF || length(slot_contents(CONTAINER_SLOT_DISPOSAL)))
		if(length(slot_contents(CONTAINER_SLOT_DISPOSAL)))
			to_chat(user, "Eject the items first!")
		return OP_OK
	set_mode(mode == DISPOSALMODE_OFF ? DISPOSALMODE_EJECTONLY : DISPOSALMODE_OFF)
	playsound(src, I.usesound, 50, 1)
	to_chat(user, "You [mode == DISPOSALMODE_EJECTONLY ? "remove" : "attach"] the screws around the power connection.")
	return OP_OK

/obj/machinery/disposal/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	wake_for_state_change()
	if(mode != DISPOSALMODE_EJECTONLY || length(slot_contents(CONTAINER_SLOT_DISPOSAL)))
		if(length(slot_contents(CONTAINER_SLOT_DISPOSAL)))
			to_chat(user, "Eject the items first!")
		return OP_OK
	use_tool(user, I, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 100, start_self = "You start slicing the floorweld off the disposal unit.", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
	return OP_OK

/obj/machinery/disposal/proc/welder_act_tool_done(mob/user)
	if(!src)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, "You sliced the floorweld off the disposal unit.")
	atom_deconstruct(TRUE)

/obj/machinery/disposal/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

// Transform into next machine type
/obj/machinery/disposal/proc/alter_bin_type(mob/user)
	if(length(slot_contents(CONTAINER_SLOT_DISPOSAL)) > 0)
		to_chat(user, "Eject the items first!")
		return
	// Get what we want to turn into
	var/nametag
	var/new_dir = SOUTH
	var/new_disposal_path
	var/result = rerun_ask(user, "k266", PROC_REF(alter_bin_type), args, /datum/prompt/choice, question = "What do you want to reconfigure the disposal bin to?", title = "Multitool-Disposal interface", choices = list( "Standard", "Wall", "Resleeving Deposit", "Wall Resleeving Deposit", "Hazard Bin", "Wall Hazard Bin", "Turn-In Bin", "Wall Turn-In Bin", "Mail Destination", "Wall Mail Destination" ))
	if(isnull(result))
		return
	if(!result)
		return
	switch(result)
		// Yellow
		if("Standard")
			new_disposal_path = /obj/machinery/disposal
		if("Wall")
			new_disposal_path = /obj/machinery/disposal/wall
			new_dir = reverse_direction(user.dir)
		// Blue
		if("Resleeving Deposit")
			new_disposal_path = /obj/machinery/disposal/cleaner
			new_dir = reverse_direction(user.dir)
		if("Wall Resleeving Deposit")
			new_disposal_path = /obj/machinery/disposal/wall/cleaner
			new_dir = reverse_direction(user.dir)
		// Red
		if("Hazard Bin")
			new_disposal_path = /obj/machinery/disposal/burn_pit
		if("Wall Hazard Bin")
			new_disposal_path = /obj/machinery/disposal/wall/burn_pit
			new_dir = reverse_direction(user.dir)
		// Green
		if("Turn-In Bin")
			new_disposal_path = /obj/machinery/disposal/turn_in
		if("Wall Turn-In Bin")
			new_disposal_path = /obj/machinery/disposal/wall/turn_in
			new_dir = reverse_direction(user.dir)
		// White
		if("Mail Destination")
			new_disposal_path = /obj/machinery/disposal/mail_reciever
			var/_answer_k298 = rerun_ask(user, "k298", PROC_REF(alter_bin_type), args, /datum/prompt/text, question = "Name this mail destination. This name has no effect on the disposal sorting junction, and is only for crew convenience.", title = "Mail Destination")
			if(isnull(_answer_k298))
				return
			nametag = _answer_k298
		if("Wall Mail Destination")
			new_disposal_path = /obj/machinery/disposal/wall/mail_reciever
			new_dir = reverse_direction(user.dir)
			var/_answer_k302 = rerun_ask(user, "k302", PROC_REF(alter_bin_type), args, /datum/prompt/text, question = "Name this mail destination. This name has no effect on the disposal sorting junction, and is only for crew convenience.", title = "Mail Destination")
			if(isnull(_answer_k302))
				return
			nametag = _answer_k302

	if(!new_disposal_path || (new_disposal_path == type && dir == new_dir))
		return
	if(!Adjacent(user) || length(slot_contents(CONTAINER_SLOT_DISPOSAL)) > 0)
		return
	if(mode > DISPOSALMODE_OFF)
		return
	// Make new bin
	var/obj/machinery/disposal/new_bin = new new_disposal_path(loc)
	if(nametag) // mailer only
		new_bin.name = "[initial(new_bin.name)]([nametag])"
	new_bin.set_broken_condition(broken_now())
	new_bin.set_maintenance(under_maintenance())
	new_bin.set_mode(mode)
	new_bin.face(new_dir)
	new_bin.visible_message("\The [src] reconfigures into \a [new_bin]!")
	// Effects
	play_sfx(new_bin, SFX_ITEMS_JAWS_CUT)
	play_sfx(new_bin, SFX_MACHINES_MACHINE_DIE_SHORT)
	fx_sparks(new_bin, 5, FALSE)
	// Cleanup
	spent(src, user)

// mouse drop another mob or self
//
/obj/machinery/disposal/proc/interaction_disposal_drag_insert(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/dropping = A.held
	if(!isliving(dropping) && Adjacent(user) && Adjacent(dropping) && isobj(dropping) && isturf(dropping.loc))
		disposal_insert(user, dropping, drag_dropped = TRUE)
	return OP_OK

/// Requirement: the user can put the dragged mob in (animals only put themselves in; nobody buckled, down or out of reach does).
/obj/machinery/disposal/proc/can_stuff_mob(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/target = A.held
	if(!istype(user) || !istype(target))
		return FALSE
	//animals cannot put mobs other than themselves into disposal
	if(isanimal(user) && target != user)
		return FALSE
	if(user.stat || !read_once(user.canmove))
		return FALSE
	if(target.buckled_to() || read_once(get_dist(user, src) > 1) || read_once(get_dist(user, target) > 1))
		return FALSE
	return TRUE

/obj/machinery/disposal/proc/stuff_started(datum/act/op/A)
	add_fingerprint(A.actor)

/obj/machinery/disposal/proc/stuff_begins(datum/act/op/A)
	var/mob/living/target = A.held
	if(A.actor == target)
		return msg_text(null, "%U% starts climbing into %T%")
	return msg_text(span_userdanger("[A.actor] starts stuffing you into [src]!"), span_danger("[A.actor] starts stuffing [target] into [src]."))

/obj/machinery/disposal/proc/stuff_mob_done(datum/act/op/A)
	var/mob/living/target = A.held
	var/mob/living/user = A.actor
	if(!loc)
		return OP_OK
	target.forceMove(src)
	if(user == target)
		act_message(user, src, MSG_SELF(span_notice("You climb into %T%")), MSG_OTHERS("%U% climbs into %T%."))
		log_and_message_admins("climbed into disposals!", user)
	else
		act_message(target, user, MSG_SELF(span_userdanger("%T% stuffs %U% into \the [src].")), MSG_OTHERS(span_danger("%T% stuffs %U% into \the [src].")))
		add_attack_logs(user,target,"Disposals dunked")
	sync_occupied()
	return OP_OK

// attempt to move while inside
/obj/machinery/disposal/relaymove(mob/user)
	attempt_escape(user)

// resist to escape the bin
/obj/machinery/disposal/container_resist(mob/living/user)
	attempt_escape(user)

/obj/machinery/disposal/proc/attempt_escape(mob/user)
	if(user.stat || flushing)
		return
	go_out(user)

// leave the disposal
/obj/machinery/disposal/proc/go_out(mob/user)
	user.forceMove(get_turf(src))
	sync_occupied()

/obj/machinery/disposal
	silicon_use = SILICON_USE_UI
/*
/obj/machinery/disposal/attack_paw()
	if(broken_now())
		return
	flush = !flush
*/
// human interact with machine
/obj/machinery/disposal/proc/interaction_disposal_use(datum/act/op/A)
	var/mob/user = A.actor
	if(user.loc == src) // the controls can't be worked from inside the bin
		to_chat(user, span_warning("You cannot reach the controls from inside."))
		return OP_DECLINE
	if(broken_now())
		return OP_OK

	// Clumsy folks can only flush it.
	if(user.IsAdvancedToolUser(1))
		tgui_interact(user)
	else
		set_flush(!flush)
		wake_for_state_change()
	return OP_OK

/// The old click_alt toggled flush, then (returning NONE) fell through to the alt-click loot panel either way.
/obj/machinery/disposal/proc/interaction_disposal_flush(datum/act/op/A)
	var/mob/user = A.actor
	/*
	if(user.canUseTopic) //Later...
		return
	*/
	if(get_dist(user, src) > 1 || user.loc == src || user.stat) //Until the above exists...
		return OP_DECLINE
	set_flush(!flush)
	wake_for_state_change()
	return OP_PASS

// user interaction

/obj/machinery/disposal/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["flushing"] = flush
	var/list/merged_1 = ui_data_obj_machinery_disposal(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/disposal's window data.
/obj/machinery/disposal/proc/ui_data_obj_machinery_disposal(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["isAI"] = isAI(user)
	data["mode"] = mode
	data["pressure"] = round(clamp(100* air_contents.return_pressure() / (SEND_PRESSURE), 0, 100),1)

	return data

/obj/machinery/disposal/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(user.loc == src)
		to_chat(user, span_warning("You cannot reach the controls from inside."))
		return FALSE
	if(mode == DISPOSALMODE_EJECTONLY && action != "eject") // If the mode is -1, only allow ejection
		to_chat(user, span_warning("The disposal units power is disabled."))
		return FALSE
	if(broken_now())
		return FALSE
	add_fingerprint(user)
	if(flushing)
		return FALSE
	return TRUE

/obj/machinery/disposal/proc/ui_act_pumpon(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	set_mode(DISPOSALMODE_CHARGING)
	wake_for_state_change()
	return TRUE

/obj/machinery/disposal/proc/ui_act_pumpoff(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	set_mode(DISPOSALMODE_OFF)
	wake_for_state_change()
	return TRUE

/obj/machinery/disposal/proc/ui_act_engagehandle(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	set_flush(TRUE)
	wake_for_state_change()
	return TRUE

/obj/machinery/disposal/proc/ui_act_disengagehandle(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	set_flush(FALSE)
	wake_for_state_change()
	return TRUE

/obj/machinery/disposal/proc/ui_act_eject(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	eject()
	wake_for_state_change()
	return TRUE

// eject the contents of the disposal unit

/obj/machinery/disposal/proc/interaction_disposal_force_eject(datum/act/op/A)
	if(flushing)
		return OP_OK
	eject()
	return OP_OK

/obj/machinery/disposal/proc/eject()
	for(var/atom/movable/AM in slot_contents(CONTAINER_SLOT_DISPOSAL))
		AM.forceMove(get_turf(src))
		AM.pipe_eject(0)
	sync_occupied()

TRACKED(/obj/machinery/disposal, flush)
/// Whether anything is inside, kept for the look.
/obj/machinery/disposal/var/occupied = FALSE
TRACKED(/obj/machinery/disposal, occupied)

/// Whether anything is inside, as the look reads it: refreshed wherever the contents change.
/obj/machinery/disposal/proc/sync_occupied()
	set_occupied(length(slot_contents(CONTAINER_SLOT_DISPOSAL)) > 0)

/// Turns the bin to face a direction; a wall bin also moves its outlet.
/obj/machinery/disposal/proc/face(new_dir)
	set_dir(new_dir)

// the icon & overlays reflect mode & status
/obj/machinery/disposal/draw(datum/look/look)
	..()
	look_parts(look)

/obj/machinery/disposal/proc/look_parts(datum/look/look)
	if(broken_now())
		look.state("disposal-broken")
		return

	// flush handle
	look.overlay("[controls_iconstate]-handle", when = flush)

	// only handle is shown if no power
	if(power_lost() || mode == DISPOSALMODE_EJECTONLY)
		return

	// 	check for items in disposal - occupied light
	look.overlay("[controls_iconstate]-full", when = occupied)

	// charging and ready light
	if(mode == DISPOSALMODE_CHARGING)
		look.overlay("[controls_iconstate]-charge")
	else if(mode == DISPOSALMODE_CHARGED)
		look.overlay("[controls_iconstate]-ready")

// timed process
// charge the gas reservoir and perform flush if ready
/obj/machinery/disposal/proc/work_step(datum/act/timer/A)
	if(!air_contents || (broken_now()))			// nothing can happen if broken
		set_use_power(USE_POWER_OFF)
		if(broken_now()) // a broken bin stops pumping and won't flush (the redraw used to do this)
			set_mode(DISPOSALMODE_OFF)
			set_flush(0)
		return PROCESS_KILL

	if(mode != DISPOSALMODE_CHARGING && !flush && !length(slot_contents(CONTAINER_SLOT_DISPOSAL)))
		set_use_power(USE_POWER_IDLE)
		flush_count = 0
		return PROCESS_KILL // idle and empty: an insertion or a flush starts it again

	flush_count++
	if( flush_count >= flush_every_ticks )
		if( length(slot_contents(CONTAINER_SLOT_DISPOSAL)) )
			if(mode == DISPOSALMODE_CHARGED)
				feedback_inc("disposal_auto_flush",1)
				flush()
		flush_count = 0

	if(flush && air_contents.return_pressure() >= SEND_PRESSURE )	// flush can happen even without power
		flush()

	if(mode != DISPOSALMODE_CHARGING) //if off or ready, no need to charge
		set_use_power(USE_POWER_IDLE)
	else if(air_contents.return_pressure() >= SEND_PRESSURE)
		set_mode(DISPOSALMODE_CHARGED) //if full enough, switch to ready mode
		if(!flush && !length(slot_contents(CONTAINER_SLOT_DISPOSAL)))
			return PROCESS_KILL // charged and empty: an insertion or a flush starts it again
	else
		if(!pressurize()) //otherwise charge
			hibernate_until_intake_changes()
			return PROCESS_KILL

/obj/machinery/disposal/proc/pressurize()
	if(power_lost())			// won't charge if no power
		set_use_power(USE_POWER_OFF)
		return FALSE

	var/atom/L = loc						// recharging from loc turf
	var/datum/gas_mixture/env = L.return_air()

	var/power_draw = -1
	if(env && env.return_temperature() > 0)
		var/transfer_moles = (PUMP_MAX_FLOW_RATE/env.return_volume())*env.total_moles()	//group_multiplier is divided out here
		power_draw = pump_gas(src, env, air_contents, transfer_moles, active_power_usage)

	if (power_draw > 0)
		use_power(power_draw)
	return power_draw >= 0

// perform a flush
/obj/machinery/disposal/proc/flush()
	flushing = TRUE
	flush_animation()
	//Bit of a nasty way to do this. But sleep()s are nastier.
	after(src, 1 SECOND, PROC_REF(flush_startup))

/obj/machinery/disposal/proc/flush_animation()
	PROTECTED_PROC(TRUE)
	flick("[icon_state]-flush", src)

/obj/machinery/disposal/proc/flush_startup()
	PROTECTED_PROC(TRUE)
	play_sfx(src, SFX_MACHINES_DISPOSALFLUSH)
	after(src, 0.5 SECONDS, PROC_REF(flush_complete)) // wait for animation to finish

/obj/machinery/disposal/proc/flush_complete()
	PROTECTED_PROC(TRUE)
	if(QDELETED(src))
		return
	// We don't ever want digestion remains going through disposals, but people understandably thing they're doing right by trashing them
	// So let's just delete them instead!
	for(var/obj/item/digestion_remains/bone in slot_contents(CONTAINER_SLOT_DISPOSAL))
		consume(bone)

	var/list/flushed_items = list()
	for(var/atom/movable/AM in slot_contents(CONTAINER_SLOT_DISPOSAL))
		flushed_items += AM

	if(stat_tracking)
		GLOB.disposals_flush_shift_roundstat++

	var/datum/act/flush_disposal/flush = ACT_TRY(src, flush_disposal, flushed_items, air_contents)
	if(flush) //If nothing handles it, we'll just expel immediately.
		act_cancel(flush)
		if(length(slot_contents(CONTAINER_SLOT_DISPOSAL)))
			packet_expel(src, flushed_items, air_contents)

	rel_set(src, nameof(air_contents), new /datum/gas_mixture(PRESSURE_TANK_VOLUME)) // new empty gas resv. Disposal packet takes ownership of the original one!
	flushing = FALSE

	// now reset disposal state
	flush = FALSE
	if(mode == DISPOSALMODE_CHARGED)	// if was ready,
		set_mode(DISPOSALMODE_CHARGING) // switch to charging

	wake_for_state_change()
	sync_occupied()

// called when area power changes
/obj/machinery/disposal/power_change()
	. = ..()	// do default setting/reset of stat NOPOWER bit
	if(.)
		if(flush || length(slot_contents(CONTAINER_SLOT_DISPOSAL)))
			wake_for_state_change()
		else if(mode == DISPOSALMODE_CHARGING && !power_lost() && can_pressurize_from(loc.return_air()) && !after_pending(src, "power_retry_timer"))
			// A station-wide restoration otherwise wakes every empty bin in the
			// same tick, their combined pump surge drops the grid, and all of them
			// go back to sleep without charging. Spread retries across the cycle.
			after(src, rand(1 SECOND, 30 SECONDS), PROC_REF(retry_charge_after_power_restore), key = "power_retry_timer")

/obj/machinery/disposal/proc/retry_charge_after_power_restore()
	if(mode == DISPOSALMODE_CHARGING && operable() && can_pressurize_from(loc.return_air()))
		wake_for_state_change()

// called when the bin expels items, generally from a disposal network, or trying to flush without a proper connection.
// should usually only occur if the pipe network if modified or delivering mail

/// Hooked on our own disposal_receive event.
/obj/machinery/disposal/proc/on_disposal_receive(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	var/datum/notice/disposal_receive/event = A
	packet_expel(source, event.items, event.gas)

/obj/machinery/disposal/proc/packet_expel(datum/source, list/expelled_items, datum/gas_mixture/gas)
	SHOULD_NOT_SLEEP(TRUE)
	var/turf/T = get_turf(src)
	var/turf/target
	play_sfx(src, SFX_MACHINES_HISS)

	for(var/atom/movable/AM in expelled_items)
		target = get_offset_target_turf(loc, rand(5)-rand(5), rand(5)-rand(5))

		AM.forceMove(T)
		AM.pipe_eject(0)
		AM.throw_at(target, 5, 1)

	T.assume_air(gas)

/obj/machinery/disposal/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	if(!source.CanEnterDisposals())
		return ..()

	if(prob(75))
		source.forceMove(src)
		if(isliving(source))
			var/mob/living/to_be_dunked = source
			if(to_be_dunked.client)
				log_and_message_admins("has thrown [source] into \the [src]", throwingdatum?.get_thrower())
			visible_message("\The [source] lands in \the [src].") // "and triggers the flush system!"
		else
			visible_message("\The [source] lands in \the [src].")
	else
		visible_message("\The [source] bounces off of \the [src]'s rim!")
		return ..()
	sync_occupied()

// Ideally, deconstruct would be a proc on /machinery, but you cant have nice things with polaris.
// AKA: FUKKIN CHANGE THIS WHEN THAT HAPPENS!!!!!1!!   pls. -Reo
/obj/machinery/disposal/atom_deconstruct(disassembled = TRUE)
	var/turf/T = loc
	/* // More nice things... Someday we'll have flags_1 and then have proper support for anything being a hologram.
	if(!(flags_1 & NODECONSTRUCT_1))
		if(stored)
			stored.forceMove(T)
			src.transfer_fingerprints_to(stored)
			stored.anchored = FALSE
			stored.density = TRUE
			stored.update_icon()
	*/
	//This is temporary until the above gets used. Or it's permanant if you're reading this 5 years from now.
	var/obj/structure/disposalconstruct/C = new (src.loc/*null, SOUTH, FALSE, src*/)
	transfer_fingerprints_to(C)
	C.ptype = 6 // 6 = disposal unit
	C.set_anchored(TRUE)
	C.set_density(TRUE)
	//End of "temporary" code
	for(var/atom/movable/AM in slot_contents(CONTAINER_SLOT_DISPOSAL))
		AM.forceMove(T)
	//..() //*cough
	PUBLISH_LEGACY(src, /datum/notice/disposal_unlink)
	destroyed(src, null, "deconstructed") //Parent above should do this, but that's not a thing as of writing this.

/obj/machinery/disposal/proc/clean_items()
	// Clean items before sending them
	for(var/obj/item/flushed_item in slot_contents(CONTAINER_SLOT_DISPOSAL))
		if(istype(flushed_item, /obj/item/storage))
			var/obj/item/storage/storage_flushed = flushed_item
			var/list/storage_items = storage_flushed.return_inv()
			for(var/obj/item/item in storage_items)
				item.wash(CLEAN_WASH)
			continue
		if(istype(flushed_item, /obj/item))
			flushed_item.wash(CLEAN_WASH)

// Wall mounted base type
/obj/machinery/disposal/wall
	name = "inset disposal unit"
	icon_state = "wall"
	controls_iconstate = "wall"

	density = FALSE

/// A wall bin sits in the wall it faces: the look offsets it by its dir (a change of dir redraws).
/obj/machinery/disposal/wall/look_parts(datum/look/look)
	..()
	switch(dir)
		if(NORTH)
			look.offset(0, -32)
		if(SOUTH)
			look.offset(0, 32)
		if(EAST)
			look.offset(-32, 0)
		if(WEST)
			look.offset(32, 0)

#undef DISPOSALMODE_EJECTONLY
#undef DISPOSALMODE_OFF
#undef DISPOSALMODE_CHARGING
#undef DISPOSALMODE_CHARGED
#undef SEND_PRESSURE
#undef PRESSURE_TANK_VOLUME
#undef PUMP_MAX_FLOW_RATE

/atom/movable/proc/CanEnterDisposals()
	return TRUE

/obj/item/projectile/CanEnterDisposals()
	return FALSE

/obj/effect/CanEnterDisposals()
	return FALSE

/obj/mecha/CanEnterDisposals()
	return FALSE

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/disposal/step_start_condition()
	return mode == 1 || flush || contents_count(src) || has_latent() // ALLOW(latent): latent entries checked

