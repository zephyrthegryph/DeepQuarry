#define TRACKED(T,v)

/datum/cow_probe
	var/list/shared
	var/list/ordinary
	var/list/false_flag
	var/list/commented
/datum/cow_probe/child
	shared = null
	var/list/overridden

TRACKED(/datum/cow_probe, shared)
TRACKED(/datum/cow_probe, ordinary)
TRACKED(/datum/cow_probe, false_flag)
TRACKED(/datum/cow_probe, commented)
TRACKED(/datum/cow_probe/child, overridden)

#if 0
CAPABILITIES(/datum/cow_probe/child)
	per_type(nameof(shared), PROC_REF(build), copy_on_write = TRUE)
	per_type(nameof(ordinary), PROC_REF(build))
	per_type(nameof(false_flag), PROC_REF(build), copy_on_write = FALSE)
	// per_type(nameof(commented), PROC_REF(build), copy_on_write = TRUE)
CAPABILITIES_PART(/datum/cow_probe/child, more)
	per_type(nameof(overridden), PROC_REF(build), copy_on_write = 1)
	per_type(nameof(missing), PROC_REF(build), copy_on_write = TRUE)
#endif
