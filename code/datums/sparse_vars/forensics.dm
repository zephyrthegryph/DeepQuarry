// Forensics-related per-atom state:
//   - forensic_was_bloodied  (FALSE/TRUE)  -- has this been bloodied
//   - forensic_blood_color   (color str)   -- color of blood it produces / is stained with
//   - forensic_data          (datum ref)   -- forensics crime datum (fingerprints, etc.),
//                                             the owned /atom/var/forensic_data (_atom.dm)
//   - forensic_fluorescent   (0/1/2)       -- UV-light state
//
// Plain saved vars on /atom: an unset var costs an instance nothing (BYOND
// stores only vars that differ from the type default), and set ones save with
// the atom's delta. blood_color has per-type defaults (synth/various species
// blood colors) in a type-default GLOB; the var is the per-instance override.

GLOBAL_LIST_INIT(dq_blood_color_by_type, list(
	// Default for /atom is null. The robolimb file's per-subtype overrides
	// (robolimbs_*.dm) populate this list at world-init via the registration
	// hook below. Add explicit defaults here only for non-instance-overrideable
	// types if needed.
))

/atom
	var/forensic_was_bloodied
	/// Per-instance blood color, or null for the per-type default.
	var/forensic_blood_color
	var/forensic_fluorescent

/// Tracked: a drawn thing that shows its blood (a clothing item's stain) redraws when these change; the dq_set_* helpers below are the writers.
TRACKED(/atom, forensic_was_bloodied)
TRACKED(/atom, forensic_blood_color)
TRACKED(/atom, forensic_fluorescent)

// ---- Helpers (global procs to avoid /atom proc-table bloat) ----

/proc/dq_get_was_bloodied(atom/a)
	return a.forensic_was_bloodied

/proc/dq_set_was_bloodied(atom/a, v)
	a.set_forensic_was_bloodied(v)

GLOBAL_LIST_EMPTY(_dq_blood_color_resolved)

/proc/dq_get_blood_color(atom/a)
	if(a.forensic_blood_color != null)
		return a.forensic_blood_color
	return _dq_resolve_typed_default(a.type, GLOB.dq_blood_color_by_type, GLOB._dq_blood_color_resolved, null)

/proc/dq_set_blood_color(atom/a, color)
	a.set_forensic_blood_color(color)

/proc/dq_get_forensic_data(atom/a)
	return a.forensic_data

/proc/dq_set_forensic_data(atom/a, datum/forensics_crime/fd)
	rel_set(a, nameof(/atom::forensic_data), fd)

/proc/dq_get_fluorescent(atom/a)
	return a.forensic_fluorescent

/proc/dq_set_fluorescent(atom/a, v)
	a.set_forensic_fluorescent(v)
