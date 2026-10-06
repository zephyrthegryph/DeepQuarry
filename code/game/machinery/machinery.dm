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
	/// Monotonic diagnostic counter: MACHINE_WAKE() calls on this machine.
	var/tmp/machine_wake_count = 0
	/// Set when the machine is told what to do (MACHINE_WAKE(), sleep_until_keys()) while its first
	/// wake is still pending (first_wake_pending()): that direction replaces the declared start condition.
	var/tmp/materialize_directed = FALSE
	/// TRUE for a type whose machine_step() reconciles its state with its power: every power or
	/// break change (power_change(), atom_break(), atom_fix()) runs one step.
	var/step_on_power_change = FALSE


	blocks_emissive = EMISSIVE_BLOCK_GENERIC
TRACKED(/obj/machinery, active_power_usage)
TRACKED(/obj/machinery, power_channel)

CAPABILITIES(/obj/machinery)
	owns_one(nameof(circuit), /obj/item/circuitboard)
	owns_many(nameof(component_parts))
	param(nameof(dir_at_make), pos = 1, keep = FALSE)

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
	if(isnum(dir_at_make))
		set_dir(dir_at_make)
	// The board stays a type path (roadmap C6): it is only ever materialized
	// into a real /obj/item/circuitboard when something needs the physical
	// item (deconstruction, admin var edit, a frame move). See
	// materialize_circuit().
	// Machines start asleep (roadmap S5): a type with machine_step() work joins the machine
	// pipeline through /datum/om/decl/pipeline_machines, gets one frame to find out whether it
	// has anything to do, and parks until a wake (MACHINE_WAKE(), its channels or watches).
	if(!mapload)
		power_change()

/// A machine in fast mode (speed_process) runs machine_step() on the fast periodic pipeline while
/// it is live. A subtype's MACHINE_PIPELINE declaration replaces this one and its runtime moves the
/// work between the machine pipeline and the fast lane on speed_process (code/datums/sys/periodic.dm).
DECLARE_PERIODIC_WHILE(/obj/machinery, PERIODIC_FAST, "speed_process")

// the base machine: board and parts deleted, occupants put out.
/obj/machinery/on_destroy(force)
	cancel_sleep_keys()
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

/// One frame of DM-side work for a machine on the machine pipeline (machine_pipeline.dm,
/// /datum/om/stage/machine/power/step): the same contract process() had on SSmachines' roster.
/// Return PROCESS_KILL when there is nothing left to do -- the stage idles and the machine parks
/// until a channel (power_change(), settings, MACHINE_WAKE()) or a gas watch wakes it.
/// Anything else keeps it running every MACHINE_PIPELINE_INTERVAL.
/obj/machinery/proc/machine_step()
	set waitfor = FALSE // ALLOW(scheduler): core dispatch hook: guards the machine pipeline against an override that still sleeps
	return PROCESS_KILL

/// Once, when a machine on the machine pipeline materializes and the world is up (a zero-delay
/// after() from joining): arm the watches that will wake it (arm_wakes()), then wake it if its
/// declared start condition holds. Nothing else runs a machine at spawn.
/obj/machinery/proc/materialize_wakes()
	// Running now: it leaves the boot bulk queue (a timer-slot run has already left its slot).
	rel_remove(om_global_owner(), nameof(/datum/om/global_owner::machine_first_wakes), src)
	var/directed = materialize_directed
	materialize_directed = FALSE
	if(QDELETED(src))
		return
	arm_wakes()
	// The start condition stands in for a first wake nobody gave. A machine already woken, or put
	// to sleep on its keys, since it joined has had its first word: waking it again here would be
	// a spurious wake of a machine whose input held steady.
	if(!directed && step_start_condition())
		MACHINE_WAKE(src)

/// TRUE while this machine's first wake (materialize_wakes()) has not run yet: it waits in the
/// boot bulk queue, or in its `first_wake` timer slot. Derived, never stored: firing, cancelling
/// and deletion all end it on their own (a deleted machine's handle stops resolving).
/obj/machinery/proc/first_wake_pending()
	// rel_names(): the boot queue holds every machine, so a list scan here made the bulk pass quadratic.
	return om_timer_slot_pending(src, "first_wake") || rel_names(om_global_owner(), nameof(/datum/om/global_owner::machine_first_wakes), src)

/// Arms what wakes this machine later (gas watches, change watches). Default: nothing to arm.
/obj/machinery/proc/arm_wakes()
	return

/// The declared start condition: TRUE when a freshly materialized machine has work right away
/// (mapped on, holding fuel, timing). Default FALSE: machines start asleep.
/obj/machinery/proc/step_start_condition()
	return FALSE

/// A machine in fast mode (speed_process) runs its machine_step() on the fast periodic pipeline.
/obj/machinery/periodic_step(delta)
	// A declared MACHINE_PIPELINE state that doesn't hold ends fast mode too; its declaration
	// restarts it when the state holds again (code/datums/sys/periodic.dm).
	if(!sys_periodic_allows(src, MACHINE_PIPELINE))
		return PROCESS_KILL
	return machine_step()

/// Gives `M` step work: the machine pipeline runs its machine_step() from the next frame until
/// it returns PROCESS_KILL. Joins the pipeline if `M` isn't on it yet (machines start asleep).
/proc/machine_wake(obj/machinery/M)
	if(!M || QDELETED(M))
		return
	// A machine whose work is declared (started_work(), code/library/machine/started_work.dm) is started there.
	if(work_start(M))
		return
	// A DECLARE_PERIODIC_WHILE(..., MACHINE_PIPELINE, ...) whose state doesn't hold refuses (code/datums/sys/periodic.dm).
	if(!sys_periodic_allows(M, MACHINE_PIPELINE))
		return
	M.machine_wake_count++
	M.set_step_active(TRUE)
	M.set_step_waiting_power(FALSE)
	if(!om_attached(M, /datum/om/pipeline/machine))
		om_attach(M, /datum/om/pipeline/machine)
		// Joined asleep (on_start); this wake is the reason it joined, so it is awake now.
		var/datum/om/frame/S = om_pipe_state(M, /datum/om/pipeline/machine)
		if(S)
			om_pipe_set_all(S, FALSE, 0)
	if(M.first_wake_pending())
		M.materialize_directed = TRUE
	om_wake(M, /datum/om/pipeline/machine)

/// Ends `M`'s step work until the next MACHINE_WAKE(): its step stage idles and it parks.
/proc/machine_sleep(obj/machinery/M)
	if(work_stop(M))
		return
	if(M)
		M.set_step_active(FALSE)
		M.set_step_waiting_power(FALSE)

/// For machine_step(): the machine can't act without power (or while broken). Ends its step work
/// until power returns and it is whole (power_change(), atom_fix()), then it runs again. Returns
/// PROCESS_KILL: `return sleep_until_powered()`.
/obj/machinery/proc/sleep_until_powered()
	if(cap_of(src, CAP_STARTED_WORK))
		return work_wait_for_power(src)
	set_step_waiting_power(TRUE)
	return PROCESS_KILL

/// A player (or program) changed the machine through an interaction or its UI: a machine with step
/// work re-evaluates it next frame (its machine_step() says whether there is anything to do).
/obj/machinery/interaction_ran(mob/actor, datum/interaction/interaction)
	if(om_attached(src, /datum/om/pipeline/machine))
		MACHINE_WAKE(src)

/// TRUE while `M` has step work on the machine pipeline (it was: on SSmachines' roster).
/proc/machine_stepping(obj/machinery/M)
	return M.step_active && om_attached(M, /datum/om/pipeline/machine)

/// TRUE when machine_step() would have work to do right now: the device's own eligibility rule,
/// the same test its gas watch arms. The machine pipeline's step stage reads it as its idle rule.
/// The default: whatever its last machine_step() said (anything but PROCESS_KILL keeps it running).
/obj/machinery/proc/step_has_work()
	return step_active

/obj/machinery/emp_act(severity, recursive)
	if(material_emp_resistance && prob(material_emp_resistance))
		return EMP_PROTECT_ALL
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	if(use_power && !has_stat(MACHINE_STAT_ANY))
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
	own_take_all(src, nameof(component_parts))
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

	if(!operable(MAINT))
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
	if(!operable(MAINT))
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
	own_take_all(src, nameof(component_parts))
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
/obj/machinery/proc/deconstruct_display(mob/user, obj/item/tool)
	if(!circuit)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, tool, src, delay = 2 SECONDS, volume = 50, start_self = "You start disconnecting the monitor.", receiver = src, on_done = PROC_REF(deconstruct_display_tool_done), done_args = list(user))
	return TRUE

/obj/machinery/proc/deconstruct_display_tool_done(mob/user)
	if(has_stat(BROKEN))
		to_chat(user, span_notice("The broken glass falls out."))
		new /obj/item/material/shard(loc)
	else
		to_chat(user, span_notice("You disconnect the monitor."))
	return dismantle() ? ITEM_INTERACT_SUCCESS : ITEM_INTERACT_BLOCKING

/obj/machinery/proc/dismantle()
	OM_EMIT(src, /datum/om/event/obj_deconstruct, FALSE)
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
			own_take_all(A, nameof(A.components))
		else
			own_take_all(A, nameof(A.components))
		own_take_all(src, nameof(component_parts))
		A.check_components()

	if(A.frame_type.frame_class == FRAME_CLASS_ALARM)
		A.state = FRAME_FASTENED
	else if(A.frame_type.frame_class == FRAME_CLASS_COMPUTER || A.frame_type.frame_class == FRAME_CLASS_DISPLAY)
		if(has_stat(BROKEN))
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
	own_take_all(src, nameof(component_parts))
	own_take(src, nameof(circuit))
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
	var/flipped = stat_add(BROKEN) // raises CHANGE_MACHINE_BROKEN
	..()
	if(!flipped)
		return FALSE
	OM_EMIT(src, /datum/om/event/machinery_broken, damage_flag)
	update_icon()
	return TRUE

/// The inverse of atom_break(), the other writer of BROKEN. Returns TRUE if the machine was broken.
/obj/machinery/atom_fix()
	var/flipped = stat_remove(BROKEN) // raises CHANGE_MACHINE_BROKEN
	..()
	return flipped ? TRUE : FALSE

// --- Sleeping until something changes (om_watch on change channels) ------------------------------

/obj/machinery
	/// While asleep on changes: the flat (entity, channel mask) pairs it watches. The machine's
	/// own settings (CHANGE_MACHINE_SETTINGS), power and repair also wake it.
	var/tmp/list/react_sleep_tokens

/**
 * Ends the machine's step work until one of `watches` (a flat list of entity, channel mask
 * pairs; empty for "only my own settings or power") changes. The wake arrives at the machine
 * pipeline's step stage as CHANGE_RELATED, which restarts the work.
 */
/obj/machinery/proc/sleep_until_keys(list/watches = list())
	cancel_sleep_keys()
	if(QDELETED(src))
		return FALSE
	if(!om_attached(src, /datum/om/pipeline/machine))
		om_attach(src, /datum/om/pipeline/machine)
	if(first_wake_pending())
		materialize_directed = TRUE
	react_sleep_tokens = watches.Copy()
	for(var/i = 1; i <= length(watches); i += 2)
		om_watch(src, watches[i], watches[i + 1], /datum/om/pipeline/machine)
		if(istype(watches[i], /datum/mob_chunk))
			GLOB.mob_chunk_watches++
	// ALLOW(sys_periodic_toggle): this is the sleep-on-keys primitive itself (ends step work until a watched key fires); react_sleep_tokens is its bookkeeping, not a state the work runs while
	MACHINE_SLEEP(src)
	return TRUE

/obj/machinery/proc/cancel_sleep_keys()
	if(isnull(react_sleep_tokens))
		return
	var/list/watches = react_sleep_tokens
	react_sleep_tokens = null
	for(var/i = 1; i <= length(watches); i += 2)
		om_unwatch(src, watches[i], /datum/om/pipeline/machine)
		if(istype(watches[i], /datum/mob_chunk))
			GLOB.mob_chunk_watches = max(GLOB.mob_chunk_watches - 1, 0)

/// TRUE while the machine sleeps on changes and has no step work.
/obj/machinery/proc/asleep_on_keys()
	return !isnull(react_sleep_tokens) && !step_active

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
