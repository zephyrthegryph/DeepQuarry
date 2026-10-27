// Question sequences (code/datums/prompts/sequence.dm).

// ---- question sequences (code/datums/prompts/sequence.dm) ----
/// One step of an ask_sequence(): question_step(key, /datum/prompt/x, field = value, ...).
#define question_step(key, prompt, fields...) list("key" = key, "type" = prompt, "fields" = list(fields))
/// Asks the steps in turn: ask_sequence(/datum/ask_sequence/x, answerer, subject, steps, PROC_REF(done), var = value...). on_done runs on src.
#define start_ask_sequence(sequence, answerer, subject, steps, on_done, params...) ask_sequence_begin(src, sequence, answerer, subject, steps, on_done, null, null, list(params))
/// Returned by a sequence's step proc: the sequence ends there.
#define ASK_STOP "ask_stop"
/// Returned by a sequence's step proc that started a child sequence (ask_child()): the sequence waits until the child finishes.
#define ASK_WAIT "ask_wait"
/// Returned by a sequence's step proc: the sequence ends successfully there (on_done runs).
#define ASK_FINISH "ask_finish"
