// Sequences: ordered steps per entity sharing a frame (code/controllers/kernel/sequence*.dm,
// doc/rewrite/life_sequences.md). Mob Life is /datum/sequence/life.

// ---- the step protocol
/// A step's handler returns this to stop the frame: the steps after it don't run and nothing sleeps this frame
/// (a step already put to sleep earlier in the frame wakes again). Return F.abort() to say why in one place.
#define STEP_ABORT "step_abort"

// ---- sleep bits: 16 steps to a word (the pipeline runner's layout, OM_PIPE_WORD)
#define SEQ_WORD(i) ((((i) - 1) >> 4) + 1)
#define SEQ_BIT(i) (1 << (((i) - 1) & 15))

/// E's state in the sequence with index `IDX` (a /datum/seq_state), or null.
#define SEQ_STATE_OF(E, IDX) (length((E).seq_states) >= (IDX) ? (E).seq_states[IDX] : null)

// ---- a step's target (/datum/seq_step/target_kind)
/// A proc on the entity: handler(frame), should_run(), rewake().
#define SEQ_TARGET_ENTITY 0
/// A proc on a shared contributor (a capability of the entity's type): handler(entity, frame), should_run(entity).
#define SEQ_TARGET_STATIC 1
/// A proc on one of the entity's own contributors (seq_extra_add()): handler(entity, frame), should_run(entity).
#define SEQ_TARGET_EXTRA 2

/// The membership source a sequence's awake members hold their sweep membership under.
#define SEQ_SOURCE "sequence"
/// Published on a member when its STAT_RELEVANCE moved (relevance_changed()): a sequence with a min_relevance re-checks it is in the sweep.
#define SEQ_KEY_RELEVANCE "seq_relevance"
/// A sequence has at most this many conditions (one bit each in a frame).
#define SEQ_MAX_CONDITIONS 24
/// The missed-wake audit's sample per sequence and pass (parked members, awake members with a sleeping step).
#define SEQ_AUDIT_PARKED_SAMPLE 400
#define SEQ_AUDIT_AWAKE_SAMPLE 100
