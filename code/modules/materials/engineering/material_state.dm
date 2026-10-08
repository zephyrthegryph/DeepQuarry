// Per-object engineered-material records.
//
// What is per-instance about a manufactured object is kept in two plain datums in its cap_data
// (code/datums/capabilities/capabilities.dm), made on the first write, so an /obj spends no base-type var
// on it (tools/ci/base_vars_lint.py: a feature's state belongs to the module that owns it):
//
//   /datum/material_assembly  the operating state of a physical assembly: its exposure service, wear
//                             (liner, exterior, fatigue, a leak), diagnostics identity and the
//                             "fabricated or reconfigured" flag.
//   /datum/material_build     the build record: per-role material overrides, an arbitrary mix, and what
//                             applying the blueprint's effects worked out (engineered id and profile, surgery
//                             and tool bonuses, effective density, gun deltas) with the item's response.
//
// Read through material_assembly_view() / material_build_view(): an object that has no record answers the
// shared pristine one (every field at its default), so a read never allocates. Write through
// material_assembly() / material_build(), which make the record. The blueprint itself (material_template,
// material_total, material_bulk_material) stays a type var on /obj: roughly 460 type bodies declare it
// (MATERIAL_BULK(), material_template =) and designs and recipes read it with initial() on a type path.
//
// A record is not a saved var, so an /obj carries the saved part of it beside its delta
// (state_extra()/state_apply_extra(), code/datums/state/schema.dm): latent collapse, entity_clone() and the
// stock ledger keep an object's overrides, mix, wear and engineered effects. A live service or response is
// wiring and pins its holder materialised (state_refusal()).

/// The operating state of one physical assembly (an /obj in the material service's care).
/datum/material_assembly
	/// The thermal and exposure simulation this assembly runs (owned; made by material_service_event()).
	var/datum/material_service/service
	/// Bumped by material_service_changed(); diagnostics restart an observation when it moves.
	var/configuration_revision = 0
	/// "ME-n": the diagnostics identity, given when the service first starts.
	var/assembly_id
	/// TRUE for player-fabricated or deliberately reconfigured assemblies. Map defaults remain inspectable
	/// without enrolling every machine in exposure.
	var/custom = FALSE
	/// The event that last admitted or woke the service.
	var/last_event
	/// Percent of the wetted liner that is left (0 = perforated).
	var/liner_integrity = 100
	/// Percent of the exterior surface that is left (0 = eaten through).
	var/exterior_integrity = 100
	/// Accumulated differential-pressure fatigue, percent (100 = the assembly yields).
	var/fatigue = 0
	/// TRUE while the pressure boundary is breached and gas moves through it.
	var/leaking = FALSE
	/// world.time of the last process_material_environment_now() sample.
	var/last_process = 0

CAPABILITIES(/datum/material_assembly)
	owns_one(nameof(service), /datum/material_service)

/// The part of the record that survives serialization, as name = value for what is not the default.
/datum/material_assembly/proc/saved()
	. = list()
	if(configuration_revision)
		.["revision"] = configuration_revision
	if(assembly_id)
		.["id"] = assembly_id
	if(custom)
		.["custom"] = TRUE
	if(liner_integrity != 100)
		.["liner"] = liner_integrity
	if(exterior_integrity != 100)
		.["exterior"] = exterior_integrity
	if(fatigue)
		.["fatigue"] = fatigue
	if(leaking)
		.["leaking"] = TRUE

/// Writes saved() back; a null `saved` puts the saved fields at their defaults. The live service stays.
/datum/material_assembly/proc/restore(list/saved)
	configuration_revision = saved?["revision"] || 0
	assembly_id = saved?["id"]
	custom = !!saved?["custom"]
	liner_integrity = isnull(saved?["liner"]) ? 100 : saved["liner"]
	exterior_integrity = isnull(saved?["exterior"]) ? 100 : saved["exterior"]
	fatigue = saved?["fatigue"] || 0
	leaking = !!saved?["leaking"]

/// The build record of one manufactured object.
/datum/material_build
	/// Role -> material id for the roles that differ from the blueprint default. Null for an unmodified
	/// object. Interned and shared (material_overrides_intern()): write through set_construction_material(),
	/// never in place.
	var/list/overrides
	/// Material id -> units for an object whose mix is arbitrary. Null for everything else, whose composition
	/// is its blueprint. Private to this instance.
	var/list/mix
	/// MAT_* name of the material the item was engineered from, and the application profile that did it.
	var/engineered_id
	var/profile
	var/surgery_cleanliness_bonus = 0
	var/tool_quality_bonus = 0
	/// Effective physical values consumed by integrity, throwing, power and examination.
	var/effective_density = 0
	var/effective_electrical_resistance = 0
	var/accuracy_delta = 0
	var/recoil_delta = 0
	/// The physical-response state of an item made of an engineered material (owned; hooks its events).
	var/datum/material_response/response

CAPABILITIES(/datum/material_build)
	owns_one(nameof(response), /datum/material_response)

/// The part of the record that survives serialization, as name = value for what is not the default.
/// (The response is live wiring: it pins the holder instead, state_refusal().)
/datum/material_build/proc/saved()
	. = list()
	if(length(overrides))
		.["overrides"] = overrides
	if(length(mix))
		.["mix"] = mix
	if(engineered_id)
		.["id"] = engineered_id
	if(profile)
		.["profile"] = profile
	if(surgery_cleanliness_bonus)
		.["cleanliness"] = surgery_cleanliness_bonus
	if(tool_quality_bonus)
		.["quality"] = tool_quality_bonus
	if(effective_density)
		.["density"] = effective_density
	if(effective_electrical_resistance)
		.["resistance"] = effective_electrical_resistance
	if(accuracy_delta)
		.["accuracy"] = accuracy_delta
	if(recoil_delta)
		.["recoil"] = recoil_delta

/// Writes saved() back; a null `saved` puts the saved fields at their defaults. The live response stays.
/datum/material_build/proc/restore(list/saved)
	var/list/restored_overrides = saved?["overrides"]
	overrides = length(restored_overrides) ? material_overrides_intern(restored_overrides) : null
	var/list/restored_mix = saved?["mix"]
	mix = length(restored_mix) ? restored_mix.Copy() : null
	engineered_id = saved?["id"]
	profile = saved?["profile"]
	surgery_cleanliness_bonus = saved?["cleanliness"] || 0
	tool_quality_bonus = saved?["quality"] || 0
	effective_density = saved?["density"] || 0
	effective_electrical_resistance = saved?["resistance"] || 0
	accuracy_delta = saved?["accuracy"] || 0
	recoil_delta = saved?["recoil"] || 0

/// O's assembly record, or null when it has none.
/proc/material_assembly_of(obj/O)
	RETURN_TYPE(/datum/material_assembly)
	return capability_data(O)?[/datum/material_assembly]

/// O's assembly record to read: the shared pristine record when it has none (never write through it).
/proc/material_assembly_view(obj/O)
	RETURN_TYPE(/datum/material_assembly)
	var/static/datum/material_assembly/pristine = new
	return capability_data(O)?[/datum/material_assembly] || pristine

/// O's assembly record, made when it has none: the one way to write assembly state.
/proc/material_assembly(obj/O)
	RETURN_TYPE(/datum/material_assembly)
	var/datum/material_assembly/assembly = capability_data(O)?[/datum/material_assembly]
	if(!assembly)
		assembly = new
		LAZYSET(capability_runtime(O).data, /datum/material_assembly, assembly)
	return assembly

/// O's material service, or null when it has not been admitted to continuous exposure.
/proc/material_service_of(obj/O)
	RETURN_TYPE(/datum/material_service)
	var/datum/material_assembly/assembly = capability_data(O)?[/datum/material_assembly]
	return assembly?.service

/// O's build record, or null when it has none.
/proc/material_build_of(obj/O)
	RETURN_TYPE(/datum/material_build)
	return capability_data(O)?[/datum/material_build]

/// O's build record to read: the shared pristine record when it has none (never write through it).
/proc/material_build_view(obj/O)
	READS_FROM() // an item's build record is asked when it is used, never cached
	RETURN_TYPE(/datum/material_build)
	var/static/datum/material_build/pristine = new
	return capability_data(O)?[/datum/material_build] || pristine

/// O's build record, made when it has none: the one way to write build state.
/proc/material_build(obj/O)
	RETURN_TYPE(/datum/material_build)
	var/datum/material_build/build = capability_data(O)?[/datum/material_build]
	if(!build)
		build = new
		LAZYSET(capability_runtime(O).data, /datum/material_build, build)
	return build

/// Deletes O's material records in the destroy transaction's links step (/obj/on_destroy), while the object's links
/// still read: the service and the response are owned children that tear down against a live owner, as they did
/// when the object owned them. caps_destroy() deletes whatever is left in cap_data afterwards.
/proc/material_records_teardown(obj/O)
	if(!capability_data(O))
		return
	for(var/key in list(/datum/material_assembly, /datum/material_build))
		var/datum/record = capability_data(O)?[key]
		if(!record)
			continue
		LAZYREMOVE(capability_runtime(O).data, key)
		spent(record)

/// The material an item was engineered from (the /obj/item compatibility field), or null.
/proc/material_engineered_id(obj/item/I)
	READS_FROM() // an item's build record is asked when it is used, never cached
	return material_build_view(I).engineered_id

/// Sets it. An item with no build record keeps none for a null id.
/proc/material_engineered_id_set(obj/item/I, id)
	if(id || material_build_of(I))
		material_build(I).engineered_id = id

// ---- serialization ----

/obj/state_extra()
	. = ..()
	var/datum/material_assembly/assembly = material_assembly_of(src)
	var/datum/material_build/build = material_build_of(src)
	if(!assembly && !build)
		return
	var/list/saved_assembly = assembly?.saved()
	var/list/saved_build = build?.saved()
	if(!length(saved_assembly) && !length(saved_build))
		return
	. = . || list()
	if(length(saved_assembly))
		.["material_assembly"] = saved_assembly
	if(length(saved_build))
		.["material_build"] = saved_build

/obj/state_apply_extra(list/extra)
	..()
	var/list/saved_assembly = extra?["material_assembly"]
	var/list/saved_build = extra?["material_build"]
	var/datum/material_assembly/assembly = length(saved_assembly) ? material_assembly(src) : material_assembly_of(src)
	assembly?.restore(saved_assembly)
	var/datum/material_build/build = length(saved_build) ? material_build(src) : material_build_of(src)
	build?.restore(saved_build)

/// A live service (exposure watches and a deadline) or response (event hooks) cannot be rebuilt from a blob:
/// the holder stays materialised, as a pinned owned child does (/datum/state_codec/pinned).
/obj/state_refusal()
	. = ..()
	if(.)
		return
	if(material_service_of(src))
		return "has a live material service, which pins it materialised"
	if(material_build_of(src)?.response)
		return "has a material response with live hooks, which pins it materialised"
