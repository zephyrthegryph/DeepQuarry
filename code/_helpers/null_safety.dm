// Null-safety helpers (unified plan sec 2.16, "No nulls in APIs").
//
// DM can't remove null from the language, so gameplay code keeps it out of its own APIs:
//   - accessors never return null: they create the thing, or assert that it exists (must_be());
//   - "none" is a null object, a shared do-nothing datum of the right type (null_object_of()),
//     not null;
//   - "unset" is a defined sentinel (NO_Z, NIGHTSHIFT_AUTO), not null.
// A converted folder then has no `?.` chains or `if(!x) return` guards on values the framework
// guarantees, and DreamChecker can check the types.

/// The z-level `A` is on, or NO_Z when it is on none (nullspace, or held with no turf under it).
/proc/z_of(atom/A)
	var/turf/T = get_turf(A)
	return T ? T.z : NO_Z

/// `value` if it is a `type`, else a runtime naming what it was. For accessors and entry points
/// that promise a typed value: the failure is a bug at the caller or the accessor, never a case to
/// handle. `type` is a type path; a null or wrongly typed value fails.
/proc/must_be(value, type)
	if(istype(value, type))
		return value
	CRASH("expected a [type], got [isnull(value) ? "null" : (isdatum(value) ? "[value:type]" : "[value]")]")

/// `value` if it is a `type`, else the null object of `fallback_type`: for a lookup that may find
/// nothing (a blood type, a thermal profile) where "nothing" has a defined behaviour.
/proc/type_or_null_object(value, type, fallback_type)
	if(istype(value, type))
		return value
	return null_object_of(fallback_type)

/// A do-nothing stand-in for "none". Subtype it per family (`/datum/species_blood/none`,
/// `/datum/thermal_profile/default`), make the family's base type answer every question with its
/// neutral value, and hand out the shared instance from null_object_of(). Never deleted.
/datum/null_object

/datum/null_object/lifecycle_keep(force)
	return TRUE

/// The shared instance of the null object `type`, created on first use. A null object holds no
/// state, so one instance serves every caller.
/proc/null_object_of(type)
	var/static/list/instances = list()
	var/datum/null_object/instance = instances[type]
	if(instance)
		return instance
	instance = new type
	if(!istype(instance, /datum/null_object))
		CRASH("[type] is not a /datum/null_object")
	instances[type] = instance
	return instance

/// TRUE for a null object (the "none" stand-in), for the rare caller that must tell.
/proc/is_null_object(datum/D)
	return istype(D, /datum/null_object)
