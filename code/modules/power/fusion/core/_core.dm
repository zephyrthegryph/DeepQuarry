/*
	TODO README
*/

#define MAX_FIELD_STR 1000
#define MIN_FIELD_STR 1

/obj/machinery/power/fusion_core
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	name = "\improper R-UST Mk. 9 Tokamak core"
	desc = "An enormous solenoid for generating extremely high power electromagnetic fields. It includes a kinetic energy harvester."
	icon = 'icons/obj/machines/power/fusion.dmi'
	icon_state = "core0"
	density = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 50
	active_power_usage = 500 //multiplied by field strength
	anchored = FALSE

	circuit = /obj/item/circuitboard/fusion_core

	var/field_strength = 1//0.01
	var/target_field_strength = 1
	var/id_tag

	var/reactant_dump = FALSE	// Does the tokomak actively try to syphon materials?
	/// Ordinary processed stock held in the core's shielded material-treatment cradle.
	var/obj/item/stack/material/processed_alloy/material_sample
	var/next_material_treatment = 0
	/// Its running field (Startup()/Shutdown()); the core steps it while it has one.
	var/obj/effect/fusion_em_field/owned_field

/obj/machinery/power/fusion_core/mapped
	anchored = TRUE


MSG_DEF_SELF(fusion_core/field_on, "The fusion field must be shut down before opening the material cradle.")
MSG_DEF_SELF(fusion_core/cradle_full, "The material cradle is already occupied.")
MSG_DEF(fusion_core/sample_loaded, "You secure %I% in %T%'s shielded treatment cradle.", "%U% secures %I% in %T%'s shielded treatment cradle.")

// The R-UST core (doc/rewrite/final_api.html section 16): it raises an electromagnetic field (Startup()) and, while it has one, runs it every
// machine service interval (core_step(): the field's strength, the material cradle, then the field's own reaction a decisecond later,
// core_tick()). The field, the material sample in its cradle and its ident are its own; with the field down the cradle opens, a part
// replacer works and a multitool sets its ident.
TRACKED(/obj/machinery/power/fusion_core, id_tag)

CAPABILITIES(/obj/machinery/power/fusion_core)
	reagents(10000)
	registry(REGISTRY_FUSION_CORES, key = nameof(id_tag))
	owns_one(nameof(owned_field), /obj/effect/fusion_em_field)
	owns_one(nameof(material_sample), /obj/item/stack/material/processed_alloy, on_destroy = ON_DESTROY_SPILL)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(core_step)), when = nameof(owned_field))
	part_replacement()
	extend("part_replacement.replace", needs(req_empty(nameof(owned_field), because = MSG(fusion_core/field_on))))
	op("load_cradle", item(/obj/item/stack/material/processed_alloy), label("Load material cradle"), wait(0),
		needs(req_empty(nameof(owned_field), because = MSG(fusion_core/field_on)), req_empty(nameof(material_sample), because = MSG(fusion_core/cradle_full))),
		put_in(nameof(material_sample)), says(MSG(fusion_core/sample_loaded)))
	op("set_ident", tool(TOOL_MULTITOOL), label("Set ident tag"), wait(0), needs(req_empty(nameof(owned_field), because = MSG(fusion_core/field_on))),
		asks(/datum/prompt/text, fields = list("title" = "Fusion Core", "question" = "Enter a new ident tag.", "default" = nameof(id_tag), "max_len" = MAX_NAME_LEN)),
		then(PROC_REF(ident_entered)))
	op("use", hand(), when(req_empty_hand()), label("Use"), ungated(), wait(0), then(PROC_REF(used)))

/obj/machinery/power/fusion_core/Initialize(mapload)
	. = ..()
	add_hose_connector(/datum/hose_connector/output)
	default_apply_parts()

/obj/machinery/power/fusion_core/proc/check_core_status()
	if(has_stat(BROKEN))
		return
	if(idle_power_usage > avail())
		return
	. = 1

/// Runs its field while it has one (its every(), gated on owned_field): broken or cut off it shuts the field down.
/obj/machinery/power/fusion_core/proc/core_step(datum/act/timer/A)
	if((has_stat(BROKEN)) || !power_region)
		Shutdown() // clears owned_field through own_clear(): the declaration stops the work
		return

	PUBLISH_LEGACY(src, /datum/notice/hose_forcepump)

	set_strength(target_field_strength)
	process_material_sample()

	if(!QDELETED(owned_field))
		after(owned_field, 0.1 SECONDS, TYPE_PROC_REF(/obj/effect/fusion_em_field, core_tick))

/obj/machinery/power/fusion_core/proc/Startup()
	if(owned_field)
		return
	rel_set(src, nameof(owned_field), new /obj/effect/fusion_em_field(loc, src))
	owned_field.ChangeFieldStrength(field_strength)
	icon_state = "core1"
	set_use_power(USE_POWER_ACTIVE)
	. = 1

/obj/machinery/power/fusion_core/proc/Shutdown(force_rupture)
	if(owned_field)
		icon_state = "core0"
		if(force_rupture || owned_field.plasma_temperature > 1000)
			owned_field.MRC()
		else
			owned_field.RadiateAll()
		destroyed(rel_take(src, nameof(owned_field)), src)
	set_use_power(USE_POWER_IDLE)

/obj/machinery/power/fusion_core/proc/AddParticles(name, quantity = 1)
	if(owned_field)
		owned_field.AddParticles(name, quantity)
		. = 1

/obj/machinery/power/fusion_core/bullet_act(obj/item/projectile/Proj)
	if(owned_field)
		return owned_field.bullet_act(Proj)
	return ..()

/obj/machinery/power/fusion_core/proc/set_strength(value)
	value = CLAMP(value, MIN_FIELD_STR, MAX_FIELD_STR)

	if(field_strength != value)
		field_strength = value
		update_active_power_usage(5 * value)
		if(owned_field)
			owned_field.ChangeFieldStrength(value)

/obj/machinery/power/fusion_core/proc/ident_entered(datum/act/op/A)
	var/datum/prompt/text/answer = A.answer
	if(answer?.value && A.actor?.Adjacent(src))
		set_id_tag(answer.value)
	return OP_OK

/// A hand on the core: an emergency shutdown of a running field, else the sample comes out of the cradle.
/obj/machinery/power/fusion_core/proc/used(datum/act/op/A)
	var/mob/user = A.actor
	if(owned_field)
		act_message(user, src, others = span_notice("%U% initiates an emergency shutdown of %T%'s fusion field."))
		Shutdown()
	else if(material_sample)
		var/obj/item/stack/material/processed_alloy/finished_sample = rel_take(src, nameof(material_sample))
		finished_sample.forceMove(user.drop_location())
		user.put_in_hands(finished_sample)
		act_message(user, src, others = span_notice("%U% releases [finished_sample] from %T%'s material cradle."))
	else
		to_chat(user, span_notice("The fusion field is off and the material cradle is empty."))
	return OP_OK

/obj/machinery/power/fusion_core/examine(mob/user)
	. = ..()
	if(material_sample)
		. += span_notice("The cradle contains [material_sample].")
		if(owned_field)
			. += span_warning("Shut down the fusion field before removing it.")
		else
			. += span_notice("Click the core to remove it.")
	else if(!owned_field)
		. += span_notice("The material cradle is empty. Apply alloy stock to load it.")

/obj/machinery/power/fusion_core/proc/process_material_sample()
	if(!material_sample || QDELETED(material_sample) || !owned_field || !COOLDOWN_FINISHED(src, next_material_treatment))
		return
	COOLDOWN_START(src, next_material_treatment, 5 SECONDS)
	var/datum/material_batch/batch = material_sample.physical_batch()?.copy_batch()
	if(!batch)
		return
	var/field_work = clamp(round(field_strength / 25 + owned_field.plasma_temperature / 2500), 2, 30)
	var/old_fusion_strength = LAZYACCESS(batch.field_treatments, MATERIAL_FIELD_FUSION) || 0
	batch.add_field_treatment(MATERIAL_FIELD_FUSION, field_work)
	batch.homogeneity = clamp(batch.homogeneity + round(field_work / 6), 0, 100)
	batch.add_batch_heat(max(100, owned_field.plasma_temperature * batch.amount * 0.04), HEAT_SOURCE_DEVICE)
	batch.record_electricity(active_power_usage * 5)
	var/phoron_key
	var/hydrogen_key
	for(var/reactant in owned_field.dormant_reactant_quantities)
		var/reactant_name = lowertext("[reactant]")
		if(!phoron_key && (findtext(reactant_name, "plasma") || findtext(reactant_name, "phoron")))
			phoron_key = reactant
		if(!hydrogen_key && findtext(reactant_name, "hydrogen"))
			hydrogen_key = reactant
	var/phoron = phoron_key ? (owned_field.dormant_reactant_quantities[phoron_key] || 0) : 0
	var/hydrogen = hydrogen_key ? (owned_field.dormant_reactant_quantities[hydrogen_key] || 0) : 0
	if(phoron > 5)
		batch.add_dissolved_gas("fusion phoron", min(phoron / 50, field_work))
		owned_field.dormant_reactant_quantities[phoron_key] = max(0, phoron - 5)
	if(hydrogen > 5)
		batch.add_dissolved_gas("fusion hydrogen", min(hydrogen / 50, field_work))
		owned_field.dormant_reactant_quantities[hydrogen_key] = max(0, hydrogen - 5)
	var/obj/item/stack/material/processed_alloy/replacement = replace_processed_stack(material_sample, batch, src)
	rel_set(src, nameof(material_sample), replacement)
	if(material_sample)
		material_sample.forceMove(src)
	if(round(old_fusion_strength / 25) != round((LAZYACCESS(batch.field_treatments, MATERIAL_FIELD_FUSION) || 0) / 25))
		visible_message(span_notice("Colored bands crawl across [src]'s sample cradle as the fusion field changes the stock's lattice."))
	spent(batch)

/obj/machinery/power/fusion_core/proc/jumpstart(field_temperature)
	field_strength = 501 // Generally a good size.
	Startup()
	if(!owned_field)
		return FALSE
	owned_field.plasma_temperature = field_temperature
	return TRUE

/// The field's share of a core step, a decisecond after the core's own.
/obj/effect/fusion_em_field/proc/core_tick()
	field_react()
	stability_monitor()
	radiation_scale()
	temp_dump()
	temp_color()

