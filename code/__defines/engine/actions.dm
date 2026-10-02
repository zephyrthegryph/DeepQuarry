// Action, hook and notice forms of the engine (doc/rewrite/final_api.html, section 8 "World actions", section 10 "Hooks and events";
// section 19 "E4, actions and hooks"). The act types, act_<name>() and the notices come from `ACTION()` (tools/analyze/src/gens/actions.rs,
// code/engine/_generated/actions.dm); the engine is code/engine/actions/.

/// Tries a world action: `var/datum/act/fall/F = ACT_TRY(src, fall, T, M)` is `act_fall(src, T, M)`. The result is the final act after every
/// adjusts(); ACT_PASS when nothing hooks the action and no listener wants its notice (nothing is allocated); or null when it was refused or
/// taken over. Every path of the caller then ends it with act_done(F) or act_cancel(F) (the pairing lint, tools/analyze sem/handlers).
/// The token is the action's name with an underscore for a slash: ACT_TRY(src, hit_projectile, packet).
#define ACT_TRY(E, token, args...) act_##token(E, ##args)
/// The final value of an action's field: the act's own field when ACT_TRY returned a real act (an adjusts() may have changed it), the caller's
/// local when it returned ACT_PASS (nothing could have adjusted it). `ACT_FINAL(F, landing, T)`.
#define ACT_FINAL(F, field, local) ((F) == ACT_PASS ? (local) : F.field)

/// Announces a FIXED action (nothing can refuse it): `PUBLISH(world_owner(), round_started)`, `PUBLISH(src, slash, slasher = user)`. Allocates
/// nothing when nobody listens. The legacy `PUBLISH(E, /datum/notice/x, args)` is PUBLISH_LEGACY.
#define PUBLISH(E, token, args...) publish_##token(E, ##args)
/// TRUE when something on E listens for notice TYPE for the outcome (default committed). Test it before building an expensive payload.
#define WANTS(E, TYPE, outcome...) notice_wanted(E, TYPE, ##outcome)
/// The legacy form: announces an occurrence with a notice built from positional arguments (code/datums/reactions). Retired per notice as it
/// becomes an ACTION.
#define PUBLISH_LEGACY(E, TYPE, ARGS...) if(notice_wanted(E, TYPE, ACT_COMMITTED)) { publish(E, take_notice(TYPE, ARGS)) }

// ---- on_change edges ----
/// Fires when the condition becomes true.
#define ENTER (1<<0)
/// Fires when the condition becomes false.
#define EXIT (1<<1)
/// Fires when the key's value changed (the only edge of a numeric key).
#define ANY (ENTER | EXIT)

// ---- hook order (instead and adjusts): the first taker in order wins ----
#define ORDER_EARLY 1
#define ORDER_NORMAL 2
#define ORDER_LATE 3

/// Names a proc of the capability datum as a handler: then(CAP_PROC(reflect)) inside the datum's entries(). The proc is x(datum/act/A), with
/// A.cap the capability.
#define CAP_PROC(x) ("cap:" + PROC_REF(x))

/// The capability of triggers only (hook_capability(), observe(), while_slotted entries that are not capabilities).
#define CAP_HOOK 8

// ---- hook kinds (a /datum/hook's kind) ----
#define HOOK_NEEDS "needs"
#define HOOK_INSTEAD "instead"
#define HOOK_ADJUSTS "adjusts"
#define HOOK_NOTICE "on_notice"
#define HOOK_CHANGE "on_change"

/// The entry kinds E4 owns.
#define ENTRY_ON_NOTICE "on_notice"
#define ENTRY_ON_CHANGE "on_change"
#define ENTRY_INSTEAD "instead"
#define ENTRY_ADJUSTS "adjusts"
#define ENTRY_NEEDS "needs"
#define ENTRY_THEN "then"
#define ENTRY_CHANCE "chance"

/// Rule names a report carries (tests assert on them).
#define RULE_ACT_DEPTH "act_depth"
#define RULE_NOTICE_DEPTH "notice_depth"
