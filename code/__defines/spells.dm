
#define OFFENSIVE_SPELLS "Offensive"
#define DEFENSIVE_SPELLS "Defensive"
#define UTILITY_SPELLS "Utility"
#define SUPPORT_SPELLS "Support"

/// Asks a question while a spell chooses its targets (spell_code.dm): the answer re-runs
/// perform_cast(), which asks the same questions again and gets the answers so far. Null while
/// waiting. `prompt` is a /datum/prompt/<kind>, named arguments set its vars.
#define cast_ask(user, key, prompt, fields...) rerun_ask_proc(user, key, PROC_REF(perform_cast), GLOB.spell_cast_args, prompt, list(fields))
