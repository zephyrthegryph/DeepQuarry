// Engine-declared interfaces for downstream presentation, construction and native delivery.

/// Establish the stateless framework interfaces at boot, after globals are available.
/// Getters remain safe for earlier callers and retain any provider they already created.
/proc/engine_prepare_interfaces()
	materialization_host()
	native_watch_provider()
	construction_stage_provider()
	transfer_feedback_provider()
	time_scheduler_factory()
	operation_compatibility()
	transfer_outputs()
	input_compatibility()
	state_reference_environment()
	containment_slot_factory()
	state_construction()
	state_registry_adapter()
	requirement_composer()
	property_environment()

/datum/proc/scheduler_presentation_mask()
	return 0

/datum/proc/scheduler_queue_presentation()
	return

/datum/proc/scheduler_evaluate_periodic()
	return

/datum/time_scheduler/proc/drain_presentation()
	return TRUE

/datum/definition_registry/proc/periodic_mask_for(path)
	return 0

/datum/native_watch/proc/bind_native()
	return 0

/datum/native_watch/proc/unbind_native(handle)
	return

/datum/native_watch_provider

GLOBAL_DATUM(native_watch_provider, /datum/native_watch_provider)

/proc/native_watch_provider()
	RETURN_TYPE(/datum/native_watch_provider)
	if(!GLOB.native_watch_provider)
		GLOB.native_watch_provider = new /datum/native_watch_provider
	return GLOB.native_watch_provider

/datum/native_watch_provider/proc/lookup(handle)
	return null

/atom/movable/proc/place_starting_occupant(atom/holder)
	return FALSE

/datum/construction_stage_provider

GLOBAL_DATUM(construction_stage_provider, /datum/construction_stage_provider)

/proc/construction_stage_provider()
	RETURN_TYPE(/datum/construction_stage_provider)
	if(!GLOB.construction_stage_provider)
		GLOB.construction_stage_provider = new /datum/construction_stage_provider
	return GLOB.construction_stage_provider

/datum/construction_stage_provider/proc/build_legacy(list/options)
	return null

/datum/transfer_feedback_provider

GLOBAL_DATUM(transfer_feedback_provider, /datum/transfer_feedback_provider)

/proc/transfer_feedback_provider()
	RETURN_TYPE(/datum/transfer_feedback_provider)
	if(!GLOB.transfer_feedback_provider)
		GLOB.transfer_feedback_provider = new /datum/transfer_feedback_provider
	return GLOB.transfer_feedback_provider

/datum/transfer_feedback_provider/proc/send(mob/actor, datum/holder, datum/item, reason, raw = FALSE)
	return
