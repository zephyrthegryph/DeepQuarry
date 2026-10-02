// Markers expand to nothing (the analysis engine reads them from text); TRACKED/SETTER are the repo's real shapes.
#define CAPABILITIES(T, entries...)
#define STAT(T, name, rule, params...)
#define READS_AS(proc, key, args...)
#define READS_FROM(args...)
#define TRACKED(T, V) ##T/proc/set_##V(value) { if(V == value) { return FALSE }; V = value; tracked_changed(src, #V); return TRUE };SETTER(T, V)
#define SETTER(T, V) ##T/proc/__setter_##V() { return TRUE }

#define TRUE 1
#define FALSE 0
#define ACT_PASS (-1)
// ACT_TRY must survive expansion as a call the pairing check can see.
#define ACT_TRY(holder, act, args...) act_try(holder, /datum/act/##act, args)
#define ACTION(name, fields...)
