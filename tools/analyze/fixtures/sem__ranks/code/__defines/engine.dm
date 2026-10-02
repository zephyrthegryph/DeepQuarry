// Markers expand to nothing (the analysis engine reads them from text); TRACKED/SETTER/REL are the repo's shapes.
#define CAPABILITIES(T, entries...)
#define STAT(T, name, rule, params...)
#define SYSTEM_ACCESSOR(system, name, key)
#define READS_AS(proc, key, args...)
#define READS_FROM(args...)
#define REL(T, V) /datum/rel_marker/##V
#define TRACKED(T, V) ##T/proc/set_##V(value) { if(V == value) { return FALSE }; V = value; tracked_changed(src, #V); return TRUE };SETTER(T, V)
#define SETTER(T, V) ##T/proc/__setter_##V() { return TRUE }
#define PUBLISH_CHANGE(E, KEY) publish_change(E, KEY)
#define TRUE 1
#define FALSE 0
