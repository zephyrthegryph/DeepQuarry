STATIC_ENTRY(micro_entry_policy)
/proc/micro_entry_policy(enterable = null, scale = null)
	return entry_make(ENTRY_MICRO_ENTRY_POLICY, null, list("enterable" = enterable, "scale" = scale))
/datum/type_trait/micro_entry_policy
	var/enterable = FALSE
	var/scale = 0.5
/datum/type_trait/micro_entry_policy/copy_values(datum/type_trait/micro_entry_policy/into)
	into.enterable = enterable
	into.scale = scale
/datum/entry_engine/type_trait/micro_entry_policy
	kind = ENTRY_MICRO_ENTRY_POLICY
	trait_type = /datum/type_trait/micro_entry_policy
	publish_key = MICRO_ENTRY_POLICY_KEY
	base_type = /obj
	var_names = list("micro_target" = "enterable", "micro_accepted_scale" = "scale")
READS_AS(/proc/micro_policy_of, MICRO_ENTRY_POLICY_KEY)
/proc/micro_policy_of(obj/holder) as /datum/type_trait/micro_entry_policy
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_MICRO_ENTRY_POLICY)
/proc/micro_policy_of_type(type) as /datum/type_trait/micro_entry_policy
	READS_FROM()
	return type_trait_of_type(type, ENTRY_MICRO_ENTRY_POLICY)
/obj/proc/set_micro_target(value)
	return set_trait(src, ENTRY_MICRO_ENTRY_POLICY, "enterable", value)
/obj/proc/set_micro_accepted_scale(value)
	return set_trait(src, ENTRY_MICRO_ENTRY_POLICY, "scale", value)

STATIC_ENTRY(object_fire_config)
/proc/object_fire_config(overlay = null, particles = null)
	return entry_make(ENTRY_OBJECT_FIRE_CONFIG, null, list("overlay" = overlay, "particles" = particles))
/datum/type_trait/object_fire_config
	var/overlay = null
	var/particles = null
/datum/type_trait/object_fire_config/copy_values(datum/type_trait/object_fire_config/into)
	into.overlay = overlay
	into.particles = particles
/datum/entry_engine/type_trait/object_fire_config
	kind = ENTRY_OBJECT_FIRE_CONFIG
	trait_type = /datum/type_trait/object_fire_config
	publish_key = OBJECT_FIRE_CONFIG_KEY
	base_type = /obj
	var_names = list("custom_fire_overlay" = "overlay", "burning_particles" = "particles")
READS_AS(/proc/object_fire_of, OBJECT_FIRE_CONFIG_KEY)
/proc/object_fire_of(obj/holder) as /datum/type_trait/object_fire_config
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_OBJECT_FIRE_CONFIG)
/proc/object_fire_of_type(type) as /datum/type_trait/object_fire_config
	READS_FROM()
	return type_trait_of_type(type, ENTRY_OBJECT_FIRE_CONFIG)
/obj/proc/set_custom_fire_overlay(value)
	return set_trait(src, ENTRY_OBJECT_FIRE_CONFIG, "overlay", value)
/obj/proc/set_burning_particles(value)
	return set_trait(src, ENTRY_OBJECT_FIRE_CONFIG, "particles", value)

