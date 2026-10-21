// Material definition and procs follow.
/datum/material
	var/name	                          // Unique name for use in indexing the list.
	var/display_name                      // Prettier name for display.
	var/use_name
	var/flags = NONE                         // Various status modifiers.
	var/sheet_singular_name = "sheet"
	var/sheet_plural_name = "sheets"
	var/sheet_collective_name = "stack"
	var/is_fusion_fuel

	// Shards/tables/structures
	var/shard_type = SHARD_SHRAPNEL       // Path of debris object.
	var/shard_icon                        // Related to above.
	var/shard_can_repair = 1              // Can shards be turned into sheets with a welder?
	var/destruction_desc = "breaks apart" // Fancy string for barricades/tables/objects exploding.

	// Icons
	var/icon_colour                                      // Colour applied to products of this material.
	var/icon_base = "metal"                              // Wall base icon tag. See header.
	var/door_icon_base = "metal"                         // Door base icon tag. See header.
	var/table_icon_base = "metal"						 // Table base icon tag. See header.
	var/icon_reinf = "reinf_metal"                       // Overlay used
	var/pass_stack_colors = FALSE                        // Will stacks made from this material pass their colors onto objects?

	// Attributes
	var/cut_delay = 0            // Delay in ticks when cutting through this wall.
	// radioactivity / luminescence / toxicity are numeric vars further down (see the
	// material property block); read via dq_material_*() and applied by material_behaviors.dm.
	var/ignition_point           // K, point at which the material catches on fire.
	var/melting_point = 1800     // K, walls will take damage if they're next to a fire hotter than this
	// integrity moved into the property system below.
	var/protectiveness = 10      // How well this material works as armor.  Higher numbers are better, diminishing returns applies.
	var/opacity = 1              // Is the material transparent? 0.5< makes transparent walls/doors.
	var/reflectivity = 0         // How reflective to light is the material?  Currently used for laser reflection and defense.
	var/explosion_resistance = 5 // Only used by walls currently.
	var/negation = 0             // Objects that respect this will randomly absorb impacts with this var as the percent chance.
	var/spatial_instability = 0  // Objects that have trouble staying in the same physical space by sheer laws of nature have this. Percent for respecting items to cause teleportation.
	var/conductive = 1           // Objects without this var add NOCONDUCT to flags on spawn.
	// conductivity moved into the property system below.
	var/list/composite_material  // If set, object matter var will be a list containing these values.
	var/radiation_resistance = 0 // Radiation resistance, which is added on top of a material's density for blocking radiation. Needed to make lead special without superrobust weapons.
	var/supply_conversion_value  // Supply points per sheet that this material sells for.
	var/can_sharpen = TRUE // Is this material compatible with a sharpening kit?

	// material property system.
	//
	// The eleven property vars below are read-heavy numeric stats. Every
	// material can carry every stat (default 0). Static materials declare
	// what's gameplay-relevant; /datum/material/dynamic rolls all of them
	// from class-aware ranges at creation time. There are no implicit
	// upstream-style defaults — 0 means "this material does not
	// contribute to that axis."
	//
	// Behavior properties: plain numeric magnitudes. Read via
	// dq_material_luminescence/radioactivity/toxicity (material_behaviors.dm) and
	// applied to items by configure_material_behaviors(). 0 = inert on that axis.
	var/luminescence = 0   // passive light range driver (~0-80)
	var/radioactivity = 0  // per-tick irradiation strength
	var/toxicity = 0       // per-tick toxin dose to a bare holder
	// Mechanical
	var/hardness = 0
	var/density = 0                  // Was upstream `weight`.
	var/integrity = 0
	var/elasticity = 0
	var/brittleness = 0              // Debuff stat: high brittleness = parts can shatter.
	// Thermal
	var/heat_resistance = 0
	var/thermal_insulation = 0
	// Electrical / magnetic
	var/conductivity = 0
	var/magnetism = 0
	// Chemical
	var/reactivity = 0
	var/corrosion_resistance = 0
	// Constitutive properties consumed by the shared composite-material simulation.
	// Object geometry turns these intrinsic values into cable, pipe, vessel, and
	// structural ratings; do not store an object's final rating on the material.
	var/electrical_resistivity = 1
	var/specific_heat = 450
	var/yield_strength = 150
	var/fracture_toughness = 50
	var/dielectric_strength = 10
	var/critical_temperature = 0
	var/critical_current_density = 0
	var/phase_change_temperature = 0
	var/phase_change_capacity = 0
	var/catalytic_activity = 0
	/// Continuous physical response coefficients. These are constitutive values,
	/// not named powers: manufactured geometry decides which ones can operate.
	var/thermoelectric_coefficient = 0
	var/piezoelectric_coefficient = 0
	var/electrogenic_rate = 0
	var/shape_recovery_rate = 0
	var/shape_recovery_temperature = 0
	var/radiovoltaic_efficiency = 0
	var/scintillation_efficiency = 0
	/// Energy deposited by emitters or particle beams which a compatible cell can retain.
	var/field_energy_capacity = 0
	/// Fraction of an emitter/PA pulse captured instead of becoming waste heat.
	var/field_charge_efficiency = 0
	/// Passive heat released by an energized or fusion-stabilized material form.
	var/exothermic_heat_rate = 0
	/// Powered coefficient for moving heat through a deliberately constructed thermal assembly.
	var/heat_pump_coefficient = 0
	/// Temperature at which the material becomes an efficient thermal conductor.
	var/thermal_switch_temperature = 0
	var/thermal_switch_ratio = 1
	var/reactive_energy_capacity = 0
	var/antimicrobial_activity = 0
	var/hemostatic_activity = 0
	var/biocompatibility = 0
	var/gas_sorption_capacity = 0
	var/reagent_porosity = 0
	// Trait holder (component-driven behaviors attached at New() or roll
	// time live as full /datum/component children on this material).
	var/list/traits

	// Placeholder vars for the time being, todo properly integrate windows/light tiles/rods.
	var/created_window
	var/created_fulltile_window
	var/rod_product
	var/wire_product
	var/list/window_options

	// hardness/weight moved into the property system above.

	// Noise when someone is faceplanted onto a table made of this material.
	var/tableslam_noise = 'sound/weapons/tablehit1.ogg'
	// Noise made when a simple door made of this material opens or closes.
	var/dooropen_noise = SFX_EFFECTS_STONEDOOR_OPENCLOSE
	// Path to resulting stacktype.
	var/stack_type
	// Wallrot crumble message.
	var/rotting_touch_message = "crumbles under your touch"

	var/wiki_flag = 0

// Placeholders for light tiles and rglass.
/datum/material/proc/build_rod_product(mob/user, obj/item/stack/used_stack, obj/item/stack/target_stack)
	if(!rod_product)
		to_chat(user, span_warning("You cannot make anything out of \the [target_stack]"))
		return
	if(used_stack.get_amount() < 1 || target_stack.get_amount() < 1)
		to_chat(user, span_warning("You need one rod and one sheet of [display_name] to make anything useful."))
		return
	used_stack.use(1)
	target_stack.use(1)
	var/obj/item/stack/S = new rod_product(get_turf(user))
	S.add_fingerprint(user)
	S.add_to_stacks(user)

/datum/material/proc/build_wired_product(mob/living/user, obj/item/stack/used_stack, obj/item/stack/target_stack)
	if(!wire_product)
		to_chat(user, span_warning("You cannot make anything out of \the [target_stack]"))
		return
	if(used_stack.get_amount() < 5 || target_stack.get_amount() < 1)
		to_chat(user, span_warning("You need five wires and one sheet of [display_name] to make anything useful."))
		return

	used_stack.use(5)
	target_stack.use(1)
	to_chat(user, span_notice("You attach wire to the [name]."))
	var/obj/item/product = new wire_product(get_turf(user))
	user.put_in_hands(product)

// Make sure we have a display name and shard icon even if they aren't explicitly set.
/datum/material/New()
	..()
	// Backfill physical coefficients from the long-standing material data. New
	// materials may override any coefficient explicitly; ordinary materials still
	// gain distinct constitutive behavior without a parallel lookup table.
	if(electrical_resistivity == initial(electrical_resistivity))
		electrical_resistivity = 100 / max(conductivity, 0.1)
	if(yield_strength == initial(yield_strength))
		yield_strength = max(hardness * 5, integrity * 0.75, 25)
	if(fracture_toughness == initial(fracture_toughness))
		fracture_toughness = max(10, elasticity * 0.5 + integrity * 0.15 - brittleness * 0.2)
	if(dielectric_strength == initial(dielectric_strength) && !conductive)
		dielectric_strength = max(25, 110 - conductivity)
	if(!display_name)
		display_name = name
	if(!use_name)
		use_name = display_name
	if(!shard_icon)
		shard_icon = shard_type

// This is a placeholder for proper integration of windows/windoors into the system.
/datum/material/proc/build_windows(mob/living/user, obj/item/stack/used_stack)
	return 0

// Return the matter comprising this material.
/datum/material/proc/get_matter()
	var/list/temp_matter = list()
	if(islist(composite_material))
		for(var/material_string in composite_material)
			temp_matter[material_string] = composite_material[material_string]
	else
		temp_matter[name] = SHEET_MATERIAL_AMOUNT
	return temp_matter

// Snowflakey, only checked for alien doors at the moment.
/datum/material/proc/can_open_material_door(mob/living/user)
	return 1

// Structures made of a behaving material self-process to irradiate; items use the
// the material_emission behaviour instead (see material_behaviors.dm).
/datum/material/proc/products_need_process()
	return (radioactivity > 0) || (toxicity > 0)

// Used by walls when qdel()ing to avoid neighbor merging.
/datum/material/placeholder
	name = "placeholder"
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = 0

// Places a girder object when a wall is dismantled, also applies reinforced material.
/datum/material/proc/place_dismantled_girder(turf/target, datum/material/reinf_material, datum/material/girder_material)
	var/obj/structure/girder/G = new(target)
	if(reinf_material)
		G.reinf_material = reinf_material
		G.reinforce_girder()
	if(girder_material)
		G.set_material(girder_material)


// General wall debris product placement.
// Not particularly necessary aside from snowflakey cult girders.
/datum/material/proc/place_dismantled_product(turf/target, amount = 1) //Added an amount var to this. Lets multi-dropped walls to drop all of their sheets together. Woo!
	place_sheet(target, amount)

// Debris product. Used ALL THE TIME.
/datum/material/proc/place_sheet(turf/target, amount)
	amount = round(amount)
	if(stack_type && amount > 0)
		return new stack_type(target, amount)

// As above.
/datum/material/proc/place_shard(turf/target)
	if(shard_type)
		return new /obj/item/material/shard(target, src.name)

// Used by walls and weapons to determine if they break or not.
/datum/material/proc/is_brittle()
	return !!(flags & MATERIAL_BRITTLE)

/// effect_multiplier scales how hard the material degrades when it combusts; all callers
/// pass it (walls 0.7, doors 0.3, weapons 0.1) and the /phoron override reads it. The base
/// is inert for most materials, but the param must be declared so it isn't silently dropped.
/datum/material/proc/combustion_effect(turf/T, temperature, effect_multiplier)
	return

// Used by walls to do on-touch things, after checking for crumbling and open-ability.
/datum/material/proc/wall_touch_special(turf/simulated/wall/W, mob/living/L)
	return

/// The stack recipes usable with a sheet of this material (a list of /datum/xform recipes and /datum/xform_group sub-lists): the /transformation/stack rules
/// whose subject is this material's type or one above it. Built on first use and shared by every stack of the material; never write the returned list.
/datum/material/proc/get_recipes()
	return stack_material_recipes(src)

// The recipes every material may have (code/library/transformations/stack_recipes.dm): all of them, then the sturdy ones, the solid ones and the hard ones.
// If is_brittle() returns true, these are only good for a single strike.
/transformation/stack/base__baseball_bat
CAPABILITIES(/transformation/stack/base__baseball_bat)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/material/twohanded/baseballbat, 1)),
		chosen = chosen(title = "{display_name} baseball bat",
			subject = /datum/material,
			build_time = 20,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__staff
CAPABILITIES(/transformation/stack/base__staff)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/material/twohanded/staff, 1)),
		chosen = chosen(title = "{display_name} staff",
			subject = /datum/material,
			build_time = 20,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__ashtray
CAPABILITIES(/transformation/stack/base__ashtray)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/material/ashtray, 1)),
		chosen = chosen(title = "{display_name} ashtray",
			subject = /datum/material,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__spoon
CAPABILITIES(/transformation/stack/base__spoon)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/material/kitchen/utensil/spoon/plastic, 1)),
		chosen = chosen(title = "{display_name} spoon",
			subject = /datum/material,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__armor_plate
CAPABILITIES(/transformation/stack/base__armor_plate)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/material/armor_plating, 1)),
		chosen = chosen(title = "{display_name} armor plate",
			subject = /datum/material,
			build_time = 20,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__armor_plate_insert
CAPABILITIES(/transformation/stack/base__armor_plate_insert)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/material/armor_plating/insert, 1)),
		chosen = chosen(title = "{display_name} armor plate insert",
			subject = /datum/material,
			build_time = 40,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__grave_marker
CAPABILITIES(/transformation/stack/base__grave_marker)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/material/gravemarker, 1)),
		chosen = chosen(title = "{display_name} grave marker",
			subject = /datum/material,
			build_time = 50,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__ring
CAPABILITIES(/transformation/stack/base__ring)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/accessory/ring/material, 1)),
		chosen = chosen(title = "{display_name} ring",
			subject = /datum/material,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__bracelet
CAPABILITIES(/transformation/stack/base__bracelet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/clothing/accessory/bracelet/material, 1)),
		chosen = chosen(title = "{display_name} bracelet",
			subject = /datum/material,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__door
CAPABILITIES(/transformation/stack/base__door)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, sturdy),
		takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/structure/simple_door, 1)),
		chosen = chosen(title = "{display_name} door",
			subject = /datum/material,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__barricade
CAPABILITIES(/transformation/stack/base__barricade)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, sturdy),
		takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/barricade, 1)),
		chosen = chosen(title = "{display_name} barricade",
			subject = /datum/material,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__stool
CAPABILITIES(/transformation/stack/base__stool)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, sturdy),
		takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stool, 1)),
		chosen = chosen(title = "{display_name} stool",
			subject = /datum/material,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__chair
CAPABILITIES(/transformation/stack/base__chair)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, sturdy),
		takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair, 1)),
		chosen = chosen(title = "{display_name} chair",
			subject = /datum/material,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__bed
CAPABILITIES(/transformation/stack/base__bed)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, sturdy),
		takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed, 1)),
		chosen = chosen(title = "{display_name} bed",
			subject = /datum/material,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__double_bed
CAPABILITIES(/transformation/stack/base__double_bed)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, sturdy),
		takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/bed/double, 1)),
		chosen = chosen(title = "{display_name} double bed",
			subject = /datum/material,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__wall_girders_standard
CAPABILITIES(/transformation/stack/base__wall_girders_standard)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, sturdy),
		takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/girder, 1)),
		chosen = chosen(title = "{display_name} wall girders (standard)",
			subject = /datum/material,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__wall_girders_bay
CAPABILITIES(/transformation/stack/base__wall_girders_bay)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, sturdy),
		takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/girder/bay, 1)),
		chosen = chosen(title = "{display_name} wall girders (bay)",
			subject = /datum/material,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__wall_girders_eris
CAPABILITIES(/transformation/stack/base__wall_girders_eris)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, solid),
		takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/girder/eris, 1)),
		chosen = chosen(title = "{display_name} wall girders (eris)",
			subject = /datum/material,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__low_wall_bay_style
CAPABILITIES(/transformation/stack/base__low_wall_bay_style)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, solid),
		takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/low_wall/bay, 1)),
		chosen = chosen(title = "low wall (bay style)",
			subject = /datum/material,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			recycle = STACK_MATERIAL_SELF,
			group = "low walls")))

/transformation/stack/base__low_wall_eris_style
CAPABILITIES(/transformation/stack/base__low_wall_eris_style)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, solid),
		takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/low_wall/eris, 1)),
		chosen = chosen(title = "low wall (eris style)",
			subject = /datum/material,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			recycle = STACK_MATERIAL_SELF,
			group = "low walls")))

/transformation/stack/base__fork
CAPABILITIES(/transformation/stack/base__fork)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, hard),
		takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/material/kitchen/utensil/fork/plastic, 1)),
		chosen = chosen(title = "{display_name} fork",
			subject = /datum/material,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__knife
CAPABILITIES(/transformation/stack/base__knife)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, hard),
		takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/material/knife/plastic, 1)),
		chosen = chosen(title = "{display_name} knife",
			subject = /datum/material,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__blade
CAPABILITIES(/transformation/stack/base__blade)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, hard),
		takes = list(stack_term(STACK_SELF, 6)), makes = list(item_term(/obj/item/material/butterflyblade, 1)),
		chosen = chosen(title = "{display_name} blade",
			subject = /datum/material,
			build_time = 20,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/base__defense_wire
CAPABILITIES(/transformation/stack/base__defense_wire)
	configure(transformation(holds = TYPE_PROC_REF(/transformation/stack, hard),
		takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/material/barbedwire, 1)),
		chosen = chosen(title = "{display_name} defense wire",
			subject = /datum/material,
			build_time = 1 MINUTE,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/datum/material/proc/get_wall_texture()
	return


// === merged from _materials_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/stack/material/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(M.handle_eat_minerals(src, user))
		return ITEM_INTERACT_SUCCESS
	..()

/obj/item/stack/material/attack_generic(mob/living/user) //Allow adminbussed mobs to eat ore if they click it while NOT on help intent.
	if(user.handle_eat_minerals(src))
		return ITEM_INTERACT_SUCCESS
	..()

