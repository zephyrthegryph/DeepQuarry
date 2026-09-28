// Forensics-related vars formerly on /atom:
//   - was_bloodied        (FALSE/TRUE)  — has this been bloodied
//   - blood_color          (color str)   — color of blood it produces / is stained with
//   - forensic_data         (datum ref)   — forensics crime datum (fingerprints, etc.)
//   - fluorescent           (0/1/2)       — UV-light state
//
// Sparse — most atoms are never bloodied / fingerprinted / glowed-under-UV.
// blood_color has many per-type defaults (synth/various species blood colors),
// stored in a type-default GLOB plus per-instance component for overrides.

GLOBAL_LIST_INIT(dq_blood_color_by_type, list(
	// Default for /atom is null. The robolimb file's per-subtype overrides
	// (robolimbs_*.dm) populate this list at world-init via the registration
	// hook below. Add explicit defaults here only for non-instance-overrideable
	// types if needed.
))

// Per-instance forensics state. All four properties live on one component
// because they're almost always set together for the same atom and we want
// to minimize component count.
/datum/component/forensics_state
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/was_bloodied
	var/blood_color
	var/datum/forensics_crime/forensic_data
	var/fluorescent

// ---- Helpers (global procs to avoid /atom proc-table bloat) ----

/proc/dq_get_was_bloodied(atom/a) // ALLOW(base_proc): global API written before the base-type ratchet
	var/datum/component/forensics_state/c = a.GetComponent(/datum/component/forensics_state)
	return c?.was_bloodied

/proc/dq_set_was_bloodied(atom/a, v) // ALLOW(base_proc): global API written before the base-type ratchet
	var/datum/component/forensics_state/c = a.GetComponent(/datum/component/forensics_state)
	if(!c)
		c = a.AddComponent(/datum/component/forensics_state)
	c.was_bloodied = v

GLOBAL_LIST_EMPTY(_dq_blood_color_resolved)

/proc/dq_get_blood_color(atom/a) // ALLOW(base_proc): global API written before the base-type ratchet
	var/datum/component/forensics_state/c = a.GetComponent(/datum/component/forensics_state)
	if(c && c.blood_color != null)
		return c.blood_color
	return _dq_resolve_typed_default(a.type, GLOB.dq_blood_color_by_type, GLOB._dq_blood_color_resolved, null)

/proc/dq_set_blood_color(atom/a, color) // ALLOW(base_proc): global API written before the base-type ratchet
	var/datum/component/forensics_state/c = a.GetComponent(/datum/component/forensics_state)
	if(!c)
		c = a.AddComponent(/datum/component/forensics_state)
	c.blood_color = color

/proc/dq_get_forensic_data(atom/a) // ALLOW(base_proc): global API written before the base-type ratchet
	var/datum/component/forensics_state/c = a.GetComponent(/datum/component/forensics_state)
	return c?.forensic_data

/proc/dq_set_forensic_data(atom/a, datum/forensics_crime/fd) // ALLOW(base_proc): global API written before the base-type ratchet
	var/datum/component/forensics_state/c = a.GetComponent(/datum/component/forensics_state)
	if(!c)
		c = a.AddComponent(/datum/component/forensics_state)
	c.forensic_data = fd

/proc/dq_get_fluorescent(atom/a) // ALLOW(base_proc): global API written before the base-type ratchet
	var/datum/component/forensics_state/c = a.GetComponent(/datum/component/forensics_state)
	return c?.fluorescent

/proc/dq_set_fluorescent(atom/a, v) // ALLOW(base_proc): global API written before the base-type ratchet
	var/datum/component/forensics_state/c = a.GetComponent(/datum/component/forensics_state)
	if(!c)
		c = a.AddComponent(/datum/component/forensics_state)
	c.fluorescent = v
