// TOPIC_ACTION registry (doc/rewrite/systems.md §20).
//
// One core dispatcher (topic_dispatch(), code/datums/topic/topic_dispatch.dm) replaces every
// Topic() override. A type declares its href actions as rows:
//
//	TOPIC_ACTION(/datum/admins, "adminplayeropts", PROC_REF(topic_player_opts), TOPIC_REF("adminplayeropts", /mob), TOPIC_RIGHTS(R_ADMIN))
//
// The dispatcher finds the row by href key (a key "action=foo" matches href action=foo, and is
// tried before a bare "action" row), checks the op's needs() (req_topic_token() and the like), each
// TOPIC_RIGHTS, resolves each TOPIC_REF with `locate(ref) in <source>` plus an istype check,
// converts TOPIC_NUM / TOPIC_TEXT, then calls the handler as
//	proc(mob/user, list/args)
// where args[name] is the validated value (null when the href omitted it) and args[TOPIC_HREF]
// is the raw href_list (for topic_ask() re-runs; never locate() from it).
// Rows inherit: a subtype sees its parents' rows; a row for the same key replaces the parent's.

/// args key holding the raw href_list (topic_ask() reads it).
#define TOPIC_HREF "_href"

#define TOPIC_SPEC_REF 1
#define TOPIC_SPEC_NUM 2
#define TOPIC_SPEC_TEXT 3
#define TOPIC_SPEC_RIGHTS 4

// TOPIC_REF sources. Omitted: /client -> TOPIC_IN_CLIENTS, /turf -> TOPIC_IN_WORLD, else TOPIC_ANY.
/// Any object of the declared type (datums, mobs in nullspace, records): the istype is the check.
#define TOPIC_ANY "any"
/// An atom on the map.
#define TOPIC_IN_WORLD "world"
/// A connected client.
#define TOPIC_IN_CLIENTS "clients"
/// A live mob (the mob registry).
#define TOPIC_IN_MOBS "mobs"
/// Something inside the target itself (target.contents).
#define TOPIC_IN_CONTENTS "contents"
// Anything else is a proc name on the target (PROC_REF(my_list)) returning the list to search.

/// Declares one href action on PATH. Expands to a topic_actions() link (like DECLARE_REF).
#define TOPIC_ACTION(PATH, KEY, PROC, SPECS...) ##PATH/topic_actions() { return topic_register(..(), KEY, PROC, list(SPECS)); }
/// A row in a separate href namespace NS: plain Topic() hrefs never reach it; only a dispatch that
/// names NS does (topic_find_row(target, href_list, NS)), which brings its own gate (View
/// Variables: topic_dispatch_vv()).
#define TOPIC_NS_ACTION(PATH, NS, KEY, PROC, SPECS...) ##PATH/topic_actions() { return topic_register(..(), KEY, PROC, list(SPECS), NS); }
/// href value `NAME` is a ref to a TYPE (or any of a list of types; null: anything locate() finds, TOPIC_ANY only, the handler validates), looked up in SOURCE (see above).
#define TOPIC_REF(NAME, TYPE, SOURCE...) (list(TOPIC_SPEC_REF, NAME, TYPE) + list(SOURCE))
/// href value `NAME` as a number (null if absent or not numeric).
#define TOPIC_NUM(NAME) list(TOPIC_SPEC_NUM, NAME)
/// href value `NAME` as text, optionally cut to MAXLEN characters.
#define TOPIC_TEXT(NAME, MAXLEN...) (list(TOPIC_SPEC_TEXT, NAME) + list(MAXLEN))
/// The clicker needs one of RIGHTS (R_*).
#define TOPIC_RIGHTS(RIGHTS) list(TOPIC_SPEC_RIGHTS, RIGHTS)
