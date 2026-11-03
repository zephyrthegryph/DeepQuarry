// Small per-type rules of an atom: the atom_rules() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(atom_rules(bubble_icon = ...))), read with atom_rules_of(A).bubble_icon, written at run time with set_<old var>().
//
//   bubble_icon   the speech bubble it uses
//   throwpass   thrown things pass it
//   emp_integrity_factor / emp_protection   how an EMP treats it
//   conflict_id   the element that excludes a second of its kind
//   light_system   which light system it uses
//   armor_spec   its innate armour: a params string of points per key (code/content/atom/armor.dm), read through get_armor()
//   integrity_failure   the integrity fraction at or below which it breaks (0: never; code/content/atom/atom_defense.dm)
//   uses_integrity   it has integrity (take_damage() and the break/destroy points, code/content/atom/atom_defense.dm)
//   simulated   the world acts on it (FALSE: an abstract marker, overlay or helper that moves, explosions, shuttles and the rest skip)

STATIC_ENTRY(atom_rules)

/proc/atom_rules(bubble_icon = null, throwpass = null, emp_integrity_factor = null, emp_protection = null, conflict_id = null, light_system = null, description_antag = null, description_fluff = null, price_tag = null, catalogue_data = null, simulated = null, armor_spec = null, integrity_failure = null, uses_integrity = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_ATOM_RULES, null, list("bubble_icon" = bubble_icon, "throwpass" = throwpass, "emp_integrity_factor" = emp_integrity_factor, "emp_protection" = emp_protection, "conflict_id" = conflict_id, "light_system" = light_system, "description_antag" = description_antag, "description_fluff" = description_fluff, "price_tag" = price_tag, "catalogue_data" = catalogue_data, "simulated" = simulated, "armor_spec" = armor_spec, "integrity_failure" = integrity_failure, "uses_integrity" = uses_integrity))

/datum/type_trait/atom_rules
	var/catalogue_data = null
	var/bubble_icon = "normal"
	var/throwpass = 0
	var/emp_integrity_factor = 0
	var/emp_protection = NONE
	var/conflict_id = null
	var/light_system = STATIC_LIGHT
	var/description_antag = null
	var/description_fluff = null
	var/price_tag = null
	var/simulated = TRUE
	var/armor_spec = null
	var/integrity_failure = 0
	var/uses_integrity = FALSE

/datum/type_trait/atom_rules/copy_values(datum/type_trait/atom_rules/into)
	into.catalogue_data = catalogue_data
	into.bubble_icon = bubble_icon
	into.throwpass = throwpass
	into.emp_integrity_factor = emp_integrity_factor
	into.emp_protection = emp_protection
	into.conflict_id = conflict_id
	into.light_system = light_system
	into.description_antag = description_antag
	into.description_fluff = description_fluff
	into.price_tag = price_tag
	into.simulated = simulated
	into.armor_spec = armor_spec
	into.integrity_failure = integrity_failure
	into.uses_integrity = uses_integrity

/datum/entry_engine/type_trait/atom_rules
	kind = ENTRY_ATOM_RULES
	trait_type = /datum/type_trait/atom_rules
	publish_key = ATOM_RULES_KEY
	base_type = /atom
	var_names = list("catalogue_data" = "catalogue_data", "bubble_icon" = "bubble_icon", "throwpass" = "throwpass", "emp_integrity_factor" = "emp_integrity_factor", "emp_protection_flags" = "emp_protection", "conflict_id" = "conflict_id", "light_system" = "light_system", "description_antag" = "description_antag", "description_fluff" = "description_fluff", "price_tag" = "price_tag", "simulated" = "simulated", "armor_spec" = "armor_spec", "integrity_failure" = "integrity_failure", "uses_integrity" = "uses_integrity")

/// The holder's atom_rules values (its own once one was set at run time). Read only.
READS_AS(/proc/atom_rules_of, ATOM_RULES_KEY)
/proc/atom_rules_of(atom/holder) as /datum/type_trait/atom_rules
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_ATOM_RULES)

/// What a type declares (no instance): the old initial().
/proc/atom_rules_of_type(type) as /datum/type_trait/atom_rules
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_ATOM_RULES)

/atom/proc/set_bubble_icon(value)
	return set_trait(src, ENTRY_ATOM_RULES, "bubble_icon", value)

/atom/proc/set_throwpass(value)
	return set_trait(src, ENTRY_ATOM_RULES, "throwpass", value)

/atom/proc/set_emp_integrity_factor(value)
	return set_trait(src, ENTRY_ATOM_RULES, "emp_integrity_factor", value)

/atom/proc/set_emp_protection_flags(value)
	return set_trait(src, ENTRY_ATOM_RULES, "emp_protection", value)

/atom/proc/set_conflict_id(value)
	return set_trait(src, ENTRY_ATOM_RULES, "conflict_id", value)

/atom/proc/set_light_system(value)
	return set_trait(src, ENTRY_ATOM_RULES, "light_system", value)

// Map variants of two computers that thrown things pass: the test map's former `throwpass = 1` var edits, now a type that declares it.
/obj/machinery/computer/ship/engines/throwpass

CAPABILITIES(/obj/machinery/computer/ship/engines/throwpass)
	configure(atom_rules(throwpass = 1))

/obj/machinery/computer/power_monitor/throwpass

CAPABILITIES(/obj/machinery/computer/power_monitor/throwpass)
	configure(atom_rules(throwpass = 1))

/atom/proc/set_description_antag(value)
	return set_trait(src, ENTRY_ATOM_RULES, "description_antag", value)

/atom/proc/set_description_fluff(value)
	return set_trait(src, ENTRY_ATOM_RULES, "description_fluff", value)

/atom/movable/proc/set_price_tag(value)
	return set_trait(src, ENTRY_ATOM_RULES, "price_tag", value)

/atom/proc/set_catalogue_data(value)
	return set_trait(src, ENTRY_ATOM_RULES, "catalogue_data", value)

/atom/proc/set_simulated(value)
	return set_trait(src, ENTRY_ATOM_RULES, "simulated", value)

// Abstract helpers with no block of their own elsewhere: the view dummy (code/host, which may not name atom_rules) and the skybox.
CAPABILITIES(/mob/dview)
	configure(atom_rules(simulated = FALSE))

CAPABILITIES(/atom/movable/screen/skybox)
	configure(atom_rules(simulated = FALSE))
