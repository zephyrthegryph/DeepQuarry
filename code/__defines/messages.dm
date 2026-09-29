// Message templates (doc/rewrite/systems.md §15).
//
// act_message(user, target, MSG_SELF(...), MSG_OTHERS(...), MSG_BLIND(...), range, item)
// sends the actor its own line and everyone else who can see the other line (blind
// observers get the blind line). Text keeps its span wrapping: MSG_SELF(span_notice("..."))
// works as before. Tokens, filled per call:
//   %U%  the user        %T%  the target        %I%  the item
//        (each is "\the [x]"; at the start of a line it becomes "\The [x]")
//   %THEY% %THEM% %THEIR% %THEIRS% %THEMSELVES% %THEYRE% %THEYVE% %S% %ES%: the user's pronouns
//   %They% %Them% %Their% %Theyre%: capitalised forms
// Declared templates are /datum/msg/<x> singletons: act_message_t(user, target, /datum/msg/x).

/// Readability wrappers: act_message's positional text arguments.
#define MSG_SELF(text) (text)
#define MSG_OTHERS(text) (text)
#define MSG_BLIND(text) (text)

/// Declares a template in one line: MSG_DEF(pry, "You pry %T% open.", "%U% pries %T% open.")
#define MSG_DEF(name, self_text, others_text) /datum/msg/##name{self = self_text; others = others_text}
/// A template shown to the actor only.
#define MSG_DEF_SELF(name, self_text) /datum/msg/##name{self = self_text}
