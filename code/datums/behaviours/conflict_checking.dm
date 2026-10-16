/**
 * Simple conflict checking for getting number of conflicting things on someone with the same ID
 * (was /datum/element/conflict_checking). Conflict groups are inherited type traits.
 */
#define ENTRY_CONFLICT_GROUP "conflict_group"
#define CONFLICT_GROUP_KEY "conflict_group"

STATIC_ENTRY(conflict_group)
/proc/conflict_group(id = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_CONFLICT_GROUP, null, list("id" = id))

/datum/type_trait/conflict_group
	var/id

/datum/type_trait/conflict_group/copy_values(datum/type_trait/conflict_group/into)
	into.id = id

/datum/entry_engine/type_trait/conflict_group
	kind = ENTRY_CONFLICT_GROUP
	trait_type = /datum/type_trait/conflict_group
	publish_key = CONFLICT_GROUP_KEY
	base_type = /atom
	var_names = list("conflict_id" = "id")

READS_AS(/proc/conflict_group_of, CONFLICT_GROUP_KEY)
/proc/conflict_group_of(atom/holder) as /datum/type_trait/conflict_group
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_CONFLICT_GROUP)

/**
 * Counts number of conflicts on something that have the conflict id `id`.
 */
/atom/proc/ConflictElementCount(id)
	. = 0
	for(var/i in GetAllContents())
		var/atom/movable/AM = i
		if(conflict_group_of(AM).id == id)
			++.
