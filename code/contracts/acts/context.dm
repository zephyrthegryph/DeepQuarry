// The act context types (doc/rewrite/final_api.html, section 8 "Contexts"; section 7 "Contexts"). Every handler the
// engine calls takes one shape, x(datum/act/A), and the context is one of five narrow types, each naming the fields its
// hook form sets: /datum/act/op, /datum/act/eval, /datum/act/notice, /datum/act/timer and /datum/act/request. A world
// action's own context (/datum/act/fall and the rest of world_actions.dm) carries the op context's common fields through
// /datum/act/action.
//
// Vars only. This is the field layout E1-E6 build against; the build checks every field a handler reads against the
// context type its hook form names (E5), so a field that a type does not carry is a build error, not a null.
//
// Pool interface. Every context is pooled: it is a /datum/pooled, so take(/datum/act/op) hands out a clean one,
// .release() gives it back and resets every field below to its initial value (nothing is cleared by hand), and a
// released context is poisoned in test builds, so a holder that kept one past its trigger crashes on its next
// POOL_ASSERT_LIVE instead of reading another taker's data. A context lives for one trigger and is never stored in a var
// or a list, or passed in with = or delayed(): A.snapshot() returns a plain list of its fields for anything that must
// outlive the trigger. The object vars below are therefore transient references the pool resets, not owned references
// (ownership_lint: pooled transient, the same pattern as /datum/damage_packet).
//
// The engines write the fields; E0 declares them only, so nothing here has a proc.

/// The base of every trigger's context. Never instantiated.
/datum/act
	parent_type = /datum/pooled
	abstract_type = /datum/act
	/// The entity whose entry is running: src in PROC_REF handlers. Always set.
	var/datum/holder
	/// Set when the entry belongs to a capability.
	var/datum/capability/cap
	/// The activation running this entry: its params, state and source (section 5).
	var/datum/activation/activation
	/// The activation's source (an item, a species, the type): also the default owner of what this trigger places.
	var/datum/source

/// What an op and a world action share: the common fields of the op context, which a world action's generated context
/// (/datum/act/fall) carries too. Never instantiated.
/datum/act/action
	abstract_type = /datum/act/action
	/// What the action is done to. A datum, because a window or a prefs record can be one. With no target binding it is the holder.
	var/datum/target
	/// The acting mob; null for a world action without one.
	var/mob/actor
	/// The item the actor holds (an op's held item; null on a world action that has none): requirements read it in any context.
	var/obj/item/held
	/// ORIGIN_*: where the input arrived.
	var/origin
	/// What performs the op: a hand, a held tool, a module (a datum so a granted power can be one).
	var/datum/provider
	/// AUTH_*: the permission it is exercised under.
	var/authority
	/// FALSE when the op's chance() failed (section 9); otherwise TRUE.
	var/rolled = TRUE
	/// ACT_*: how the action ended. Null while an op waits. Set when it ends, and read by the notice and by tests.
	var/outcome
	/// The refusal reason (a /datum/msg type) when the action ended refused.
	var/reason
	/// What the hook that took the action over answered: the value its then() handler returned (HOOK_DECLINE leaves the action to the next taker).
	/// The caller reads it with ACT_REPLY right after ACT_TRY returned null; it is the payload of a veto (the name a disguise shows, the
	/// ITEM_INTERACT_* result of an item the holder took over).
	var/reply
	/// Validated UI or topic args (they also arrive as typed proc params), or an after(with =) payload.
	var/list/args

/// An op's context: its parts (requirements, effects, feedback) and the hooks on an op or an action.
/// Fields set: holder, target, target_atom, actor, held, origin, provider, authority, rolled, source, activation, cap,
/// args, request, answer, and the snapshot fields.
/datum/act/op
	parent_type = /datum/act/action
	/// The op's key chain as logged ("cover.open", "construction.build:door_wired").
	var/key
	/// The same entity as target, as an atom, set when the op declares target_type = /atom.
	var/atom/target_atom
	/// The latest request, whatever its outcome (section 13).
	var/datum/request/request
	/// The answered request, after asks() (section 13).
	var/datum/request/answer
	/// The fields captured when the op first suspended at an asks()/confirms()/captures() (section 13): name -> value.
	/// Read through A.captured(nameof(v)), never off the live holder.
	var/list/captured_values
	/// wait(repeats =): the laps of the repeating wait finished so far. Read it with A.laps().
	var/laps_done = 0
	/// Snapshot names, taken when the op starts: later feedback reads these, never a deleted object.
	var/held_name
	var/target_name
	var/actor_name

/// Conditions, contributions, look_layer(when =), outputs, and a requirement asked outside an op (a menu, an early cancel).
/// Reused by the kernel and allocated by nobody. Fields set: holder, cap, activation, and dt for outputs. No actor, held
/// item, target or origin: reading A.actor here is a build error.
/datum/act/eval
	/// Elapsed time, for outputs.
	var/dt
	/// The viewer, for the outputs a person reads (ui_data, examine): set there and nowhere else.
	var/mob/actor
	/// ui_data: TRUE when the viewer is a ghost looking at the window read-only (every ui_act it sends is refused; the window renders its buttons disabled).
	var/observer = FALSE

/// on_notice, on_op and on_change handlers. Fields set: holder, target, the notice's typed fields, outcome.
/datum/act/notice
	var/datum/target
	/// ACT_*: the outcome the notice carries.
	var/outcome
	/// The refusal reason (a /datum/msg type) of what ended refused: an op's (op_done for on_op(..., outcome = ACT_REFUSED)).
	var/refusal

/// after(), delayed(), every(), after_init() and sequence work. Fields set: holder, dt, args (after_init(): mapload); for a system's per-member work target is
/// the member; for a delayed() part, holder and the three snapshot names and nothing else.
/datum/act/timer
	var/dt
	/// after_init(): TRUE when it runs for an instance the map loaded (code/engine/actions/after_init.dm).
	var/mapload = FALSE
	var/list/args
	var/datum/target
	var/held_name
	var/target_name
	var/actor_name

/// request() callbacks. Fields set: holder (the owner), request, answer.
/datum/act/request
	var/datum/request/request
	var/datum/request/answer

/// Anything that waits for an answer (foundation X3, section 13): prompts, backend queries, client round trips.
/// E6 owns its fields (outcome, fields, timeout) and the request layer.
/datum/request
	/// REQ_*: how the step ended. Null while it waits.
	var/outcome

/// The result of perform_op() and of the test driver's forms (round 5, NB1): a small non-pooled record, never the pooled
/// act. The engine fills it when the op ends, and an op that is still in Wait comes back with a null outcome and the
/// same record carries the outcome once test_answer(), test_phase(KERNEL_PHASE_D), test_time() or wait_ticks() advance it.
/// It holds no reference to an entity, so a caller may keep it freely.
/datum/op_result
	/// The op key chain.
	var/key
	/// ACT_COMMITTED, ACT_REFUSED or ACT_REPLACED; null while the op still waits.
	var/outcome
	/// The refusal reason: a /datum/msg type, null unless refused.
	var/reason
	/// FALSE when the op's chance() failed; otherwise TRUE.
	var/rolled = TRUE
	/// TRUE when the op committed and said the input is not used up (an effect answered OP_PASS): the click went on to the next candidate.
	var/passed = FALSE
	/// ORIGIN_*: where the input arrived.
	var/origin

CAPABILITIES(/datum/act/timer)
	ref_one(nameof(target))

/// Borrow the current member only for this trigger; deletion clears the link before a later part reads it.
/datum/act/timer/proc/set_member_target(datum/member)
	rel_set(src, nameof(target), member)
