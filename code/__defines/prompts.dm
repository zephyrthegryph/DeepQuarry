// Re-run prompts: the legacy procs that ask before they act (code/datums/prompts/reruns.dm).

// ---- re-run prompts (code/datums/prompts/reruns.dm): the first call asks and returns null; the answer re-runs the caller, where
// the same call returns the answer. `prompt` is a /datum/prompt kind; the named arguments are its fields (open_request()'s), plus
// cancel_answer. ----
/// In an ADMIN_VERB body (`verb_args`: the verb's args).
#define verb_ask(user, key, verb_args, prompt, fields...) verb_rerun_ask(user, key, verb_args, prompt, list(fields))
/// In a /client proc: re-runs proc_name with proc_args; `rights` (R_*) are re-checked.
#define client_ask(key, proc_name, proc_args, rights, prompt, fields...) client_rerun_ask(key, proc_name, proc_args, rights, prompt, list(fields))
/// In any datum proc: re-runs proc_name on src with proc_args.
#define rerun_ask(user, key, proc_name, proc_args, prompt, fields...) rerun_ask_proc(user, key, proc_name, proc_args, prompt, list(fields))
/// The same, re-running proc_name on `target` instead of src.
#define rerun_ask_on(target, user, key, proc_name, proc_args, prompt, fields...) target.rerun_ask_proc(user, key, proc_name, proc_args, prompt, list(fields))
/// Deep inside a prompt_flow().
#define flow_ask(user, key, prompt, fields...) prompt_flow_ask(user, key, prompt, list(fields))
/// Thrown by flow_io_answer() to unwind a prompt flow whose query is in flight; prompt_flow() catches it.
#define PROMPT_FLOW_PENDING "prompt_flow_pending"

// ---- question sequences (code/datums/prompts/sequence.dm) ----
/// One step of an ask_sequence(): question_step(key, /datum/prompt/x, field = value, ...).
#define question_step(key, prompt, fields...) list("key" = key, "type" = prompt, "fields" = list(fields))
/// Asks the steps in turn: ask_sequence(/datum/ask_sequence/x, answerer, subject, steps, PROC_REF(done), var = value...). on_done runs on src.
#define start_ask_sequence(sequence, answerer, subject, steps, on_done, params...) ask_sequence_begin(src, sequence, answerer, subject, steps, on_done, null, null, list(params))
/// Returned by a sequence's step proc: the sequence ends there.
#define ASK_STOP "ask_stop"
