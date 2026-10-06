/*
Overview:
	Used to create objects that need a per step proc call.  Default definition of 'New()'
	stores a reference to src machine in global 'machines list'.  Default definition
	of 'Del' removes reference to src machine in global 'machines list'.

Class Variables:

	power_init_complete (boolean)
		Indicates that we have have registered our static power usage with the area.

	use_power (num)
		current state of auto power use.
		Possible Values:
			USE_POWER_OFF:0 -- no auto power use
			USE_POWER_IDLE:1 -- machine is using power at its idle power level
			USE_POWER_ACTIVE:2 -- machine is using power at its active power level

	active_power_usage (num)
		Value for the amount of power to use when in active power mode

	idle_power_usage (num)
		Value for the amount of power to use when in idle power mode

	power_channel (num)
		What channel to draw from when drawing power for power mode
		Possible Values:
			EQUIP:0 -- Equipment Channel
			LIGHT:2 -- Lighting Channel
			ENVIRON:3 -- Environment Channel

	component_parts (list)
		A list of component parts of machine used by frame based machines.

	panel_open (num)
		Whether the panel is open

	uid (num)
		Unique id of machine across all machines.

	gl_uid (global num)
		Next uid value in sequence

	stat (bitflag)
		Machine status bit flags.
		Possible bit flags:
			BROKEN:1 -- Machine is broken
			NOPOWER:2 -- No power is being supplied to machine.
			POWEROFF:4 -- tbd
			MAINT:8 -- machine is currently under going maintenance.
			EMPED:16 -- temporary broken by EMP pulse

Class Procs:
	Initialize(mapload)                     'game/machinery/machine.dm'

	Destroy()                     'game/machinery/machine.dm'

	get_power_usage()            'game/machinery/machinery_power.dm'
		Returns the amount of power this machine uses every machine pipeline frame.
		Default definition uses 'use_power', 'active_power_usage', 'idle_power_usage'

	powered(chan = CURRENT_CHANNEL)         'game/machinery/machinery_power.dm'
		Checks to see if area that contains the object has power available for power
		channel given in 'chan'.

	use_power_oneoff(amount, chan=CURRENT_CHANNEL)   'game/machinery/machinery_power.dm'
		Deducts 'amount' from the power channel 'chan' of the area that contains the object.

	power_change()               'game/machinery/machinery_power.dm'
		Called by the area that contains the object when ever that area under goes a
		power state change (area runs out of power, or area channel is turned off).

	RefreshParts()               'game/machinery/machine.dm'
		Called to refresh the variables in the machine that are contributed to by parts
		contained in the component_parts list. (example: glass and material amounts for
		the autolathe)

		Default definition does nothing.

	assign_uid()               'game/machinery/machine.dm'
		Called by machine to assign a value to the uid variable.

	process()                  'game/machinery/machine.dm'
		Called by the 'master_controller' once per game tick for each machine that is listed in the 'machines' list.

	Compiled by Aygar
*/

/obj/machinery
	material_template = /datum/material_template/machine_part
	material_total = 5 * SHEET_MATERIAL_AMOUNT
	name = "machinery"
	silicon_use = SILICON_USE_HAND
	icon = 'icons/obj/stationobjs.dmi'
	w_class = ITEMSIZE_NO_CONTAINER
	layer = UNDER_JUNK_LAYER

	var/use_power = USE_POWER_IDLE
		//0 = dont run the auto
		//1 = run auto, use idle
		//2 = run auto, use active
	var/idle_power_usage = 0
	var/active_power_usage = 0
	var/power_channel = EQUIP //EQUIP, ENVIRON or LIGHT
	var/tmp/power_init_complete = FALSE
	/// Re-checks power (power_change()) when its area's channels change.
	/// Lights listen on the reactor key instead.
	var/power_subscriber = TRUE
	/// Cache of the real part objects once materialize_parts() has pulled
	/// them out of the CONTAINER_SLOT_INTERNALS latent entries (roadmap C6):
	/// null until then. The circuit board is not in this list; see `circuit`.
	var/list/component_parts = null
	latent_contents = TRUE
	var/tmp/uid
	var/global/gl_uid = 1
	var/clicksound			// sound played on succesful interface. Just put it in the list of vars at the start.
	var/clickvol = 40		// volume
	var/interact_offline = 0 // Can the machine be interacted with while de-powered.
	var/obj/item/circuitboard/circuit = null
	/// Bitfield of MACHINE_MAINT_*: which Maintainable interactions this machine offers (machinery_maintenance.dm).
	var/maintenance_flags = NONE
	/// Time spent securing or unsecuring this machine; zero is immediate.
	var/maintenance_wrench_time = 0
	/// Time spent welding a damaged machine back to full integrity.
	var/maintenance_weld_time = 2 SECONDS
	/// Inspectable material makeup retained from the frame and installed parts.
	var/list/material_component_manifest
	/// Whole-machine EMP rejection supplied by insulating component materials.
	var/material_emp_resistance = 0
	/// Monotonic diagnostic counter for exact dependency-wake assertions.
	var/tmp/gas_dependency_wake_count = 0


	blocks_emissive = EMISSIVE_BLOCK_GENERIC
TRACKED(/obj/machinery, active_power_usage)
TRACKED(/obj/machinery, power_channel)

CAPABILITIES(/obj/machinery)
	contributes(STAT_OPERABLE, TYPE_PROC_REF(/obj/machinery, stat_bits_allow), reason = MSG(machine/inoperable), reads = list("stat"))
	owns_one(nameof(circuit), /obj/item/circuitboard)
	owns_many(nameof(component_parts))
	param(nameof(dir_at_make), pos = 1, keep = FALSE)
	section(maintenance, "The panel, deconstruct, secure and weld repair that the type's maintenance_flags offer (machinery_maintenance.dm)")
	op("machine_panel", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT - 1), wait(0), label("Open maintenance panel"),
		when(req(PROC_REF(maint_offers_panel))), when(cond_not(nameof(panel_open))), says(MSG(interaction/maintenance_panel/open)), then(PROC_REF(toggle_maintenance_panel)))
	op("machine_panel_close", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT - 1), wait(0), label("Close maintenance panel"),
		// ALLOW(door_gates): the legacy machine panel is the panel_open var, not a capability space an op could be placed in
		when(req(PROC_REF(maint_offers_panel))), when(nameof(panel_open)), says(MSG(interaction/maintenance_panel/close)), then(PROC_REF(toggle_maintenance_panel)))
	op("machine_deconstruct", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT - 1), wait(0), label("Deconstruct"), when(req(PROC_REF(maint_offers_frame))),
		needs(req(PROC_REF(maintenance_panel_open), because = MSG(interaction/maintenance_panel/closed))), then(PROC_REF(maintenance_deconstruct)))
	op("machine_anchor", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT - 1), wait(PROC_REF(maintenance_wrench_wait)), label("Secure"),
		when(req(PROC_REF(maint_offers_wrench))), when(cond_not(nameof(anchored))), needs(req(PROC_REF(maintenance_panel_shut), because = MSG(interaction/maintenance_panel/opened))),
		begins(MSG(start/interaction/machine_anchor/secure)), says(MSG(interaction/machine_anchor/secure)), then(PROC_REF(toggle_maintenance_anchor)))
	op("machine_unanchor", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT - 1), wait(PROC_REF(maintenance_wrench_wait)), label("Unsecure"),
		when(req(PROC_REF(maint_offers_wrench))), when(nameof(anchored)), needs(req(PROC_REF(maintenance_panel_shut), because = MSG(interaction/maintenance_panel/opened))),
		begins(MSG(start/interaction/machine_anchor/unsecure)), says(MSG(interaction/machine_anchor/unsecure)), then(PROC_REF(toggle_maintenance_anchor)))
	op("machine_repair", lit_welder(fuel = 0), priority(OP_PRIORITY_DEFAULT - 1), wait(PROC_REF(maintenance_weld_wait)), label("Repair"), when(req(PROC_REF(maint_offers_repair))),
		needs(req(PROC_REF(maintenance_is_damaged), because = MSG(interaction/machine_repair/intact))), says(MSG(interaction/machine_repair)), then(PROC_REF(maintenance_repair)))

REGISTRY_MEMBERSHIP(/obj/machinery, REGISTRY_MACHINES)

/// The board plus its req_components, as a spawn list (roadmap C6): resolved
/// lazily into latent entries in CONTAINER_SLOT_INTERNALS the first time
/// anything asks the ledger an exact question (RefreshParts's rating reads
/// included), so a mapped machine's board and parts stay data at boot.
/obj/machinery/latent_generator()
	if(!circuit)
		return null
	var/list/gen = list()
	gen[circuit] = 1
	var/list/req = dq_type_var(circuit, "req_components")
	for(var/comp_path in req)
		var/comp_amt = req[comp_path]
		if(comp_amt)
			gen[comp_path] = (gen[comp_path] || 0) + comp_amt
	return gen

/// The facing a machine is built with (its constructor param).
/obj/machinery/var/dir_at_make // ALLOW(base_vars): param() carries the constructor's facing into init through a var of the type it declares

// ALLOW(init/INSTANCE_STATE): a machine faces the way it is built and, made after the map, checks its power
/obj/machinery/Initialize(mapload)
	. = ..()
	if(starts_switched_off())
		set_switched_on(FALSE)
	if(starts_broken())
		set_broken_condition(TRUE)
	if(isnum(dir_at_make))
		set_dir(dir_at_make)
	// The board stays a type path (roadmap C6): it is only ever materialized
	// into a real /obj/item/circuitboard when something needs the physical
	// item (deconstruction, admin var edit, a frame move). See
	// materialize_circuit().
	if(!mapload)
		power_change()

// the base machine: board and parts deleted, occupants put out.
/obj/machinery/on_destroy(force)
	om_watch_disarm_all(src)
	// The installed board is DECLARE_REF(..., OWNED) (phase 4 deletes it); every other leftover in the
	// internals slot (SLOT_DROP_HOLDER) is deleted by the core /atom/movable Destroy().
	// Only a human stuck in the internals slot is put out by hand: it needs its view
	// reset, which no slot policy does.
	// ALLOW(latent): only materialized mobs are wanted here, and a mob is never a latent ledger entry
	for(var/mob/living/carbon/human/H in contents)
		H.forceMove(loc)
		H.reset_perspective()
	..()

/// TRUE for a type that is made with its own switch off (cookers).
/obj/machinery/proc/starts_switched_off()
	return FALSE

/// TRUE for a type that is made broken (a wreck placed as a warning).
/obj/machinery/proc/starts_broken()
	return FALSE

/// The declared start condition of a machine's started work (started_work(starts = PROC_REF(step_start_condition))): TRUE when it has work
/// right away at initialization (mapped on, holding fuel, timing). Default FALSE.
/obj/machinery/proc/step_start_condition()
	return FALSE

/obj/machinery/emp_act(severity, recursive)
	if(material_emp_resistance && prob(material_emp_resistance))
		return EMP_PROTECT_ALL
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	if(use_power && !has_condition())
		use_power(7500/severity)

		var/obj/effect/overlay/pulse2 = new /obj/effect/overlay(src.loc)
		pulse2.icon = 'icons/effects/effects.dmi'
		pulse2.icon_state = "empdisable"
		pulse2.name = "emp sparks"
		pulse2.set_anchored(TRUE)
		pulse2.set_dir(pick(GLOB.cardinal))
		pulse2.expire(1 SECOND)

/obj/machinery/vv_edit_var(var_name, new_value)
	if(var_name == NAMEOF(src, use_power))
		set_use_power(new_value)
		return TRUE
	else if(var_name == NAMEOF(src, power_channel))
		update_power_channel(new_value)
		return TRUE
	else if(var_name == NAMEOF(src, idle_power_usage))
		update_idle_power_usage(new_value)
		return TRUE
	else if(var_name == NAMEOF(src, active_power_usage))
		update_active_power_usage(new_value)
		return TRUE
	return ..()

/// Reads var_name's declared value for a bare type `path` (roadmap C6): one
/// transient instance, made and qdel'd once per (path, var_name) and cached
/// after that. `path` might be any subtype (a stock part, a circuit board, an
/// smes_coil, ...), so a typed local can't be used to read it -- a typed
/// local's `.` member access binds to its DECLARED type at compile time,
/// which for a subtype path silently reads the wrong (base type's) value.
/// The `:` operator would dispatch correctly, but AGENTS.md §3b forbids it
/// for subtype access; this reads the same data through a real instance and
/// the built-in per-datum `vars` list instead, which is always dynamic.
/proc/dq_type_var(path, var_name)
	// A caller may already hold a materialized instance (the board, once
	// materialize_parts() resolved it) rather than a bare path: read it
	// directly, since it already IS "a real instance" of its own exact type.
	if(!ispath(path))
		var/atom/instance = path
		return instance?.vars[var_name]
	var/static/list/cache = list() // ALLOW(cache): type-var probe; values can be shared type-default lists handed to callers that may mutate
	var/cache_key = "[path]#[var_name]"
	if(cache_key in cache)
		return cache[cache_key]
	// The probe instance is kept alive (never qdel'd), one per path, reused
	// across every var_name asked of it. A list-valued var (req_components)
	// is very often the SAME shared list reference as every other instance
	// of that type gets by default (DM does not deep-copy a `list(...)`
	// compile-time default per instance) -- qdel'ing the probe could run
	// Destroy() cleanup that clears that list in place and corrupt it for
	// every real instance of the type, not just this throwaway one.
	var/static/list/probes = list()
	var/atom/instance = probes[path]
	if(!instance)
		instance = new path
		probes[path] = instance
	var/value = instance.vars[var_name]
	cache[cache_key] = value
	return value

/// Returns the sum of the rating values of all installed parts that are
/// subtypes of part_type (roadmap C6): real objects already materialized in
/// CONTAINER_SLOT_INTERNALS, plus latent entries not yet materialized there.
/obj/machinery/proc/total_component_rating_of_type(part_type)
	. = 0
	for(var/obj/item/stock_parts/P in slot_contents(CONTAINER_SLOT_INTERNALS))
		if(istype(P, part_type))
			. += P.rating
	for(var/datum/latent_entry/entry as anything in latent_entries(CONTAINER_SLOT_INTERNALS))
		if(ispath(entry.path, part_type))
			. += dq_type_var(entry.path, "rating") * entry.count

/// Alias of total_component_rating_of_type(), named to match get_part_count().
/obj/machinery/proc/get_part_rating(part_type)
	return total_component_rating_of_type(part_type)

/// Returns how many installed parts are subtypes of part_type: real objects
/// plus latent entries, in CONTAINER_SLOT_INTERNALS (roadmap C6).
/obj/machinery/proc/get_part_count(part_type)
	. = 0
	for(var/obj/item/stock_parts/P in slot_contents(CONTAINER_SLOT_INTERNALS))
		if(istype(P, part_type))
			.++
	for(var/datum/latent_entry/entry as anything in latent_entries(CONTAINER_SLOT_INTERNALS))
		if(ispath(entry.path, part_type))
			. += entry.count

/// Materializes the board (roadmap C6): if `circuit` is still a type path,
/// pulls the real board (and every other latent entry in
/// CONTAINER_SLOT_INTERNALS) out through the ledger. Idempotent.
/obj/machinery/proc/materialize_circuit()
	if(ispath(circuit))
		materialize_parts()
	return circuit

/// Materializes every latent entry in CONTAINER_SLOT_INTERNALS (roadmap C6):
/// the board becomes `circuit`, everything else becomes `component_parts`. A
/// no-op once component_parts is already a real list, so it's safe to call
/// defensively before anything that reads or moves real parts: deconstruction,
/// an RPED swap, admin var edits.
/obj/machinery/proc/materialize_parts()
	if(component_parts)
		return
	latent_materialize_all(CONTAINER_SLOT_INTERNALS)
	rel_take(src, nameof(component_parts))
	for(var/obj/item/I in slot_contents(CONTAINER_SLOT_INTERNALS))
		if(owner_of(I)) // already held by a var (an APC's cell, a camera's assembly): not a loose part
			continue
		if(istype(I, /obj/item/circuitboard))
			rel_set(src, nameof(circuit), I)
		else
			rel_add(src, nameof(component_parts), I)

// Duplicate of below because we don't want to fuck around with CanUseTopic in TGUI
// TODO: Replace this with can_interact from /tg/
/obj/machinery/tgui_status(mob/user)
	if(!interact_offline && (!operable()))
		return STATUS_CLOSE
	return ..()

/obj/machinery/CanUseTopic(mob/user)
	if(!interact_offline && (!operable()))
		return STATUS_CLOSE
	return ..()

////////////////////////////////////////////////////////////////////////////////////////////

/// Machines take the AI's Use as a hand's (silicon_use), but a cyborg looking
/// through a camera can't remotely control them (old /obj/machinery/attack_ai). Offered
/// only while that holds, so it doesn't compete with a machine's own silicon interactions.
/// machinery_maintenance.dm declares the machine's other interactions.
EXTEND_INTERACTIONS(/obj/machinery, INTERACT_ROBOT("Blocked", TYPE_PROC_REF(/atom, interaction_swallow), REQ_TARGET_STATE(/obj/machinery/proc/machinery_robot_remote_locked)))

/obj/machinery/proc/machinery_robot_remote_locked(mob/actor, atom/target, obj/item/held)
	return isrobot(actor) && actor.is_remote_viewing()

/// The checks every machine's hand interactions pass behind (see machine_use_blocker() for the Menu's version).
/obj/machinery/hand_gate(mob/user as mob)

	if(!operable())
		return 1
	if(user.lying || user.stat)
		return 1
	if(!user.IsAdvancedToolUser())
		to_chat(user, span_warning("You don't have the dexterity to do this!"))
		return 1
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.injury_load(INJURY_CATEGORY_NEURAL) >= 55)
			visible_message(span_warning("[H] stares cluelessly at [src]."))
			return 1
		else if(prob(H.injury_load(INJURY_CATEGORY_NEURAL)))
			to_chat(user, span_warning("You momentarily forget how to use [src]."))
			return 1

	if(clicksound && istype(user, /mob/living/carbon))
		playsound(src, clicksound, clickvol)

	add_fingerprint(user)

	return ..()

MSG_DEF_SELF(machine/not_working, "It isn't working.")
MSG_DEF_SELF(machine/cant_reach, "You can't reach it like this.")
MSG_DEF_SELF(machine/no_dexterity, "You don't have the dexterity.")

/// The hand needs what the machinery hand gate needs: power, posture and dexterity.
/obj/machinery/proc/hand_ok(datum/act/op/A)
	return isnull(hand_refusal(A))

/obj/machinery/op_hand_refusal(datum/act/op/A)
	return hand_refusal(A)

/obj/machinery/proc/hand_refusal(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return /datum/msg/machine/not_working
	if(user?.lying || user?.stat) // ALLOW(reads): posture is read when the touch is tried; a cached menu entry is advisory
		return /datum/msg/machine/cant_reach
	if(!user?.IsAdvancedToolUser())
		return /datum/msg/machine/no_dexterity
	return null

/// The parts changed: a machine recomputes what its parts rate (until the machine track turns this into components(slots)).
/obj/machinery/proc/RefreshParts()
	return

/// Finalize the physical machine from its real installed parts. Individual
/// machines still calculate functional ratings in RefreshParts(); this common
/// pass retains their materials and supplies chassis/EMP behavior.
/obj/machinery/proc/finalize_material_assembly()
	material_component_manifest = list()
	var/total_integrity = 0
	var/total_dielectric = 0
	var/part_count = 0
	for(var/obj/item/part as anything in component_parts)
		var/datum/material/material = part.primary_construction_material() || part.get_material()
		if(!material)
			continue
		part_count++
		total_integrity += material.integrity
		total_dielectric += material.dielectric_strength
		material_component_manifest += "[part.name]: [material.display_name]"
	if(!part_count)
		return FALSE
	var/integrity_factor = clamp((total_integrity / part_count) / 150, 0.5, 2.5)
	max_integrity = max(1, round(initial(max_integrity) * integrity_factor))
	if(uses_integrity)
		update_integrity(max_integrity)
	material_emp_resistance = clamp(round(total_dielectric / part_count * 0.6), 0, 75)
	return TRUE

/obj/machinery/examine(mob/user)
	. = ..()
	if(length(material_component_manifest))
		. += span_notice("Installed material parts: [jointext(material_component_manifest, "; ")].")

/obj/machinery/proc/assign_uid()
	uid = gl_uid
	gl_uid++

/obj/machinery/proc/state(msg)
	for(var/mob/O in hearers(src, null))
		O.show_message("[icon2html(src,O.client)] " + span_notice("[msg]"), 2)

/obj/machinery/proc/ping(text=null)
	if(!text)
		text = "\The [src] pings."

	state(text, "blue")
	play_sfx(src, SFX_MACHINES_PING)

/obj/machinery/proc/shock(mob/user, prb)
	if(!operable())
		return 0
	if(!prob(prb))
		return 0
	fx_sparks(src, 5)
	if(electrocute_mob(user, get_area(src), src, 0.7))
		var/area/temp_area = get_area(src)
		if(temp_area)
			var/obj/machinery/power/apc/temp_apc = temp_area.get_apc()

			if(temp_apc && temp_apc.terminal && temp_apc.terminal.power_region)
				power_warn(temp_apc.terminal.power_region)
		if(user.has_status(STAT_STUNNED))
			return 1
	return 0

/// Kept for the ~85 existing call sites in individual machines' Initialize().
/// There is nothing left to build eagerly (roadmap C6): the board and its
/// req_components are declared through latent_generator() and resolved into
/// CONTAINER_SLOT_INTERNALS entries lazily, the first time anything (this
/// RefreshParts() call included) asks the ledger an exact question.
/obj/machinery/proc/default_apply_parts()
	rel_take(src, nameof(component_parts))
	RefreshParts()

/obj/machinery/proc/default_use_hicell()
	materialize_parts()
	var/obj/item/cell/C = locate_in_list(component_parts, /obj/item/cell)
	if(C)
		own_take_member(src, nameof(component_parts), C)
		spent(C)
		// Made in nullspace: new(src) already put it inside, and the move then refused ("it is already there").
		C = new /obj/item/cell/high()
		move_into(src, CONTAINER_SLOT_INTERNALS, C)
		rel_add(src, nameof(component_parts), C)
		RefreshParts()
		return C

/obj/machinery/proc/default_part_replacement(mob/user, obj/item/storage/part_replacer/R)
	var/parts_replaced = FALSE
	if(!istype(R))
		return 0
	if(!circuit)
		return 0
	materialize_parts()
	to_chat(user, span_notice("Following parts detected in [src]:"))
	for(var/obj/item/C in component_parts)
		to_chat(user, span_notice("    [C.name]"))
	if(panel_open || global.panel_open(src) || !R.panel_req) // the legacy panel var, or the panel() capability's key
		var/list/req = dq_type_var(circuit, "req_components")
		var/P
		for(var/obj/item/A in component_parts)
			for(var/T in req)
				if(ispath(A.type, T))
					P = T
					break
			for(var/obj/item/B in contents_of(R))
				if(istype(B, P) && istype(A, P))
					if(B.get_rating() > A.get_rating())
						R.remove_from_storage(B, src, user)
						R.insert_item(A, user, TRUE)
						own_take_member(src, nameof(component_parts), A)
						move_into(src, CONTAINER_SLOT_INTERNALS, B, user)
						own_move(B, src, nameof(component_parts))
						to_chat(user, span_notice("[A.name] replaced with [B.name]."))
						parts_replaced = TRUE
						break
			update_icon()
		RefreshParts()
		if(parts_replaced)
			R.play_rped_sound()
	return 1

// This is it's own proc so it can be more easily found when looking for machines that can upgrade themselves from mapped parts
// Called from a mapped machine's after_init() pass
/obj/machinery/proc/apply_mapped_upgrades()
	return

/// Focused-hook implementation for monitor-style machines that dismantle directly
/// rather than exposing a maintenance panel.
MSG_DEF_SELF(machine/display_disconnecting, "You start disconnecting the monitor.")

/// A wall display's screwdriver (status displays, holopads, newscasters, account terminals): after 2 s the monitor comes off its board.
/// With no board the click is taken and nothing happens. Declared by each display: op("disconnect_display", ...) below.
/proc/display_disconnect_op()
	return op("disconnect_display", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(2 SECONDS), label("Disconnect monitor"),
		needs(req(TYPE_PROC_REF(/obj/machinery, has_board), silent = TRUE)), begins(MSG(machine/display_disconnecting)), then(TYPE_PROC_REF(/obj/machinery, display_disconnected)))

/obj/machinery/proc/has_board(datum/act/op/A)
	return !!circuit

/obj/machinery/proc/display_disconnected(datum/act/op/A)
	if(broken_now())
		to_chat(A.actor, span_notice("The broken glass falls out."))
		new /obj/item/material/shard(loc)
	else
		to_chat(A.actor, span_notice("You disconnect the monitor."))
	return dismantle() ? OP_OK : OP_DECLINE

/obj/machinery/proc/dismantle()
	PUBLISH_LEGACY(src, /datum/notice/obj_deconstruct, FALSE)
	play_sfx(src, SFX_ITEMS_CROWBAR)
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/I in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		if(istype(I,/obj/item/card/id))
			I.forceMove(src.loc)

	if(!circuit)
		return 0
	materialize_circuit()
	materialize_parts()
	var/obj/structure/frame/A = new /obj/structure/frame(src.loc)
	var/obj/item/circuitboard/M = circuit
	M.forceMove(A)
	own_move(M, A, nameof(A.circuit)) // the board moves from the machine to the frame (CONTAINED there)
	A.set_anchored(TRUE)
	rel_set(A, nameof(A.frame_type), frame_type_copy(M.board_type)) // the board keeps its own
	if(A.frame_type.circuit)
		A.need_circuit = 0

	if(A.frame_type.frame_class == FRAME_CLASS_ALARM || A.frame_type.frame_class == FRAME_CLASS_DISPLAY)
		A.set_density(FALSE)
	else
		A.set_density(TRUE)

	if(A.frame_type.frame_class == FRAME_CLASS_MACHINE)
		for(var/obj/D in component_parts)
			D.forceMove(src.loc)
		if(A.components)
			rel_take(A, nameof(A.components))
		else
			rel_take(A, nameof(A.components))
		rel_take(src, nameof(component_parts))
		A.check_components()

	if(A.frame_type.frame_class == FRAME_CLASS_ALARM)
		A.state = FRAME_FASTENED
	else if(A.frame_type.frame_class == FRAME_CLASS_COMPUTER || A.frame_type.frame_class == FRAME_CLASS_DISPLAY)
		if(broken_now())
			A.state = FRAME_WIRED
		else
			A.state = FRAME_PANELED
	else
		A.state = FRAME_WIRED

	A.set_dir(dir)
	A.pixel_x = pixel_x
	A.pixel_y = pixel_y
	A.update_desc()
	A.update_icon()
	M.atom_deconstruct(TRUE, src) // the board stays in the frame (its CONTAINED circuit)
	destroyed(src, null, "deconstructed")
	return 1

/**
 * Machinery contents are the deterministic salvage from structural destruction.
 * /obj/deconstruct() moves those contents to the turf after this hook. Detach the
 * bookkeeping references first so Destroy() neither deletes the salvaged parts
 * nor reports them as stale component_parts.
 */
/obj/machinery/atom_deconstruct(disassembled = TRUE)
	// Real objects must exist to be scattered as salvage by /obj/deconstruct()'s
	// generic contents-to-turf pass, so materialize before letting go of them.
	materialize_circuit()
	materialize_parts()
	rel_take(src, nameof(component_parts))
	rel_take(src, nameof(circuit))
	return ..()

/obj/machinery/atom_destruction(damage_flag)
	if(dq_destroy_effects_once(src)) // one per turf per blast (lifecycle/batch.dm)
		play_sfx(src, SFX_MACHINES_MACHINE_DIE_SHORT)
		fx_sparks(src, 5, FALSE)
	return ..()

/**
 * The one machinery break (damage.md §6), and the only writer of BROKEN: the integrity state (G8). Sets BROKEN,
 * then the parent publishes INTEGRITY_KEY_BROKEN, then emits machinery_broken. Returns TRUE if the machine was not
 * already broken. Subtypes with real behaviour call this first and act on the result; an override that only sets
 * flags is forbidden (tools/ci/check_breakpoints.sh).
 */
/obj/machinery/atom_break(damage_flag)
	var/flipped = set_broken_condition(TRUE) // raises CHANGE_MACHINE_BROKEN
	..()
	if(!flipped)
		return FALSE
	PUBLISH_LEGACY(src, /datum/notice/machinery_broken, damage_flag)
	update_icon()
	return TRUE

/// The inverse of atom_break(), the other writer of BROKEN. Returns TRUE if the machine was broken.
/obj/machinery/atom_fix()
	var/flipped = set_broken_condition(FALSE) // raises CHANGE_MACHINE_BROKEN
	..()
	return flipped ? TRUE : FALSE

// ---------------------------------------------------------------- configuration prompts (om_ask)

/// Asks for a new radio frequency; frequency_entered() applies it through the machine's set_frequency().
/obj/machinery/proc/ask_frequency(mob/user, current)
	open_request(src, /datum/prompt/number, PROC_REF(frequency_entered), answerer = user, title = "[src] frequency", question = "[src] has a frequency of [current]. What would you like it to be?", default = current, max_value = RADIO_HIGH_FREQ, min_value = RADIO_LOW_FREQ, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)

/obj/machinery/proc/frequency_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/new_frequency = A.answer.value
	if(!new_frequency || !hascall(src, "set_frequency"))
		return
	call(src, "set_frequency")(sanitize_frequency(new_frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ))

/// Asks for a new value of a text var (a tag, a command); an empty answer keeps the old one.
/obj/machinery/proc/ask_text_var(mob/user, var_name, message, title, max_length = MAX_NAME_LEN)
	open_request(src, /datum/prompt/text/machine_var, PROC_REF(text_var_entered), answerer = user, title = title, question = message, default = vars[var_name], max_len = max_length, name_text = (max_length <= MAX_NAME_LEN), var_name = var_name, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)

/// A question about one text var of a machine: the var's name is kept on it.
/datum/prompt/text/machine_var
	/// The machine var the answer is written to.
	var/var_name

/obj/machinery/proc/text_var_entered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/datum/prompt/text/machine_var/R = A.request
	vars[R.var_name] = A.answer.value // ALLOW(api): the asked var is named by the question, so the write is by name; ask_text_var() callers pass their own var


/// The maintenance panel is open.
OM_FIELD(/obj/machinery, panel_open, FALSE, CHANGE_MACHINE_PANEL)

/// Who is in the machine's sealed occupant slot `slot_id` (a /datum/om/relation/slot/occupant), or null. The accessor requirements read: the slot
/// publishes OCCUPANT_KEY when someone gets in or out (code/datums/containment/occupant_slot.dm), so a cached menu follows it.
/obj/machinery/proc/slot_occupant(slot_id)
	return slot_item(slot_id)

READS_AS(/obj/machinery/proc/slot_occupant, OCCUPANT_KEY)

/// The machine's maintenance panel is shut (a legacy machine panel, maintenance_flags; not a capability door): the requirement of an op
/// that must not reach into an open machine.
/obj/machinery/proc/maintenance_panel_shut(datum/act/op/A)
	return !panel_open

/// The machine's maintenance panel is open (a legacy machine panel): an op that works on what is behind it.
/obj/machinery/proc/maintenance_panel_open(datum/act/op/A)
	return panel_open
