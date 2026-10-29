#define SCHEMA(T,V,S)
#define TRACKED_SCHEMA(T,V,S)
/datum/allowed
/datum/rejected
SCHEMA(/datum/probe, ordered, schema_path(/datum/allowed))
TRACKED_SCHEMA(/datum/probe, grouped, schema_path(/datum/allowed))
