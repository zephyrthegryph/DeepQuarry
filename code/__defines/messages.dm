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
/// Free text a player supplied (an emote, a label, a typed name): its % is shown as typed and never
/// read as a token. Wrap only the player's part, e.g. "%U% writes: [MSG_LITERAL(str)]".
#define MSG_LITERAL(text) msg_literal(text)

/// Declares a template in one line: MSG_DEF(pry, "You pry %T% open.", "%U% pries %T% open.")
#define MSG_DEF(name, self_text, others_text) /datum/msg/##name{self = self_text; others = others_text}
/// A template shown to the actor only.
#define MSG_DEF_SELF(name, self_text) /datum/msg/##name{self = self_text}
/// Where a template's actor line is shown: in chat (the default), or as a balloon over the actor (a refusal that never wrote to chat).
#define MSG_DISPLAY_CHAT 0
#define MSG_DISPLAY_BALLOON 1
/// A template shown to the actor as a balloon alert, not a chat line: because = MSG(x) and starts() refusals route it to balloon_alert(). No tokens, plain text.
#define MSG_BALLOON(name, text) /datum/msg/##name{self = text; display = MSG_DISPLAY_BALLOON}
