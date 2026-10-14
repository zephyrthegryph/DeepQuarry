// occupant_pod(slot, accepts =, enter_wait =, exit_to =, controls_inside =, eject_wait_inside =, shown_y =, bare =) (doc/rewrite/final_api.html,
// section 11 "Containers and slots": occupant(slot); section 16.4): a machine one person lies in, a sleeper, a cryo cell, a body scanner.
//
//   CAPABILITIES(/obj/machinery/bodyscanner)
//       occupant_pod(OCCUPANT_SLOT_BODY_SCANNER, bare = TRUE)
//   CAPABILITIES(/obj/machinery/sleeper)
//       occupant_pod(OCCUPANT_SLOT_SLEEPER, enter_wait = 2 SECONDS, controls_inside = nameof(controls_inside))
//       extend(TAG_POD_ENTER, needs(req_operable()))                        what the machine asks of every way in
//       when(STAT_OPERABLE, while_slotted(OCCUPANT_SLOT_SLEEPER, contributes(STAT_CLOCK_RATE_BIO, nameof(stasis_rate)), on = ON_CONTENTS))
//   CAPABILITIES(/obj/machinery/atmospherics/unary/cryo_cell)
//       occupant_pod(OCCUPANT_SLOT_CRYO, accepts = /mob/living/carbon, exit_to = SOUTH, controls_inside = FALSE, eject_wait_inside = 2 MINUTES,
//           shown_y = 19, bare = TRUE)
//
// The params:
//   slot               the pod's ledger slot (OCCUPANT_SLOT_*): one mob of `accepts`, sealed (the pod's shell is the occupant's environment: no gas, no
//                      heat, no blast reaches them), spilled onto the floor when the pod is destroyed.
//   enter_wait         how long putting someone in takes (the requirements are asked again when it ends: a pod that lost its power takes nobody).
//   exit_to            a direction: the occupant leaves onto the tile that way when it is open, else onto the pod's own tile. null: the pod's tile.
//   controls_inside    whether the occupant may work the pod's window (TRUE, FALSE, or nameof() a holder var that says).
//   eject_wait_inside  how long the occupant's own eject takes (a cryo cell's release sequence); an outsider's is at once.
//   shown_y            the occupant is shown in the pod (vis_contents), this many pixels up, facing south. null: hidden inside.
//   bare               the occupant may wear nothing abiotic.
//
// What it brings:
//   ops     occupant_pod.put_in           a mob dragged onto the pod (by itself: climbing in), after enter_wait
//           occupant_pod.put_in_grabbed   a grab used on the pod: the grabbed mob, after enter_wait; the grab is used up
//           occupant_pod.climb_in         "Move Inside" from the context menu
//           occupant_pod.eject            "Eject" from the context menu: an outsider at once, the occupant after eject_wait_inside
//           occupant_pod.busy_tools       a screwdriver or a crowbar while someone is inside: refused, "Someone is inside it."
//           The three ways in carry TAG_POD_ENTER, so one extend(TAG_POD_ENTER, needs(...)) says what the machine asks of them all.
//   move    the occupant pressing a direction gets out, when they can act (a while_slotted hook on their relay_movement action).
//   window  every TAG_UI op of the pod needs controls_inside when the actor is the occupant.
//   look    the part LOOK_OCCUPIED ("<base>-occupied", when the sprite has it) while someone is inside; with shown_y the occupant is drawn in
//           the pod's look (look.show()).
//   state   OCCUPANT_POD_OCCUPIED (a condition, occupant_pod_occupied(holder)) and OCCUPANT_KEY, published whenever someone gets in or out by any
//           path: an op, occupant_enter() or occupant_eject() from code, a raw slot move, a destroy spill, the occupant's deletion. The notices
//           /datum/notice/pod_entered and /datum/notice/pod_left (with .occupant) say who, for the machine's own on_notice() hooks.
//   reads   occupant_of(holder): who is inside, or null. occupant_enter(holder, M, actor) and occupant_eject(holder) from code.

MSG_DEF(occupant_pod/climbs_in, "You climb into %T%.", "%U% climbs into %T%.")
MSG_DEF(occupant_pod/puts_in, "You put %I% into %T%.", "%U% puts %I% into %T%.")
MSG_DEF(occupant_pod/puts_grabbed_in, "You put the one you are holding into %T%.", "%U% puts the one they are holding into %T%.")
MSG_DEF(occupant_pod/begins_climb, "You start climbing into %T%.", "%U% starts climbing into %T%.")
MSG_DEF(occupant_pod/begins_put, "You start putting %I% into %T%.", "%U% starts putting %I% into %T%.")
MSG_DEF(occupant_pod/begins_put_grabbed, "You start putting the one you are holding into %T%.", "%U% starts putting the one they are holding into %T%.")
MSG_DEF(occupant_pod/ejects, "You let the occupant out of %T%.", "%U% lets the occupant out of %T%.")
MSG_DEF(occupant_pod/gets_out, "You get out of %T%.", "%U% gets out of %T%.")
MSG_DEF(occupant_pod/release_begins, "You start the release sequence of %T%. It will take a while.", "%T% begins its release sequence.")
MSG_DEF_SELF(occupant_pod/empty, "Nobody is inside it.")
MSG_DEF_SELF(occupant_pod/occupied, "It is already occupied.")
MSG_DEF(occupant_pod/someone_inside, "Someone is inside %T%.", "")
MSG_DEF_SELF(occupant_pod/nobody, "There is nobody to put in.")
MSG_DEF_SELF(occupant_pod/wrong_kind, "It is not designed for that organism.")
MSG_DEF_SELF(occupant_pod/not_here, "They are not next to it.")
MSG_DEF_SELF(occupant_pod/anchored, "They are fixed in place.")
MSG_DEF_SELF(occupant_pod/buckled, "They are buckled to something.")
MSG_DEF_SELF(occupant_pod/carrying, "They have someone attached to them; remove them first.")
MSG_DEF_SELF(occupant_pod/abiotic, "The subject cannot have abiotic items on.")
MSG_DEF_SELF(occupant_pod/controls_outside, "You can't reach the controls from in here.")

/// The pod's occupant got in or out, by any path: published by the pod (never tried), for the machine's own on_notice() hooks.
ACTION(pod_enter, mob/living/occupant, FIXED, notice = /datum/notice/pod_entered)
ACTION(pod_leave, mob/living/occupant, FIXED, notice = /datum/notice/pod_left)

CAPABILITY_TYPE(occupant_pod, CAP_OCCUPANT_POD, /datum/capability/lib/occupant_pod, key = NONE, slot = null, accepts = /mob/living/carbon/human, enter_wait = 0, exit_to = null, controls_inside = TRUE, eject_wait_inside = 0, shown_y = null, bare = FALSE)
cap_keys(CAP_OCCUPANT_POD, OCCUPIED = MSG(occupant_pod/empty))

/// slot id -> TRUE for every slot an occupant_pod() declares: the ledger's slot hook asks this before it looks for a pod.
GLOBAL_LIST_EMPTY(occupant_pod_slots)

/datum/capability/lib/occupant_pod
	output_hooks = OUTPUT_HOOK_DRAW

/// A pod that shows its occupant (shown_y) draws them in its look; the look keeps vis_contents.
/datum/capability/lib/occupant_pod/on_draw(datum/act/eval/A, datum/look/look)
	if(isnull(shown_y))
		return
	look.show(occupant_of(A.holder))

/datum/capability/lib/occupant_pod/entries()
	GLOB.occupant_pod_slots[slot] = TRUE
	var/list/who = list(req(CAP_PROC(victim_fits)))
	var/list/entries = list(
		slot(slot, accepts = accepts, capacity = 1, exposure = SLOT_EXPOSURE_SEALED),
		op("put_in", item(/mob/living), gesture(GESTURE_DRAG), label("Put inside"), global.tag(TAG_POD_ENTER),
			needs(who), wait(enter_wait), begins(CAP_PROC(begins_message)), then(CAP_PROC(put_victim_in)), says(CAP_PROC(entered_message)), logs(LOG_GAME)),
		op("put_in_grabbed", item(/obj/item/grab), label("Put inside"), global.tag(TAG_POD_ENTER),
			needs(who), wait(enter_wait), begins(MSG(occupant_pod/begins_put_grabbed)), then(CAP_PROC(put_victim_in)), consumes(),
			says(MSG(occupant_pod/puts_grabbed_in)), logs(LOG_GAME)),
		op("climb_in", menu(), label("Move Inside"), global.tag(TAG_POD_ENTER),
			needs(req_conscious(), who), wait(enter_wait), begins(MSG(occupant_pod/begins_climb)), then(CAP_PROC(put_victim_in)),
			says(MSG(occupant_pod/climbs_in)), logs(LOG_GAME)),
		op("eject", menu(), label("Eject"), when(OCCUPANT_POD_OCCUPIED),
			needs(req_conscious()), wait(CAP_PROC(eject_wait), keeps = TARGET_PRESENT | ALIVE), begins(CAP_PROC(eject_begins_message)),
			then(CAP_PROC(eject_op)), says(CAP_PROC(eject_message)), logs(LOG_GAME)),
		op("busy_tools", any_of_tools(TOOL_SCREWDRIVER, TOOL_CROWBAR), label("Open"), when(OCCUPANT_POD_OCCUPIED), priority(OP_PRIORITY_TAKE_OUT), wait(0),
			says(MSG(occupant_pod/someone_inside))), // above the machine's legacy maintenance entries (tier attack): takes the tool's click and does nothing
		while_slotted(slot, extend(/datum/act/relay_movement, instead(then(GLOBAL_PROC_REF(occupant_pod_moved)))), on = ON_CONTENTS),
		look_layer(LOOK_OCCUPIED, when = OCCUPANT_POD_OCCUPIED))
	if(controls_inside != TRUE)
		entries += extend(TAG_UI, needs(req_pod_controls()))
	return entries

// ---- who goes in ----

/// The mob an op puts in: the dragged mob, the one a held grab holds, or the actor climbing in from the menu. Null when it is none of them.
/datum/capability/lib/occupant_pod/proc/victim_of(datum/act/op/A)
	var/atom/held = A.held
	if(isliving(held))
		return held
	var/obj/item/grab/G = held
	if(istype(G))
		return G.grab_target()
	return isnull(held) ? A.actor : null

/// Why `victim` can't be put into `holder` by `actor` now: the reason (a message type), or null when it can. Reads only.
/datum/capability/lib/occupant_pod/proc/refusal(atom/movable/holder, mob/living/victim, mob/actor)
	if(!istype(victim) || QDELETED(victim))
		return /datum/msg/occupant_pod/nobody
	if(!istype(victim, accepts))
		return /datum/msg/occupant_pod/wrong_kind
	if(occupant_pod_occupied(holder))
		return /datum/msg/occupant_pod/occupied
	if(victim.anchored)
		return /datum/msg/occupant_pod/anchored
	if(victim.buckled_to())
		return /datum/msg/occupant_pod/buckled
	if(victim.has_buckled_mobs())
		return /datum/msg/occupant_pod/carrying
	if(bare && victim.abiotic())
		return /datum/msg/occupant_pod/abiotic
	if(get_dist(victim, holder) > 1 || (actor && get_dist(victim, actor) > 1))
		return /datum/msg/occupant_pod/not_here
	return null

/datum/capability/lib/occupant_pod/proc/victim_fits(datum/act/op/A)
	var/why = refusal(A.holder, victim_of(A), A.actor)
	return isnull(why) ? null : (why || /datum/msg/op/not_available)

/datum/capability/lib/occupant_pod/proc/begins_message(datum/act/op/A)
	return A.held == A.actor ? /datum/msg/occupant_pod/begins_climb : /datum/msg/occupant_pod/begins_put

/datum/capability/lib/occupant_pod/proc/entered_message(datum/act/op/A)
	return A.held == A.actor ? /datum/msg/occupant_pod/climbs_in : /datum/msg/occupant_pod/puts_in

/// Puts the op's mob in. The requirements were asked again when the wait ended, so it goes in.
/datum/capability/lib/occupant_pod/proc/put_victim_in(datum/act/op/A)
	if(!enter(A.holder, victim_of(A), A.actor))
		return OP_FAILED
	return OP_OK

// ---- who comes out ----

/// The occupant's own eject waits eject_wait_inside; an outsider's is at once.
/datum/capability/lib/occupant_pod/proc/eject_wait(datum/act/op/A)
	return A.actor == occupant_of(A.holder) ? eject_wait_inside : 0

/datum/capability/lib/occupant_pod/proc/eject_begins_message(datum/act/op/A)
	return (eject_wait_inside && A.actor == occupant_of(A.holder)) ? /datum/msg/occupant_pod/release_begins : null

/datum/capability/lib/occupant_pod/proc/eject_message(datum/act/op/A)
	return A.actor == occupant_of(A.holder) ? /datum/msg/occupant_pod/gets_out : /datum/msg/occupant_pod/ejects

/datum/capability/lib/occupant_pod/proc/eject_op(datum/act/op/A)
	if(!length(eject(A.holder)))
		return OP_FAILED
	var/atom/holder = A.holder
	holder.add_fingerprint(A.actor)
	return OP_OK

/// The occupant works the window only when the pod has controls inside.
/datum/capability/lib/occupant_pod/proc/controls_reachable(atom/holder, mob/actor)
	if(actor != occupant_of(holder))
		return TRUE
	if(istext(controls_inside))
		return !!holder.vars[controls_inside]
	return !!controls_inside

/// req_pod_controls(): the actor is not the pod's occupant, or the pod has controls inside ("You can't reach the controls from in here."). A part of
/// its own: it extends the holder's window buttons, which belong to no capability, so it finds the pod from the holder.
/proc/req_pod_controls()
	return part_make(/datum/entry/part/req/pod_controls)

/datum/entry/part/req/pod_controls
	part_name = "req_pod_controls"
	default_reason = /datum/msg/occupant_pod/controls_outside

/datum/entry/part/req/pod_controls/holds(datum/act/op/A)
	var/datum/capability/lib/occupant_pod/pod = occupant_pod_of(A.holder)
	return !pod || pod.controls_reachable(A.holder, A.actor)

// ---- the slot, from code ----

/// Moves `victim` in, through the pod's own rules (not the machine's extends: an op asks those). TRUE when they are inside.
/datum/capability/lib/occupant_pod/proc/enter(atom/movable/holder, mob/living/victim, mob/actor)
	if(refusal(holder, victim, actor == victim ? null : actor))
		return FALSE
	victim.stop_pulling()
	if(!move_into(holder, slot, victim, actor))
		return FALSE
	if(actor)
		holder.add_fingerprint(actor)
	return victim.loc == holder

/// Where an occupant leaving `holder` stands: the tile toward exit_to when nothing blocks it, else the pod's own tile.
/datum/capability/lib/occupant_pod/proc/exit_turf(atom/movable/holder)
	var/turf/here = get_turf(holder)
	if(isnull(exit_to) || !here)
		return here
	var/turf/out = get_step(here, exit_to)
	return (out && !is_blocked_turf(out)) ? out : here

/// Lets everyone in the pod out. The occupants that left (never null).
/datum/capability/lib/occupant_pod/proc/eject(atom/movable/holder)
	. = list()
	var/turf/out = exit_turf(holder)
	if(!out)
		return
	for(var/mob/living/inside in holder.slot_contents(slot))
		if(holder.slot_remove(inside, out))
			. += inside

/// The ledger moved `thing` in or out of the pod's slot (by any path): the state follows, the occupant is shown or not, the machine hears it.
/datum/capability/lib/occupant_pod/proc/slot_changed(atom/movable/holder, atom/movable/thing, inserted)
	cap_key_set(holder, OCCUPANT_POD_OCCUPIED, length(holder.slot_contents(slot)) > 0)
	PUBLISH_CHANGE(holder, OCCUPANT_KEY)
	var/mob/living/M = thing
	if(!istype(M))
		return
	if(!isnull(shown_y)) // the pod's look shows them (on_draw()); they sit raised in it, facing out
		if(inserted)
			M.pixel_y += shown_y
			M.set_dir(SOUTH)
		else
			M.pixel_x = M.default_pixel_x
			M.pixel_y = M.default_pixel_y
	if(inserted)
		PUBLISH(holder, pod_enter, M)
	else
		PUBLISH(holder, pod_leave, M)

// ---- reads and code entry points ----

/// The occupant pod capability of `holder`, or null.
/proc/occupant_pod_of(atom/holder)
	RETURN_TYPE(/datum/capability/lib/occupant_pod)
	READS_FROM() // the type's compiled table, not an entity's state
	return cap_of(holder, CAP_OCCUPANT_POD)

/// Who is inside `holder`'s pod, or null. The one accessor of a pod's occupant: conditions that read it follow OCCUPANT_KEY.
/proc/occupant_of(atom/holder)
	RETURN_TYPE(/mob/living)
	READS_FROM() // the ledger slot it reads is published as OCCUPANT_KEY (READS_AS below)
	var/datum/capability/lib/occupant_pod/pod = occupant_pod_of(holder)
	if(!pod)
		return null
	var/datum/ledger/L = holder.containment_ledger()
	var/list/inside = L?.slots[pod.slot]
	return length(inside) ? inside[1] : null

READS_AS(/proc/occupant_of, OCCUPANT_KEY)

/// Puts `M` into `holder`'s pod from code (a spawn, a bump, a test): the pod's own rules, no wait. TRUE when they are inside.
/proc/occupant_enter(atom/movable/holder, mob/living/M, mob/actor = null)
	var/datum/capability/lib/occupant_pod/pod = occupant_pod_of(holder)
	return pod ? pod.enter(holder, M, actor) : FALSE

/// Lets the occupant of `holder`'s pod out from code. The mobs that left (never null).
/proc/occupant_eject(atom/movable/holder)
	var/datum/capability/lib/occupant_pod/pod = occupant_pod_of(holder)
	return pod ? pod.eject(holder) : list()

/// From the ledger (/atom/on_slot_changed()): something moved in or out of `slot_id` of `holder`; a pod's slot tells its pod.
/proc/occupant_pod_slot_changed(atom/movable/holder, slot_id, atom/movable/thing, inserted)
	if(!GLOB.occupant_pod_slots[slot_id] || !istype(holder))
		return
	var/datum/capability/lib/occupant_pod/pod = occupant_pod_of(holder)
	if(pod?.slot == slot_id)
		pod.slot_changed(holder, thing, inserted)

/// The occupant pressed a direction (their relay_movement action, hooked while they are in a pod): one who can act gets out.
/proc/occupant_pod_moved(datum/act/relay_movement/A)
	var/mob/living/M = A.holder
	var/atom/movable/pod_holder = M?.loc
	if(!istype(pod_holder) || !istype(M) || M.incapacitated())
		return null
	if(length(occupant_eject(pod_holder)))
		act_message(M, pod_holder, MSG_SELF("You get out of %T%."), MSG_OTHERS("%U% gets out of %T%."))
	return null
