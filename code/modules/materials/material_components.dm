// Behavior components attached to /datum/material instances.
//
// Three concrete components live here: luminescent, radioactive, toxic.
// Each carries a numeric magnitude and (when fully wired) hooks into
// signals to inject behavior — but the immediate role is to expose the
// magnitude in a uniform way that machine-part formulas and gameplay
// readers can query.
//
// Why components, not vars?
//   - These are the three properties that actually *do* something to the
//     world (emit light, irradiate, harm). The component layer is the
//     natural home for that behavior even though the behavior wiring is
//     deferred to follow-up work.
//   - Future traits ("Resonant", "Reactive", etc.) plug into this same
//     pattern: each is a /datum/component subtype attached to materials
//     that happen to roll it.
//   - Asking "does this material have property X?" becomes a presence
//     check (HasComponent) rather than a > 0 numeric compare.
//
// Static materials attach these in their `New()` proc. Dynamic
// round-rolled materials get them attached during the roll based on the
// material class and a chance roll (see /datum/material/dynamic).
//
// Static helper procs (dq_material_luminescence/radioactivity/toxicity)
// at the bottom of this file are the canonical read API — callers should
// prefer them over direct GetComponent calls for readability.

// --- Base component ----------------------------------------------------------

/datum/component/material_property
	/// Magnitude carried by this component instance. Set at AddComponent
	/// time via the first positional argument.
	var/magnitude = 0
	/// One per material. Re-attaching with the same type updates the
	/// magnitude; DCS dupe_mode COMPONENT_DUPE_UNIQUE enforces this.
	dupe_mode = COMPONENT_DUPE_UNIQUE

/datum/component/material_property/Initialize(_magnitude = 0)
	. = ..()
	magnitude = _magnitude

/datum/component/material_property/InheritComponent(datum/component/material_property/old, original)
	if(old)
		magnitude = old.magnitude


// --- Concrete behavior components -------------------------------------------

/// Glows. Items made from a material with this component get a passive
/// light overlay with brightness proportional to magnitude. (Behavior
/// wiring deferred — for now the component just carries the number.)
/datum/component/material_luminescent
	var/magnitude = 0
	dupe_mode = COMPONENT_DUPE_UNIQUE

/datum/component/material_luminescent/Initialize(_magnitude = 0)
	. = ..()
	magnitude = _magnitude

/datum/component/material_luminescent/InheritComponent(datum/component/material_luminescent/old, original)
	if(old)
		magnitude = old.magnitude


/// Emits ionising radiation. Walls / doors / weapons made from a
/// material carrying this component irradiate nearby mobs. Magnitude is
/// the per-tick irradiation strength on the legacy radioactivity scale.
/datum/component/material_radioactive
	var/magnitude = 0
	dupe_mode = COMPONENT_DUPE_UNIQUE

/datum/component/material_radioactive/Initialize(_magnitude = 0)
	. = ..()
	magnitude = _magnitude

/datum/component/material_radioactive/InheritComponent(datum/component/material_radioactive/old, original)
	if(old)
		magnitude = old.magnitude


/// Releases harmful particulates on contact. Magnitude is the per-hold
/// toxicity dose. (Behavior wiring deferred.)
/datum/component/material_toxic
	var/magnitude = 0
	dupe_mode = COMPONENT_DUPE_UNIQUE

/datum/component/material_toxic/Initialize(_magnitude = 0)
	. = ..()
	magnitude = _magnitude

/datum/component/material_toxic/InheritComponent(datum/component/material_toxic/old, original)
	if(old)
		magnitude = old.magnitude


// --- Read API ---------------------------------------------------------------
//
// Canonical helpers: return the magnitude of the named behavior
// component on a material, or 0 if not present. Callers in upstream
// readers (walls.dm, girders.dm, etc.) go through these so the
// component layout can change without rewriting every site.

/proc/dq_material_luminescence(datum/material/M)
	if(!M)
		return 0
	var/datum/component/material_luminescent/C = M.GetComponent(/datum/component/material_luminescent)
	return C ? C.magnitude : 0

/proc/dq_material_radioactivity(datum/material/M)
	if(!M)
		return 0
	var/datum/component/material_radioactive/C = M.GetComponent(/datum/component/material_radioactive)
	return C ? C.magnitude : 0

/proc/dq_material_toxicity(datum/material/M)
	if(!M)
		return 0
	var/datum/component/material_toxic/C = M.GetComponent(/datum/component/material_toxic)
	return C ? C.magnitude : 0
