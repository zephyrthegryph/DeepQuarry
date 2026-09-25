/**
 * Accessors for /mob/var/list/mutations.
 *
 * `mutations` is a lazy list (null when empty) of mutation defines
 * (HULK, HUSK, XRAY, ...). Everything that reads or writes it goes through
 * these procs so a future storage change (e.g. folding mutations into
 * capabilities) only has to touch this file.
 */

/// Returns TRUE if this mob currently has the given mutation.
/mob/proc/has_mutation(mut)
	return mut && LAZYFIND(mutations, mut) ? TRUE : FALSE

/// Adds a mutation to this mob. Does not deduplicate, matching the previous
/// raw list.Add() behaviour.
/mob/proc/add_mutation(mut)
	if(!mut)
		return
	LAZYADD(mutations, mut)
	update_mutation_immunities(mut)

/// Removes every occurrence of the given mutation from this mob.
/mob/proc/remove_mutation(mut)
	if(!mut)
		return
	LAZYREMOVE(mutations, mut)
	update_mutation_immunities(mut)

/// Returns the number of mutations currently active on this mob.
/mob/proc/mutation_count()
	return LAZYLEN(mutations)

/// Returns a copy of the active mutations list (safe to iterate/mutate by the caller).
/// Never returns null -- returns an empty list instead.
/mob/proc/get_mutations()
	return mutations ? mutations.Copy() : list()
