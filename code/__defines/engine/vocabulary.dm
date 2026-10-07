// Engine vocabulary (doc/rewrite/final_api.html, sections 2, 8, 9 and 13): outcomes, origins, reach policies,
// authorities, intents, affordances, op keeps, request outcomes and the engine constants the E0 contracts and the
// test driver share. Constants only; layer 1 of the compile order (section 22).
//
// Several families already have members on master (AFF_*, GESTURE_*, OP_PRIORITY_*, LANE_*, KERNEL_PHASE_*). Those
// keep their live definition; this file adds only the members the final API needs and master lacks. The ones whose
// meaning differs are listed in doc/rewrite/engine_contracts.md ("Name clashes") for the engine that retires the
// legacy form.

// ---- Action outcomes (section 8). One vocabulary for an act's outcome and for the notice/on_op outcome filters. ----
/// The action happened (an op that committed; a failed chance() is ACT_COMMITTED with rolled = FALSE).
#define ACT_COMMITTED (1<<0)
/// A requirement, or the caller, said no (a failed op is reported as ACT_REFUSED with the runtime logged).
#define ACT_REFUSED (1<<1)
/// Something else happened instead (an instead hook took it over).
#define ACT_REPLACED (1<<2)
/// Filter only: a committed op whose chance() failed. An act's own outcome is never this value.
#define ACT_ROLL_FAILED (1<<3)
/// An op handler answered OP_DECLINE: the op did not apply after all, nothing was committed, told or published, and the click goes on to the next
/// candidate. An act's own outcome only; no filter selects it and ACT_ANY does not include it.
#define ACT_DECLINED (1<<4)
/// Filter only: every outcome.
#define ACT_ANY (ACT_COMMITTED | ACT_REFUSED | ACT_REPLACED | ACT_ROLL_FAILED)
/// ACT_TRY's shared "nothing hooks this action" constant (section 8). Carries no fields; act_done()/act_cancel() ignore it.
#define ACT_PASS (-1)
/// Synchronous nesting depth of actions and notices before a notice is queued and an action is refused.
#define ACT_MAX_DEPTH 8

// ---- Op effect reports (section 9). OP_* is the effect report vocabulary only; filters use ACT_*. ----
#define OP_OK 1
#define OP_REFUSED 2
#define OP_REPLACED 3
#define OP_FAILED 4
/// A then() handler or effect proc answers this to say "not handled": the op ends ACT_DECLINED with no cost committed, no notice and no message, and a click
/// resolves on to the next candidate (the veto hooks' HOOK_DECLINE, for an op). Effects that ran before the declining one are not undone: decline from the
/// first effect, before anything is written.
#define OP_DECLINE 5
/// A then() handler or effect proc answers this to say "handled, but the input is not used up": the op commits, and the click goes on to the next candidate
/// whose conditions hold, then on to the mob's own click handling (afterattack, the loot panel). The per-return form of the passes() part (the old INTERACTION_HANDLED_PASS).
#define OP_PASS 6

// ---- Origins: where an input arrived (section 8). Bits, so acts_via can be a mask (at most 24). ----
#define ORIGIN_NONE 0
#define ORIGIN_CLICK (1<<0)
#define ORIGIN_UI (1<<1)
#define ORIGIN_MENU (1<<2)
#define ORIGIN_VERB (1<<3)
#define ORIGIN_HOTKEY (1<<4)
#define ORIGIN_AI (1<<5)
#define ORIGIN_SYSTEM (1<<6)
#define ORIGIN_ALL (ORIGIN_CLICK | ORIGIN_UI | ORIGIN_MENU | ORIGIN_VERB | ORIGIN_HOTKEY | ORIGIN_AI | ORIGIN_SYSTEM)

// ---- Reach policies: the spatial relation an op needs (section 8). ----
#define REACH_ADJACENT 1
#define REACH_INSIDE 2
#define REACH_VIEW 3
#define REACH_ANY 4
/// REACH_RANGE(n): within n tiles, whatever the provider reaches. Encoded above the named policies.
#define REACH_RANGE_BASE 1000
#define REACH_RANGE(n) (REACH_RANGE_BASE + (n))

// ---- Authorities: the permission an op is exercised under (section 8). Bits, so a binding can accept a mask. ----
#define AUTH_PHYSICAL (1<<0)
#define AUTH_REMOTE_ACCESS (1<<1)
#define AUTH_ADMIN (1<<2)
#define AUTH_AI (1<<3)

// ---- Intents and the one gesture master lacks (section 8). GESTURE_CLICK/_SHIFT/_CTRL/_ALT/_DRAG/_SELF exist. ----
#define INTENT_USE 1
#define INTENT_ATTACK 2
#define INTENT_TOGGLE 3
#define INTENT_OPEN 4
#define INTENT_EJECT 5
#define INTENT_DROP_ONTO 6
#define INTENT_EXAMINE 7
#define INTENT_PRESENT 8
#define GESTURE_MIDDLE "middle_click"

// ---- Affordances the final API adds (AFF_HOLD, _MANIPULATE, _HOLD_SMALL, _CONTROL exist with legacy values). ----
#define AFF_ATTACK (1<<5)
#define AFF_OBSERVE (1<<6)

// ---- Busy policy for a second input while an op waits (section 9). ----
#define BUSY_REPLACE 1
#define BUSY_REFUSE 2

// ---- Claims (section 9): what a waiting op holds exclusively. Ops whose claims overlap conflict; ops that share none coexist. ----
/// The actor's hands: a tool or item in use, a click that works something.
#define CLAIM_HANDS (1<<0)
/// The actor's body: the op needs the actor to stand and work (a timed action that is broken by moving).
#define CLAIM_BODY (1<<1)
/// The target: a second claiming op on it is refused, and the target draws the work (op_claimed()).
#define CLAIM_TARGET (1<<2)
#define CLAIM_ALL (CLAIM_HANDS | CLAIM_BODY | CLAIM_TARGET)
/// The most pending ops (waits and open questions) one actor may have at once: one more is refused with a message.
#define OP_PENDING_CAP 10

// ---- Op wait keeps (section 9): what cancels a wait or an open asks(). ----
#define HELD (1<<0)
#define ADJACENT (1<<1)
#define TARGET_PRESENT (1<<2)
#define ALIVE (1<<3)
/// The actor stays where it started (a timed action is cancelled by walking away, as the legacy timed actions were).
#define STAY (1<<4)
#define WAIT_KEEPS_DEFAULT (HELD | ADJACENT | TARGET_PRESENT | ALIVE | STAY)

// ---- Where an effect lands (section 8). ----
#define ON_TARGET 1
#define ON_HOLDER 2
#define ON_ACTOR 3
#define ON_HELD 4
#define ON_CONTENTS 5
/// verb_entry(): the verb lands on the activation's source instead of its holder (an item's own verb, listed while a mob carries it).
#define ON_SOURCE 6

// ---- Slot families a while_slotted() may name (scopes.dm, slot_matches()). ----
/// Any slot of the holder that is worn equipment (a body slot with BODY_SLOT_WORN).
#define SLOT_ANY_WORN "any_worn"
/// Any hand of the holder.
#define SLOT_ANY_HELD "any_held"
/// Any body slot of the holder: a hand or anything worn, a pocket included.
#define SLOT_ANY_CARRIED "any_carried"

// ---- Request outcomes: one enum for every workflow step (section 13). ----
#define REQ_ANSWERED 1
#define REQ_CANCELLED 2
#define REQ_TIMED_OUT 3
#define REQ_TRANSPORT_FAILED 4
#define REQ_NO_RESULT 5
#define REQ_FAILED 6

// ---- Resume policy of a captured asks() field (section 13). ----
#define CAPTURE 1
#define LATEST 2
#define CANCEL_IF_CHANGED 3

// ---- Hold priority levels (section 5). ----
#define PRIORITY_DEFAULT 0
#define PRIORITY_FORCE 100
#define PRIORITY_ADMIN 1000

// ---- Kernel and drain constants (sections 2 and 7). ----
/// Passes of one drain before the engine logs the key chain and spills the rest to the next drain point.
#define DRAIN_MAX_PASSES 8
