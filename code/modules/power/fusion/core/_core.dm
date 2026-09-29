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

/obj/machinery/power/fusion_core/mapped
	anchored = TRUE

REGISTRY_MEMBERSHIP(/obj/machinery/power/fusion_core, REGISTRY_FUSION_CORES)

DECLARE_REAGENTS(/obj/machinery/power/fusion_core, 10000, null)

/// Its running field (Startup()/Shutdown()); the core ticks it while it has one.
OM_FIELD_VIEW(/obj/machinery/power/fusion_core, obj/effect/fusion_em_field, owned_field, CHANGE_MACHINE_SETTINGS)
DECLARE_PERIODIC_WHILE(/obj/machinery/power/fusion_core, MACHINE_PIPELINE, "owned_field")

/obj/machinery/power/fusion_core/Initialize(mapload)
	. = ..()

	add_hose_connector(/datum/hose_connector/output)


	default_apply_parts()

OWN(/obj/machinery/power/fusion_core, material_sample, OWN_SPILL)

/obj/machinery/power/fusion_core/proc/check_core_status()
	if(has_stat(BROKEN))
		return
	if(idle_power_usage > avail())
		return
	. = 1

/// Runs its field while it has one; shut down, it sleeps until Startup(). The field is owned: when
/// it is destroyed the ownership framework clears owned_field and raises its channel, so the
/// declaration stops the work with no guard here.
/obj/machinery/power/fusion_core/machine_step()
	if((has_stat(BROKEN)) || !power_region)
		Shutdown() // clears owned_field through own_clear(): the declaration stops the work
		return

	OM_EMIT(src, /datum/om/event/hose_forcepump)

	set_strength(target_field_strength)
	process_material_sample()

	if(!QDELETED(owned_field))
		om_after(owned_field, 1, TYPE_PROC_REF(/obj/effect/fusion_em_field, core_tick))

TOPIC_ACTION(/obj/machinery/power/fusion_core, "str", PROC_REF(topic_str), TOPIC_NUM("str"))

/obj/machinery/power/fusion_core/proc/topic_str(mob/user, list/args)
	var/dif = args["str"]
	if(!isnum(dif))
		return
	field_strength = min(max(field_strength + dif, MIN_FIELD_STR), MAX_FIELD_STR)
	update_active_power_usage(500 * field_strength)
	if(owned_field)
		owned_field.ChangeFieldStrength(field_strength)
	return TRUE

/obj/machinery/power/fusion_core/proc/Startup()
	if(owned_field)
		return
	own_set(src, "owned_field", new /obj/effect/fusion_em_field(loc, src))
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
		own_clear(src, "owned_field", OWN_DELETE)
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

/obj/machinery/power/fusion_core/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/fusion_core_material_insert,
		/datum/interaction/machine_item/fusion_core_part_replacement,
		/datum/interaction/machine_item/fusion_core_set_ident,
		/datum/interaction/machine_hand/ungated/fusion_core_use,
	)
	..()

/// Whether the fusion field is off (the material cradle and internals can be reached).
/obj/machinery/power/fusion_core/proc/fusion_field_off(mob/actor, atom/target, obj/item/held)
	return !owned_field

/// Old attackby: load a processed alloy stack into the material cradle.
/datum/interaction/machine_item/fusion_core_material_insert
	id = "fusion_core_material_insert"
	name = "Load material cradle"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item/stack/material/processed_alloy
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/power/fusion_core/proc/fusion_field_off, "the fusion field must be shut down before opening the material cradle"))
	effect = /obj/machinery/power/fusion_core/proc/interaction_material_insert
	also_requires = list(REQ_FIELD_NOT("material_sample", "the material cradle is already occupied"))

/obj/machinery/power/fusion_core/proc/interaction_material_insert(mob/user, obj/item/stack/material/processed_alloy/stock, datum/interaction/interaction)
	user.drop_from_inventory(stock)
	stock.forceMove(src)
	own_set(src, "material_sample", stock)
	act_message(user, src, others = span_notice("%U% secures [stock] in %T%'s shielded treatment cradle."))
	return TRUE

/// Old attackby: `if(default_part_replacement(user, W)) return`, gated on the fusion field being off.
/datum/interaction/machine_item/fusion_core_part_replacement
	id = "fusion_core_part_replacement"
	name = "Replace parts"
	category = INTERACTION_CAT_MAINTAIN
	held_type = /obj/item/storage/part_replacer
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/power/fusion_core/proc/fusion_field_off, "the fusion field must be shut down before opening the material cradle"))
	effect = /obj/machinery/proc/interaction_part_replacement

/// Old attackby: a multitool sets the ident tag.
/datum/interaction/machine_item/fusion_core_set_ident
	id = "fusion_core_set_ident"
	name = "Set ident tag"
	category = INTERACTION_CAT_CONFIGURE
	tool = TOOL_MULTITOOL
	tool_volume = 0
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/power/fusion_core/proc/fusion_field_off, "the fusion field must be shut down before opening the material cradle"))
	effect = /obj/machinery/power/fusion_core/proc/interaction_set_ident

/obj/machinery/power/fusion_core/proc/interaction_set_ident(mob/user, obj/item/held, datum/interaction/interaction)
	var/new_ident = rerun_ask(user, "k186", PROC_REF(interaction_set_ident), args, /datum/om/prompt/text, message = "Enter a new ident tag.", title = "Fusion Core", default = id_tag, max_length = MAX_NAME_LEN)
	if(isnull(new_ident))
		return
	if(new_ident && user.Adjacent(src))
		id_tag = new_ident
	return TRUE

/// Old attack_hand, which never called ..(): no gate. `Adjacent` is now REQ_INTERACTION_REACH.
/datum/interaction/machine_hand/ungated/fusion_core_use
	id = "fusion_core_use"
	name = "Use"
	effect = /obj/machinery/power/fusion_core/proc/interaction_use

/obj/machinery/power/fusion_core/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(owned_field)
		act_message(user, src, others = span_notice("%U% initiates an emergency shutdown of %T%'s fusion field."))
		Shutdown()
	else if(material_sample)
		var/obj/item/stack/material/processed_alloy/finished_sample = material_sample
		own_take(src, "material_sample")
		finished_sample.forceMove(user.drop_location())
		user.put_in_hands(finished_sample)
		act_message(user, src, others = span_notice("%U% releases [finished_sample] from %T%'s material cradle."))
	else
		to_chat(user, span_notice("The fusion field is off and the material cradle is empty."))
	return TRUE

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
	batch.add_thermal_energy(max(100, owned_field.plasma_temperature * batch.amount * 0.04))
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
	own_set(src, "material_sample", replacement)
	if(material_sample)
		material_sample.forceMove(src)
	if(round(old_fusion_strength / 25) != round((LAZYACCESS(batch.field_treatments, MATERIAL_FIELD_FUSION) || 0) / 25))
		visible_message(span_notice("Colored bands crawl across [src]'s sample cradle as the fusion field changes the stock's lattice."))
	qdel(batch)

/obj/machinery/power/fusion_core/proc/jumpstart(field_temperature)
	field_strength = 501 // Generally a good size.
	Startup()
	if(!owned_field)
		return FALSE
	owned_field.plasma_temperature = field_temperature
	return TRUE

/// The field's share of a core process tick, a tick after the core's own.
/obj/effect/fusion_em_field/proc/core_tick()
	periodic_step()
	stability_monitor()
	radiation_scale()
	temp_dump()
	temp_color()

