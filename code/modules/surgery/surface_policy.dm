// Surgical suitability is surface policy, independent of damage, germ and patient state.
STATIC_ENTRY(surgery_surface)

/proc/surgery_surface(cleanliness = null)
	return entry_make(ENTRY_SURGERY_SURFACE, null, list("cleanliness" = cleanliness))

/datum/type_trait/surgery_surface
	var/cleanliness = 0

/datum/type_trait/surgery_surface/copy_values(datum/type_trait/surgery_surface/into)
	into.cleanliness = cleanliness

/datum/entry_engine/type_trait/surgery_surface
	kind = ENTRY_SURGERY_SURFACE
	trait_type = /datum/type_trait/surgery_surface
	publish_key = SURGERY_SURFACE_KEY
	base_type = /obj
	var_names = list("surgery_cleanliness" = "cleanliness")

READS_AS(/proc/surgery_surface_of, SURGERY_SURFACE_KEY)
/proc/surgery_surface_of(obj/O) as /datum/type_trait/surgery_surface
	READS_FROM(O)
	return type_trait_of(O, ENTRY_SURGERY_SURFACE)

/proc/surgery_surface_of_type(path) as /datum/type_trait/surgery_surface
	READS_FROM()
	return type_trait_of_type(path, ENTRY_SURGERY_SURFACE)
