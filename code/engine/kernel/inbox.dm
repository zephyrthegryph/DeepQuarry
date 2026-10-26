// The input inbox (doc/rewrite/final_api.html, section 2 "The input inbox"; section 19 "E6, kernel completion").
//
// One inbox replaces SSinput, SSverb_manager, the speech lane and the click holdback. Every client entry point (Click,
// client/Topic, say, point, a tgui action, a driver-built input) builds one typed /datum/input_event and hands it to
// input_submit(). There are no opt-in macros and no callbacks:
//
//   - Order and budget. An event resolves on the spot when its client has nothing waiting and the tick has room
//     (TICK_USAGE under the event's threshold); otherwise it queues. Phase K drains the queues round-robin across clients,
//     each in arrival order, under the input budget (KERNEL_INPUT_CAP percent of a tick, one event at least), so one
//     flooding client cannot starve the rest.
//   - Bounded queues. A client's inbox holds INPUT_CLIENT_MAX events. A coalescible input (a held key, a repeated click on one
//     target, a repeated point) keeps only the latest queued copy; past the cap the oldest coalescible input is dropped and
//     counted. An input that cannot coalesce (say, a Topic, a tgui action) is never dropped, so an inbox of such inputs
//     can pass the cap.
//   - Resolution at drain time. Each event is checked by its gate when it is resolved, not when it arrived: a target or an
//     actor that has gone by then ends the event with the gate's reason and nothing runs.
//   - Never shed. The inbox is latency class L0: phase K runs it first, every tick, whatever the load.
//
// What resolves an event is the event's own resolve(), and it is one step whether the event ran on arrival or waited in the inbox: the target type's
// declared entry for the input (click_on(), double_click_on(), drag_onto(), drag_over(), hover(), tooltip(), looked up in the type tables by
// input_dispatch(), code/engine/lifeforms/input.dm) runs first, and an input no entry takes goes on to its default handling: the click router for a
// click, the target's ops and MouseDrop_T for a drop, the Topic dispatch for a Topic, the mob's hover tracking for a hover. No type overrides a native
// mouse proc: BYOND's callbacks are overridden only in code/engine/kernel/entry.dm. E2's resolver takes the click, menu and window-action events over
// through the seams at the bottom (input_resolve_click(), input_resolve_menu(), input_resolve_ui()); a driver-built event reports a missing
// resolver to the test driver (ENGINE_STUB).

MSG_DEF_SELF(input/stale_actor, "You can't do that any more.")
MSG_DEF_SELF(input/stale_target, "That is no longer there.")
MSG_DEF_SELF(input/client_gone, "Your connection is gone.")
MSG_DEF_SELF(input/too_late, "That input waited too long for the server and was ignored.")
MSG_DEF_SELF(input/flood, "You are sending input faster than the server can take it: that one was refused.")

// ---------------------------------------------------------------- events

/// One input a client sent, recorded when it arrived and resolved when the inbox gets to it.
/datum/input_event
	/// The mob the input acts as. A plain reference, held for the few ticks the event lives (a deleted mob is
	/// QDELETED, and the gate drops the event).
	var/mob/actor
	/// ORIGIN_*: which binding the input came through (section 8).
	var/origin = ORIGIN_CLICK
	/// world.time and TICK_USAGE when the event arrived: the wait metrics read them when it resolves.
	var/arrived_time = 0
	var/arrived_usage = 0
	/// The client that sent it. A /client is not a datum, so this is a plain reference: a client that has gone reads null.
	var/client/sender
	/// TRUE when the input was built by the test driver, so the resolver behind it is E2's and not the legacy path.
	var/driven = FALSE
	/// What the resolver reported (the op's /datum/op_result), or null when nothing resolved.
	var/datum/op_result/result
	/// TICK_USAGE under which this kind resolves on the spot.
	var/resolve_threshold = INPUT_VERB_THRESHOLD
	/// TRUE when a click-cost measurement (the tick meter's click stamps) should wrap the resolution.
	var/metered_as_click = FALSE
	/// The kernel clock (op_now(): the injected one under a test driver) when the event arrived: its age at resolve time is read from it.
	var/arrived_clock = 0
	/// How long the event may wait in the inbox before it is too late, in deciseconds (INPUT_MAX_WAIT_*), or null for never: a Topic, a tgui action, say, point
	/// and a menu pick are what the player asked for, whenever they are served. The gate checks it when the event resolves.
	var/max_wait = null
	/// TRUE when an expired event is dropped without telling the player (feedback such as a hover).
	var/silent_expiry = FALSE
	/// FALSE for inputs the rate limit does not apply to (the server's own: a reboot, the synthetic load).
	var/rate_limited = TRUE

/datum/input_event/New(mob/user)
	..()
	if(user)
		actor = user // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input
		sender = user.client

/// What the inbox files this event's queue under: the client, or the actor for an input with no client (a driver-built event).
/datum/input_event/proc/lane_key()
	return sender || actor

/// Events with the same non-null key replace one another in a queue: only the latest is kept. Null: it never coalesces.
/datum/input_event/proc/coalesce_key()
	return null

/// The thing whose deletion makes the event stale, or null.
/datum/input_event/proc/subject()
	return null

/// The op key chain the event reports under (the recorder's rows and the logs).
/datum/input_event/proc/event_key()
	return "input.[type]"

/// Null while the event is still good to resolve, else the /datum/msg type that says why not.
/datum/input_event/proc/gate()
	if(!driven && !actor)
		return /datum/msg/input/stale_actor
	var/datum/thing = subject()
	if(thing && QDELETED(thing))
		return /datum/msg/input/stale_target
	if(!driven && sender && !actor.client)
		return /datum/msg/input/client_gone
	if(expired())
		return /datum/msg/input/too_late
	return null

/// Has the event waited longer than its max_wait?
/datum/input_event/proc/expired()
	return !isnull(max_wait) && (op_now() - arrived_clock) > max_wait

/// Does the work, as `actor`. Returns the op's /datum/op_result or null.
/datum/input_event/proc/resolve()
	return null

/// A click on the map or a screen object.
/datum/input_event/click
	resolve_threshold = INPUT_CLICK_THRESHOLD
	metered_as_click = TRUE
	max_wait = INPUT_MAX_WAIT_CLICK
	var/atom/target
	var/location
	var/control
	var/params
	/// Driver-built clicks: the held item and the gesture the click stands for.
	var/atom/movable/held
	var/gesture = GESTURE_CLICK

/datum/input_event/click/New(mob/user, atom/clicked, location, control, params)
	..(user)
	if(clicked)
		target = clicked // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input
	src.location = location
	src.control = control
	src.params = params

/// Repeated clicks on one target keep only the latest.
/datum/input_event/click/coalesce_key()
	return target ? "click:[REF(target)]" : null

/datum/input_event/click/subject()
	return target

/datum/input_event/click/event_key()
	return "input.click"

/// The native hook's arguments by name, as a declared handler's A.native reads them.
/datum/input_event/click/proc/native_args()
	return list("location" = location, "control" = control, "params" = params)

/// The type's click_on() entry first (a driver-built click is the ops' own and runs no declared entry), then the click router.
/datum/input_event/click/resolve()
	if(!driven && input_dispatch(target, actor, INPUT_CLICK_ON, params, null, FALSE, native_args()))
		return null
	return input_resolve_click(src)

/// An atom (an item, or a mob dragging itself) dragged onto another: the Drag action. The ops of the target see the dragged atom as A.held (gesture GESTURE_DRAG);
/// what no op answers goes on to the legacy MouseDrop_T chain, as it did before the target declared one.
/datum/input_event/drag
	resolve_threshold = INPUT_CLICK_THRESHOLD
	metered_as_click = TRUE
	max_wait = INPUT_MAX_WAIT_DRAG
	var/atom/dragged
	var/atom/over
	/// What the legacy chain takes on (the locations, the controls and the params of the drag).
	var/list/legacy_args
	/// TRUE for a drop BYOND handed over (atom/MouseDrop, code/engine/kernel/entry.dm): the drop must be within reach of the actor when it resolves,
	/// which a drop an adapter already checked (adapter.drag()) is not asked twice.
	var/native = FALSE

/datum/input_event/drag/New(mob/user, atom/dragged_atom, atom/dropped_on, list/legacy, native_drop = FALSE)
	..(user)
	native = native_drop
	if(dragged_atom)
		dragged = dragged_atom // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input
	if(dropped_on)
		over = dropped_on // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input
	legacy_args = legacy

/datum/input_event/drag/subject()
	return over

/datum/input_event/drag/gate()
	if(dragged && QDELETED(dragged))
		return /datum/msg/input/stale_target
	return ..()

/datum/input_event/drag/event_key()
	return "input.drag"

/// What the legacy chain takes on, as a declared handler's A.native reads it.
/datum/input_event/drag/proc/native_args()
	return list("over_object" = over, "src_location" = legacy_args?[1], "over_location" = legacy_args?[2], "src_control" = legacy_args?[3], "over_control" = legacy_args?[4], "params" = legacy_args?[5])

/// The dragged type's drag_onto() entry first (no reach is asked of it: the entry says what it takes), then the target's ops and MouseDrop_T.
/datum/input_event/drag/resolve()
	if(!driven && dragged && input_dispatch(dragged, actor, INPUT_DRAG_ONTO, legacy_args?[5], over, FALSE, native_args()))
		return null
	return input_resolve_drag(src)

/// A double click on a target. Repeated ones on one target keep only the latest.
/datum/input_event/click/double
	metered_as_click = FALSE

/datum/input_event/click/double/coalesce_key()
	return target ? "double:[REF(target)]" : null

/datum/input_event/click/double/event_key()
	return "input.double_click"

/datum/input_event/click/double/resolve()
	if(!driven && input_dispatch(target, actor, INPUT_DOUBLE_CLICK, params, null, FALSE, native_args()))
		return null
	actor.input_double_click(target, params)
	return null

/// The mouse wheel over a target. Every notch counts: it never coalesces.
/datum/input_event/click/wheel
	metered_as_click = FALSE
	max_wait = INPUT_MAX_WAIT_WHEEL
	var/delta_x = 0
	var/delta_y = 0

/datum/input_event/click/wheel/New(mob/user, atom/over, location, control, params, delta_x, delta_y)
	..(user, over, location, control, params)
	src.delta_x = delta_x
	src.delta_y = delta_y

/datum/input_event/click/wheel/coalesce_key()
	return null

/datum/input_event/click/wheel/event_key()
	return "input.wheel"

/datum/input_event/click/wheel/resolve()
	actor.input_wheel(target, delta_x, delta_y, params)
	return null

/// The mouse entering a target, or leaving it (`entered` FALSE). Only the latest hover of a target is worth keeping: an exit that finds its enter still waiting
/// replaces it, so the pair does nothing.
/datum/input_event/click/hover
	metered_as_click = FALSE
	max_wait = INPUT_MAX_WAIT_FEEDBACK
	silent_expiry = TRUE
	/// TRUE on enter, FALSE on exit.
	var/entered = TRUE

/datum/input_event/click/hover/New(mob/user, atom/over, location, control, params, entering = TRUE)
	..(user, over, location, control, params)
	entered = entering

/datum/input_event/click/hover/coalesce_key()
	return target ? "hover:[REF(target)]" : "hover"

/datum/input_event/click/hover/event_key()
	return "input.hover"

/// The tooltip the type declares opens or closes, its hover() entry runs, and an enter goes on to the mob's hover tracking whatever the entry said.
/datum/input_event/click/hover/resolve()
	input_tooltip(target, actor, entered, params)
	if(!driven)
		input_dispatch(target, actor, INPUT_HOVER, params, null, entered, native_args())
	if(entered)
		actor.input_hover(target, params)
	return null

/// A mouse button pressed on a target (atom/MouseDown). A press and its release are a pair: it never coalesces.
/datum/input_event/click/pressed
	metered_as_click = FALSE
	max_wait = INPUT_MAX_WAIT_FEEDBACK
	silent_expiry = TRUE

/datum/input_event/click/pressed/event_key()
	return "input.pressed"

/datum/input_event/click/pressed/coalesce_key()
	return null

/datum/input_event/click/pressed/resolve()
	actor.input_pressed(target, params)
	return null

/// The client's own mouse procs (client/MouseDown, MouseUp, MouseDrag): INPUT_MOUSE_*, what the pointer is on, and for a drag what it is over.
/datum/input_event/click/client_mouse
	metered_as_click = FALSE
	/// A press or a release is a click's own wait; a drag is feedback (silent when late).
	max_wait = INPUT_MAX_WAIT_CLICK
	var/kind = INPUT_MOUSE_DOWN
	var/atom/over

/datum/input_event/click/client_mouse/New(mob/user, mouse_kind, atom/pointed, atom/dragged_over, location, control, params)
	..(user, pointed, location, control, params)
	kind = mouse_kind
	if(kind == INPUT_MOUSE_DRAG)
		max_wait = INPUT_MAX_WAIT_FEEDBACK
		silent_expiry = TRUE
	if(dragged_over)
		over = dragged_over // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input

/// A drag keeps only its latest position; a press and a release never coalesce.
/datum/input_event/click/client_mouse/coalesce_key()
	return kind == INPUT_MOUSE_DRAG ? "mouse_drag" : null

/datum/input_event/click/client_mouse/event_key()
	return "input.[kind]"

/// A press and its release are a pair: a release whose press ran is never too late (the press is held until it arrives), whatever it waited. A release
/// whose press never ran (it was late, refused or dropped) expires like any other input.
/datum/input_event/click/client_mouse/expired()
	if(kind == INPUT_MOUSE_UP && SSinput.press_ran(lane_key()))
		return FALSE
	return ..()

/// A drag first runs the dragged type's drag_over() entry (it only watches: the drag goes on to the mob's hook either way).
/datum/input_event/click/client_mouse/resolve()
	if(kind == INPUT_MOUSE_DOWN)
		SSinput.note_press(lane_key(), TRUE)
	else if(kind == INPUT_MOUSE_UP)
		SSinput.note_press(lane_key(), FALSE)
	if(kind == INPUT_MOUSE_DRAG && target && over)
		input_dispatch(target, actor, INPUT_DRAG_OVER, params, over, FALSE, list("over_object" = over, "over_location" = location, "over_control" = control, "params" = params))
	actor.input_client_mouse(kind, target, over, params)
	return null

/// A pick from a target's context menu (origin ORIGIN_MENU).
/datum/input_event/menu
	origin = ORIGIN_MENU
	resolve_threshold = INPUT_CLICK_THRESHOLD
	var/atom/target
	var/op_key
	var/atom/movable/held

/datum/input_event/menu/New(mob/user, atom/picked, key, atom/movable/in_hand)
	..(user)
	if(picked)
		target = picked // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input
	op_key = key
	if(in_hand)
		held = in_hand // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input

/datum/input_event/menu/subject()
	return target

/datum/input_event/menu/event_key()
	return "input.menu"

/datum/input_event/menu/resolve()
	return input_resolve_menu(src)

/// A tgui window action (origin ORIGIN_UI): a player's, through a /datum/tgui, or a driver-built one naming the window's host.
/datum/input_event/ui_act
	origin = ORIGIN_UI
	var/action
	var/list/payload
	/// A player's: the window and the state it ran under. Null for a driver-built one.
	var/datum/ui
	var/datum/state
	/// A driver-built one: the entity hosting the window.
	var/datum/window

CAPABILITIES(/datum/input_event/ui_act)
	ref_one(nameof(state))

/datum/input_event/ui_act/New(mob/user, datum/window_ui, act_type, list/act_payload, datum/act_state)
	..(user)
	if(window_ui)
		ui = window_ui // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input
	action = act_type
	payload = act_payload
	rel_set(src, nameof(state), act_state)

/datum/input_event/ui_act/subject()
	return ui || window

/datum/input_event/ui_act/event_key()
	return "input.ui.[action]"

/datum/input_event/ui_act/resolve()
	if(driven)
		return input_resolve_ui(src)
	ui.input_window_action(action, payload, state)
	return null

/// The presentation adapter supplies a window's concrete dispatch protocol.
/datum/proc/input_window_action(action, list/payload, datum/state)
	return null

/// A Topic href: the dispatch the client's own hrefs and every datum's Topic() take. Never dropped.
/datum/input_event/topic
	var/datum/hsrc
	var/href
	var/list/href_list
	/// TRUE for a link BYOND already carried to the datum's own Topic() (/datum/Topic, code/engine/kernel/entry.dm): the dispatch answers it, and the
	/// client's chain is not walked again.
	var/at_datum = FALSE
	/// What the datum dispatch answered (TRUE when an op took the link), for the Topic() that submitted it.
	var/answered

/datum/input_event/topic/New(mob/user, datum/source, link, list/link_list, reached_datum = FALSE)
	..(user)
	at_datum = reached_datum
	if(source)
		hsrc = source // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input
	href = link
	href_list = link_list

/datum/input_event/topic/subject()
	return hsrc

/datum/input_event/topic/event_key()
	return "input.topic"

/datum/input_event/topic/resolve()
	if(at_datum)
		answered = hsrc.input_topic_dispatch(actor, href_list)
		return null
	// The op that names the href answers it, through the same Match, Require and Do as a click; what no op names is the legacy Topic() chain's.
	var/datum/op_result/answered = op_topic_href(actor, hsrc, href_list)
	if(answered)
		return answered
	if(driven)
		input_compatibility().compatibility_topic(hsrc, actor, href_list) // a driver-built link: the table's row, as the actor (a player's reaches it through Topic())
		return null
	sender?.input_topic(hsrc, href, href_list)
	return null

/// say: the message is processed by the mob's say(). Never dropped.
/datum/input_event/say
	var/message

/datum/input_event/say/New(mob/user, text)
	..(user)
	message = text

/datum/input_event/say/event_key()
	return "input.say"

/datum/input_event/say/resolve()
	actor.input_say(message)
	return null

/// Point To: a repeated point keeps only the latest.
/datum/input_event/point
	var/atom/pointing_at

/datum/input_event/point/New(mob/user, atom/target)
	..(user)
	if(target)
		pointing_at = target // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input

/datum/input_event/point/coalesce_key()
	return "point"

/datum/input_event/point/subject()
	return pointing_at

/datum/input_event/point/event_key()
	return "input.point"

/datum/input_event/point/resolve()
	actor.input_point(pointing_at)
	return null

/// world.Reboot(): who asked, and whether the world goes on to reboot (the hook, input_reboot()). It resolves on arrival whatever the tick says:
/// a reboot waits for no drain, and a server-side one has no actor.
/datum/input_event/reboot
	resolve_threshold = 1000
	rate_limited = FALSE
	var/reason = 0
	var/fast_track = FALSE
	/// What the hook answered: TRUE when the native reboot goes on.
	var/proceed = FALSE
	/// TRUE once the hook returned (an input that sleeps detaches in input_run(), so a hook that slept has not).
	var/finished = FALSE

/datum/input_event/reboot/New(mob/user, reboot_reason, reboot_fast_track)
	..(user)
	reason = reboot_reason
	fast_track = reboot_fast_track

/datum/input_event/reboot/lane_key()
	return "reboot"

/datum/input_event/reboot/gate()
	return null

/datum/input_event/reboot/event_key()
	return "input.reboot"

/datum/input_event/reboot/resolve()
	proceed = world.input_reboot(actor, reason, fast_track)
	finished = TRUE
	return null

// ---------------------------------------------------------------- the system

// What the inbox remembers about one client between its inputs, a list by these indexes (kept under the lane's REF text, so a client that leaves is not held, and
// forgotten after a minute of nothing): the rate window, the refusal bursts, the time near the cap, an unreleased press.
#define INPUT_LANE_RATE_START 1
#define INPUT_LANE_RATE_COUNT 2
/// When the last input of the lane was refused, and when the player was last told (null: never).
#define INPUT_LANE_LAST_REFUSAL 3
#define INPUT_LANE_LAST_NOTICE 4
/// When the inbox first reached INPUT_CLIENT_NEAR_CAP in this run of it, and when the server last warned.
#define INPUT_LANE_NEAR_SINCE 5
#define INPUT_LANE_LAST_NEAR_WARNING 6
/// TRUE from a press that ran until its release runs.
#define INPUT_LANE_PRESSED 7
#define INPUT_LANE_TOUCHED 8

SYSTEM_DEF(input)
	name = "Input"
	phase = KERNEL_PHASE_K
	latency_class = LATENCY_L0
	init_stage = INITSTAGE_EARLY
	/// lane key (a client, or a mob with none) -> its queue: /datum/input_event, oldest first.
	var/list/inboxes = list()
	/// The lane keys that have a queue, in the order the drain serves them (round-robin).
	var/list/ready = list()
	/// The lane key the next drain starts with (set when a drain ran out of budget in the middle of a round).
	var/next_source
	/// TRUE/FALSE forces the "does the tick have room" answer (test builds); null asks the tick.
	var/room_override
	/// Counters since boot.
	var/resolved_in_place = 0
	var/resolved_queued = 0
	var/queued = 0
	var/coalesced = 0
	var/dropped_cap = 0
	var/dropped_stale = 0
	var/faults = 0
	/// The deepest any inbox got.
	var/queue_high_water = 0
	var/last_drop_log = 0
	/// Inputs refused over a client's hard cap or rate limit, and inputs that waited past their max_wait, since boot.
	var/hard_refused = 0
	var/rate_refused = 0
	var/expired = 0
	var/near_cap_warnings = 0
	/// lane key REF text -> that lane's state (INPUT_LANE_*).
	var/list/lanes = list()
	var/next_lane_prune = 0
	/// TRUE while the drain item is parked (the drain found nothing queued): the enqueue that ends the idle wakes it, and every other
	/// enqueue reads this flag instead of looking the item up.
	var/drain_parked = FALSE

/datum/system/input/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(drain_step), phase = KERNEL_PHASE_K, lane = LANE_URGENT)
	. += every(WORK_EVERY_TICK, PROC_REF(key_step), phase = KERNEL_PHASE_K, lane = LANE_URGENT, after = list("[/datum/system/input]:drain_step"))

/// Forces the "does the tick have room" answer (TRUE: inputs resolve on the spot, FALSE: they queue), or null to ask the tick again.
/// For tests and the benchmarks' synthetic input.
/proc/input_force_room(room)
	SSinput.room_override = room

/// Hands an event to the inbox. Returns TRUE when it resolved on the spot (E.result holds what it reported), FALSE when it
/// was queued or dropped.
/proc/input_submit(datum/input_event/E)
	return SSinput.submit(E)

/datum/system/input/proc/submit(datum/input_event/E)
	E.arrived_time = world.time // ALLOW(sys_world_time_write): the inbox's own arrival stamp, read for the wait metrics, not an entity expiry
	E.arrived_usage = TICK_USAGE
	E.arrived_clock = op_now()
	var/source = E.lane_key()
	if(E.rate_limited && source && !E.coalesce_key() && rate_exceeded(source))
		// An input that cannot coalesce is not bounded by the soft cap, so its rate is: the newest is refused, never one already waiting.
		rate_refused++
		refuse(E, source, "more than [INPUT_CLIENT_RATE_MAX] such inputs in [INPUT_RATE_WINDOW / (1 SECONDS)] second")
		return FALSE
	var/list/queue = inboxes[source]
	// has_room() inlined: this is the stretch between an input's arrival stamp and its dispatch stamp, which the wait metrics count.
#ifdef UNIT_TESTS
	if(!length(queue) && (isnull(room_override) ? TRUE : room_override)) // a test world boots through ticks past 100%: only room_override decides
#else
	if(!length(queue) && (isnull(room_override) ? (TICK_USAGE < E.resolve_threshold) : room_override))
#endif
		resolved_in_place++
		var/datum/kernel_latency/latency = Kernel.latency_state || kernel_latency()
		latency.input_immediate++
		latency.input_bins[1]++ // record_input(0): an input that ran on arrival waited no ticks
		run_event(E, FALSE, latency, TRUE)
		return TRUE
	enqueue(E, source, queue)
	return FALSE

/// Does the tick have room for `E` now: the test override, else TICK_USAGE under the event kind's threshold.
/datum/system/input/proc/has_room(datum/input_event/E)
	if(!isnull(room_override))
		return room_override
	return input_room(E)

/// The tick's own answer (no override).
/datum/system/input/proc/input_room(datum/input_event/E)
#ifdef UNIT_TESTS
	// A test world boots through ticks that run far past 100%: only room_override decides there (as shedding is off in tests).
	return TRUE
#else
	return TICK_USAGE < E.resolve_threshold
#endif

/// Files `E` in `source`'s queue: a coalescible event replaces the queued one with its key, and a full inbox sheds its oldest
/// coalescible input (an event that cannot coalesce is kept, past the cap if it must).
/datum/system/input/proc/enqueue(datum/input_event/E, source, list/queue)
	if(!queue)
		queue = list()
		inboxes[source] = queue
		ready += source
		wake_work_item(PROC_REF(drain_step))
	var/key = E.coalesce_key()
	if(key)
		for(var/i in length(queue) to 1 step -1)
			var/datum/input_event/older = queue[i]
			if(older.coalesce_key() == key)
				queue.Cut(i, i + 1)
				coalesced++
				break
	if(length(queue) >= INPUT_CLIENT_MAX)
		var/dropped = FALSE
		for(var/i in 1 to length(queue))
			var/datum/input_event/older = queue[i]
			if(older.coalesce_key())
				queue.Cut(i, i + 1)
				note_drop(older, "the inbox is full")
				dropped = TRUE
				break
		if(!dropped && key)
			// Nothing in the inbox can be shed and this one could be: it goes.
			note_drop(E, "the inbox is full of inputs that cannot be dropped")
			return
	if(length(queue) >= INPUT_CLIENT_HARD_MAX)
		// Nothing left to shed and the inbox is full of inputs that cannot be dropped: the newest is refused, and said so.
		hard_refused++
		refuse(E, source, "the inbox holds [INPUT_CLIENT_HARD_MAX] waiting inputs")
		return
	queue += E
	queued++
	kernel_latency().input_queued++
	if(length(queue) > queue_high_water)
		queue_high_water = length(queue)
	watch_near_cap(source, length(queue))
	km_meter().verb_queued(length(queue))

/// A coalescible input was dropped over the cap: counted, and logged at most once a second.
/datum/system/input/proc/note_drop(datum/input_event/E, why)
	dropped_cap++
	kernel_latency().input_dropped++
	if(world.time - last_drop_log >= 1 SECONDS) // ALLOW(sys_world_time_expiry): the inbox's own log throttle, not an entity expiry
		last_drop_log = world.time // ALLOW(sys_world_time_write): the inbox's own log throttle, not an entity expiry
		log_world("Input: dropped a [E.type] from [E.actor ? key_name(E.actor) : "nobody"]: [why] (inbox cap [INPUT_CLIENT_MAX], [dropped_cap] dropped so far).")

/// Resolves one event now (from its arrival, or from the drain). `waited` events were queued: their wait is recorded.
/// `on_arrival`: it is resolving in the call that received it, so a player's own input (not a driver-built one) cannot have gone
/// stale since BYOND handed it over, and its gate is not asked.
/datum/system/input/proc/run_event(datum/input_event/E, waited = TRUE, datum/kernel_latency/latency = null, on_arrival = FALSE)
	latency ||= Kernel.latency_state || kernel_latency()
	if(waited)
		latency.record_input((world.time - E.arrived_time) / world.tick_lag)
		km_meter().verb_run(E.arrived_time, E.arrived_usage)
		resolved_queued++
	var/reason = (on_arrival && !E.driven) ? null : E.gate()
	if(reason)
		if(reason == /datum/msg/input/too_late)
			expired++
			if(!E.silent_expiry)
				op_tell(E.actor, reason)
		else
			dropped_stale++
		TEST_REC_OUTCOME(E.event_key(), ACT_REFUSED, reason, E.actor)
		TEST_REC_LOG(E.event_key(), ACT_REFUSED, E.origin, E.actor, E.subject(), "[reason]")
		return
	var/datum/tick_meter/meter = km_holder().meter || km_meter()
	var/entry_time = world.time
	var/dispatch_usage = E.metered_as_click ? meter.click_dispatched(E.arrived_time, E.arrived_usage) : 0
	try
		E.result = world.input_run(E.actor, E) // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input
	catch(var/exception/fault) // ALLOW(silent_catch): the inbox is the kernel's own isolation point: one input's runtime must not stop the drain
		faults++
		kernel().report_fault(fault, "input event [E.type] runtime: [fault] ([fault.file]:[fault.line])")
	if(E.metered_as_click)
		meter.click_done(entry_time, dispatch_usage)

/// Runs `E.resolve()` as `user_mob` (usr), and puts usr back.
/// Deliberate native-input shim: unconverted callbacks still receive BYOND's acting mob through usr; engine event records carry actor explicitly.
/world/proc/input_run(mob/user_mob, datum/input_event/E)
	set waitfor = FALSE // ALLOW(scheduler): kernel code: an input that sleeps (a legacy Topic) detaches here instead of holding phase K
	var/temp = usr // the inbox runs an input as its actor: the engine sets usr for a resolved input
	usr = user_mob
	. = E.resolve()
	usr = temp

/// Phase K: serves the queues round-robin, each client's oldest first, under the input budget (one event at least).
/datum/system/input/proc/drain_step(dt, unlimited = FALSE)
	if(op_now() >= next_lane_prune)
		next_lane_prune = op_now() + 1 MINUTES
		prune_lanes()
	if(!length(ready))
		// Nothing queued: the item parks and the next enqueue() wakes it (no per-tick poll of an empty inbox).
		drain_parked = TRUE
		return STEP_PARK
	var/started = TICK_USAGE
	// `unlimited`, or a test owning the kernel clock: no budget, so a loaded test machine cannot change how many events a drain serves.
	var/limit = (unlimited || !isnull(kernel().test_now)) ? WORK_TEST_LIMIT : min(Kernel.current_ticklimit, started + KERNEL_INPUT_CAP)
	var/served = 0
	// Start with the client after the last one the previous drain reached, so a budget that runs out in the middle of a round
	// does not always shed the same clients.
	var/list/serving = ready.Copy()
	var/start = next_source ? serving.Find(next_source) : 1
	if(start > 1)
		serving = serving.Copy(start) + serving.Copy(1, start)
	next_source = null
	while(length(serving))
		var/list/still = list()
		for(var/source in serving)
			if(served && TICK_USAGE >= limit)
				next_source = source
				kernel_latency().input_over_cap++
				charge_drain(started)
				return STEP_DONE
			var/list/queue = inboxes[source]
			if(!length(queue))
				inbox_done(source)
				continue
			var/datum/input_event/E = queue[1]
			queue.Cut(1, 2)
			if(length(queue))
				still += source
			else
				inbox_done(source)
			served++
			run_event(E)
		serving = still
	charge_drain(started)
	return STEP_DONE

/// The drain's cost is the input system's, and input cost in the tick record.
/datum/system/input/proc/charge_drain(started)
	var/ms = TICK_USAGE_TO_MS(started)
	if(ms <= 0)
		return
	var/datum/tick_meter/meter = km_meter()
	meter.charge(KM_SYS_INPUT, ms)
	meter.input_ms += ms

/// `source`'s queue is empty: it leaves the round.
/datum/system/input/proc/inbox_done(source)
	inboxes -= source
	ready -= source
	var/list/L = lanes["[REF(source)]"]
	if(L)
		L[INPUT_LANE_NEAR_SINCE] = null

/// Phase K, after the drain: every client's held keys (the movement loop SSinput ran).
/datum/system/input/proc/key_step(dt)
	SHOULD_NOT_SLEEP(TRUE)
	var/list/clients = GLOB.clients
	if(!length(clients))
		// No one is connected: parked until a client joins (client/New wakes it).
		return STEP_PARK
	for(var/i in 1 to length(clients))
		var/client/C = clients[i]
		C?.input_key_loop()
	return STEP_DONE

/// The events waiting for `source` (a client, or a mob with none), oldest first. The store's own list: read it only.
/datum/system/input/proc/waiting(source)
	return inboxes[source] || list()

/// Total events queued across every inbox.
/datum/system/input/proc/queued_total()
	. = 0
	for(var/source in inboxes)
		. += length(inboxes[source])

/// Test builds: forgets every queued event and the room override, so one test's inputs never reach the next.
/datum/system/input/proc/reset_for_test()
	inboxes = list()
	ready = list()
	next_source = null
	room_override = null
	lanes = list()

/datum/system/input/stat_entry(msg)
	return "[msg] I:[resolved_in_place + resolved_queued] Q:[queued_total()]"

/datum/system/input/metrics()
	. = ..()
	.["resolved_in_place"] = resolved_in_place
	.["resolved_queued"] = resolved_queued
	.["queued"] = queued
	.["coalesced"] = coalesced
	.["dropped_cap"] = dropped_cap
	.["dropped_stale"] = dropped_stale
	.["faults"] = faults
	.["queue_high_water"] = queue_high_water
	.["hard_refused"] = hard_refused
	.["rate_refused"] = rate_refused
	.["expired"] = expired
	.["near_cap_warnings"] = near_cap_warnings
	var/list/depth = depth_stats()
	.["depth_max"] = depth[1]
	.["depth_p95"] = depth[2]

/// The state of `source`'s lane, made on first use.
/datum/system/input/proc/lane_of(source)
	var/key = "[REF(source)]"
	var/list/L = lanes[key]
	if(!L)
		L = list(0, 0, null, null, null, null, FALSE, 0)
		lanes[key] = L
	L[INPUT_LANE_TOUCHED] = op_now()
	return L

/// Has `source` sent more inputs that cannot coalesce than INPUT_CLIENT_RATE_MAX in the current INPUT_RATE_WINDOW (this one counted)?
/datum/system/input/proc/rate_exceeded(source)
	var/list/L = lane_of(source)
	var/now = op_now()
	if(now - L[INPUT_LANE_RATE_START] >= INPUT_RATE_WINDOW)
		L[INPUT_LANE_RATE_START] = now
		L[INPUT_LANE_RATE_COUNT] = 0
	L[INPUT_LANE_RATE_COUNT]++
	return L[INPUT_LANE_RATE_COUNT] > INPUT_CLIENT_RATE_MAX

/// Refuses `E`: counted by the caller, logged (once per burst, to staff too), and the player told (at most every INPUT_REFUSE_NOTICE_EVERY). Never silent.
/datum/system/input/proc/refuse(datum/input_event/E, source, why)
	var/list/L = lane_of(source)
	var/now = op_now()
	var/kind = E.event_key()
	TEST_REC_OUTCOME(kind, ACT_REFUSED, /datum/msg/input/flood, E.actor)
	TEST_REC_LOG(kind, ACT_REFUSED, E.origin, E.actor, E.subject(), "refused: [why]")
	if(isnull(L[INPUT_LANE_LAST_REFUSAL]) || now - L[INPUT_LANE_LAST_REFUSAL] >= INPUT_REFUSE_BURST_GAP)
		var/who = E.actor ? key_name(E.actor) : "nobody"
		log_world("Input: refused a [kind] from [who]: [why] ([hard_refused] hard-cap and [rate_refused] rate refusals so far).")
		world.input_flood_report(E.actor, kind, why)
	L[INPUT_LANE_LAST_REFUSAL] = now
	if(isnull(L[INPUT_LANE_LAST_NOTICE]) || now - L[INPUT_LANE_LAST_NOTICE] >= INPUT_REFUSE_NOTICE_EVERY)
		L[INPUT_LANE_LAST_NOTICE] = now
		op_tell(E.actor, /datum/msg/input/flood)

/// `source`'s inbox now holds `depth` events: a client that stays at INPUT_CLIENT_NEAR_CAP or more for INPUT_NEAR_CAP_WARN gets a warning in the server log.
/datum/system/input/proc/watch_near_cap(source, depth)
	var/list/L = lane_of(source)
	if(depth < INPUT_CLIENT_NEAR_CAP)
		L[INPUT_LANE_NEAR_SINCE] = null
		return
	var/now = op_now()
	if(isnull(L[INPUT_LANE_NEAR_SINCE]))
		L[INPUT_LANE_NEAR_SINCE] = now
		return
	var/last_warning = L[INPUT_LANE_LAST_NEAR_WARNING]
	if(now - L[INPUT_LANE_NEAR_SINCE] >= INPUT_NEAR_CAP_WARN && (isnull(last_warning) || now - last_warning >= INPUT_NEAR_CAP_REPEAT))
		L[INPUT_LANE_LAST_NEAR_WARNING] = now
		near_cap_warnings++
		var/mob/who = ismob(source) ? source : null
		if(!who && istype(source, /client))
			var/client/C = source
			who = C.mob
		log_world("WARNING: Input: [who ? key_name(who) : "a client"]'s inbox has held [depth] of its [INPUT_CLIENT_MAX] inputs for [(now - L[INPUT_LANE_NEAR_SINCE]) / (1 SECONDS)] seconds.")

/// The deepest inbox and the 95th percentile of the inbox depths, over the clients that have one waiting: list(max, p95).
/datum/system/input/proc/depth_stats()
	var/list/depths = list()
	for(var/source in inboxes)
		depths += length(inboxes[source])
	if(!length(depths))
		return list(0, 0)
	depths = sortTim(depths, GLOBAL_PROC_REF(cmp_numeric_asc))
	return list(depths[length(depths)], depths[max(1, CEILING(length(depths) * 0.95, 1))])

/// Did the press of `source`'s last mouse button run and its release not yet?
/datum/system/input/proc/press_ran(source)
	var/list/L = lanes["[REF(source)]"]
	return L ? L[INPUT_LANE_PRESSED] : FALSE

/datum/system/input/proc/note_press(source, down)
	var/list/L = lane_of(source)
	L[INPUT_LANE_PRESSED] = down

/// Forgets the lanes that have been quiet for a minute.
/datum/system/input/proc/prune_lanes()
	var/now = op_now()
	for(var/key in lanes)
		var/list/L = lanes[key]
		if(now - L[INPUT_LANE_TOUCHED] >= 1 MINUTES && !L[INPUT_LANE_PRESSED])
			lanes -= key

/// The inbox's counters and depths (SSinput.metrics()), for the server metrics source (code/modules/metrics/metrics_sources.dm).
/proc/input_metrics()
	return SSinput.metrics()

// ---------------------------------------------------------------- the resolver seams (E2)
// input_resolve_click(), input_resolve_menu() and input_resolve_ui() are code/engine/parts/inputs.dm.

// ---------------------------------------------------------------- the driver's entry points

/// The click params a gesture stands for.
/proc/input_params_for(gesture)
	switch(gesture)
		if(GESTURE_SHIFT)
			return "left=1;shift=1"
		if(GESTURE_CTRL)
			return "left=1;ctrl=1"
		if(GESTURE_ALT)
			return "left=1;alt=1"
		if(GESTURE_MIDDLE)
			return "middle=1"
	return "left=1"

/// Resolves a click through the input inbox as origin `origin` would, and returns the op's /datum/op_result (null outcome
/// while it waits), or null when nothing resolved (queued, dropped, or E2's resolver is not there yet).
/proc/inbox_click(mob/actor, atom/target, atom/movable/held, gesture, origin)
	RETURN_TYPE(/datum/op_result)
	var/datum/input_event/click/E = new(actor, target, null, "mapwindow.map", input_params_for(gesture))
	E.driven = TRUE
	E.origin = origin || ORIGIN_CLICK
	E.gesture = gesture
	E.held = held // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input
	input_submit(E)
	return E.result

/// Drags `dragged` onto `over` through the input inbox as a player's drag would: the target's ops see it as the held atom. Returns the op's /datum/op_result.
/proc/inbox_drag(mob/actor, atom/dragged, atom/over)
	RETURN_TYPE(/datum/op_result)
	var/datum/input_event/drag/E = new(actor, dragged, over)
	E.driven = TRUE
	input_submit(E)
	return E.result

/// Presses a window button: the args cross the schema boundary, the op's ui_act() binding matches. Returns the op's /datum/op_result.
/proc/inbox_ui(mob/actor, window, action, list/args)
	RETURN_TYPE(/datum/op_result)
	var/datum/input_event/ui_act/E = new(actor, null, action, args)
	E.driven = TRUE
	E.window = window // ALLOW(ownership): a transient input record: the inbox drops it once resolved, and a relation would allocate an OM record per input
	input_submit(E)
	return E.result

/// Follows a topic link through the input inbox as a player's href would: the op of `holder` that names the href runs, origin ORIGIN_UI. Returns its
/// /datum/op_result, or null when no op names it.
/proc/inbox_topic(mob/actor, datum/holder, list/href_list)
	RETURN_TYPE(/datum/op_result)
	var/datum/input_event/topic/E = new(actor, holder, list2params(href_list), href_list)
	E.driven = TRUE
	input_submit(E)
	return E.result

/// Picks an op by key from a target's menu (origin ORIGIN_MENU), with `held` as the held item. Returns the op's /datum/op_result.
/proc/inbox_menu(mob/actor, atom/target, op_key, atom/movable/held)
	RETURN_TYPE(/datum/op_result)
	var/datum/input_event/menu/E = new(actor, target, op_key, held)
	E.driven = TRUE
	input_submit(E)
	return E.result
