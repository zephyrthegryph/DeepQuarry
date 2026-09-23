// Material templates: the per-type blueprint of what an object is made of.
//
// A template is a singleton describing functional roles (a cell's conductor, a
// tool's grip...). Each role has a fraction of the object's total material, a
// default material, a label, a description and an optional flag. An object's
// composition is its template plus a total amount, both declared on its type:
//     material_template = /datum/material_template/cell
//     material_total = 2 * SHEET_MATERIAL_AMOUNT
// Instances store only the roles whose material differs (material_overrides).
// Amounts are derived on demand: fraction x total, with the last role taking the
// remainder so every blueprint conserves its total exactly.
//
// Plain objects made of one material use the single-role bulk template:
//     MATERIAL_BULK(MAT_STEEL, 500)
// Objects made of a fixed mix of several use a per-type mix template:
//     MATERIAL_MIX(list(MAT_STEEL = 500, MAT_GLASS = 250))

/// One role of a template.
/proc/material_template_role(fraction, default_material, label, description, optional = FALSE)
	return list(
		"fraction" = fraction,
		"default" = default_material,
		"label" = label,
		"description" = description,
		"optional" = optional,
	)

/// The shared singleton for a template type. Templates are read-only.
/proc/material_template_singleton(template_path) as /datum/material_template
	var/static/list/templates
	if(!template_path)
		return null
	if(isnull(templates))
		templates = list()
	. = templates[template_path]
	if(!.)
		. = new template_path
		templates[template_path] = .

/datum/material_template
	/// MATERIAL_APPLICATION_* this blueprint serves, or null for plain bulk material.
	var/application
	/// Ordered role -> material_template_role(). The last role takes the rounding remainder.
	var/list/roles
	/// TRUE for bulk and mix templates: plain material with no functional parts.
	var/bulk = FALSE

/// Amount of each role for a given total. Every role but the last is rounded; the
/// last takes the remainder, so the amounts always sum to exactly `total`.
/datum/material_template/proc/role_amounts(total)
	RETURN_TYPE(/list)
	. = list()
	var/remaining = total
	var/count = length(roles)
	var/index = 0
	for(var/role in roles)
		index++
		if(index == count)
			.[role] = remaining
		else
			var/amount = round(roles[role]["fraction"] * total)
			.[role] = amount
			remaining -= amount

/datum/material_template/proc/role_amount(role, total)
	var/list/amounts = role_amounts(total)
	return amounts[role] || 0

/datum/material_template/proc/default_material(role)
	return roles[role]?["default"]

/// Role -> material, filling unspecified roles with defaults. Null if a required
/// role has no valid material.
/datum/material_template/proc/resolve(list/requested)
	RETURN_TYPE(/list)
	var/list/resolved = list()
	for(var/role in roles)
		var/list/spec = roles[role]
		var/material_id = requested?[role]
		if(!material_id)
			material_id = spec["default"]
		if(!material_slot_choice_valid(spec, material_id))
			if(spec["optional"] && !material_id)
				continue
			return null
		resolved[role] = material_id
	return resolved

/// The single-role template for objects made of one plain material. Its default
/// material is the declaring type's material_bulk_material.
/datum/material_template/bulk
	bulk = TRUE
	roles = list(
		MATERIAL_ROLE_BULK = list("fraction" = 1, "default" = null, "label" = "Material", "description" = "The plain material this object is made of.", "optional" = FALSE),
	)

/// A fixed mix of plain materials, one role per material. Instances are interned by
/// content (material_mix_template()); they carry their exact amounts.
/datum/material_template/mix
	bulk = TRUE
	/// Material -> exact amount.
	var/list/amounts
	var/total = 0

/datum/material_template/mix/role_amounts(total)
	if(total == src.total)
		. = list()
		for(var/role in roles)
			.[role] = amounts[roles[role]["default"]]
		return .
	return ..()

/// The shared mix template for a material -> amount list, or null for an empty one.
/proc/material_mix_template(list/mix) as /datum/material_template/mix
	var/static/list/interned
	if(!length(mix))
		return null
	if(isnull(interned))
		interned = list()
	var/key = ""
	for(var/material_id in mix)
		key += "[material_id]=[mix[material_id]];"
	. = interned[key]
	if(.)
		return .
	var/datum/material_template/mix/template = new
	template.roles = list()
	template.amounts = list()
	for(var/material_id in mix)
		var/amount = mix[material_id]
		template.total += amount
		template.amounts[material_id] = amount
		template.roles[MATERIAL_BULK_ROLE(material_id)] = list("fraction" = 0, "default" = material_id, "label" = "Material", "description" = "Plain material.", "optional" = FALSE)
	for(var/role in template.roles)
		var/list/spec = template.roles[role]
		spec["fraction"] = template.total ? template.amounts[spec["default"]] / template.total : 0
	interned[key] = template
	return template

/// Motor-driven pressure devices: the pressure envelope plus the drive train.
/datum/material_template/pump
	application = MATERIAL_APPLICATION_PRESSURE
	roles = list(
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.175, "default" = MAT_STEEL, "label" = "Pressure shell", "description" = "Controls pressure limit, fracture, and high-temperature strength.", "optional" = FALSE),
		MATERIAL_ROLE_LINER = list("fraction" = 0.05, "default" = MAT_GLASS, "label" = "Exposed liner", "description" = "Controls corrosion, sorption, and contact chemistry.", "optional" = FALSE),
		MATERIAL_ROLE_INSULATION = list("fraction" = 0.025, "default" = MAT_PLASTIC, "label" = "Thermal isolation", "description" = "Layer controlling heat transfer through the vessel wall.", "optional" = FALSE),
		MATERIAL_ROLE_CONDUCTOR = list("fraction" = 0.25, "default" = MAT_COPPER, "label" = "Motor windings", "description" = "Drives the pump; controls electrical efficiency.", "optional" = FALSE),
		MATERIAL_ROLE_BEARINGS = list("fraction" = 0.25, "default" = MAT_STEEL, "label" = "Bearings", "description" = "Carries the rotor; controls friction and wear.", "optional" = FALSE),
		MATERIAL_ROLE_WORKING = list("fraction" = 0.25, "default" = MAT_STEEL, "label" = "Impeller", "description" = "Moves gas; controls wear against the working fluid.", "optional" = FALSE),
	)

/datum/material_template/tool
	application = MATERIAL_APPLICATION_TOOL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.7, "default" = MAT_STEEL, "label" = "Working head", "description" = "Controls hardness, wear, force, and heat tolerance.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.3, "default" = MAT_PLASTIC, "label" = "Grip", "description" = "Controls insulation, handling, and shock isolation.", "optional" = FALSE)
	)

/datum/material_template/surgical
	application = MATERIAL_APPLICATION_SURGICAL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.75, "default" = MAT_STEEL, "label" = "Working surface", "description" = "Controls precision, edge retention, cleanliness, and corrosion.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.25, "default" = MAT_PLASTIC, "label" = "Grip", "description" = "Controls handling and thermal/electrical isolation.", "optional" = FALSE)
	)

/datum/material_template/cell
	application = MATERIAL_APPLICATION_CELL
	roles = list(
		MATERIAL_ROLE_CONDUCTOR = list("fraction" = 0.35, "default" = MAT_COPPER, "label" = "Current collector", "description" = "Controls resistance, discharge current, and resistive heat.", "optional" = FALSE),
		MATERIAL_ROLE_ELECTRODE = list("fraction" = 0.3, "default" = MAT_COPPER, "label" = "Electrodes", "description" = "Controls charge capacity and electrochemical stability.", "optional" = FALSE),
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Casing", "description" = "Controls impact, pressure, and chemical durability.", "optional" = FALSE),
		MATERIAL_ROLE_THERMAL = list("fraction" = 0.1, "default" = MAT_COPPER, "label" = "Thermal buffer", "description" = "Absorbs and spreads operating heat around the cell.", "optional" = FALSE),
		MATERIAL_ROLE_INSULATION = list("fraction" = 0.05, "default" = MAT_GLASS, "label" = "Insulation", "description" = "Controls heat leakage, electrical isolation, and EMP coupling.", "optional" = FALSE)
	)

/datum/material_template/armor
	application = MATERIAL_APPLICATION_ARMOR
	roles = list(
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.65, "default" = MAT_STEEL, "label" = "Load-bearing layer", "description" = "Controls strength, mass, and fracture behavior.", "optional" = FALSE),
		MATERIAL_ROLE_LINER = list("fraction" = 0.15, "default" = MAT_CLOTH, "label" = "Inner liner", "description" = "Controls wearer contact, biocompatibility, and thermal comfort.", "optional" = FALSE),
		MATERIAL_ROLE_JACKET = list("fraction" = 0.2, "default" = MAT_PLASTIC, "label" = "Outer layer", "description" = "Controls corrosion, radiation exposure, and surface responses.", "optional" = FALSE)
	)

/datum/material_template/pressure
	application = MATERIAL_APPLICATION_PRESSURE
	roles = list(
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.7, "default" = MAT_STEEL, "label" = "Pressure shell", "description" = "Controls pressure limit, fracture, and high-temperature strength.", "optional" = FALSE),
		MATERIAL_ROLE_LINER = list("fraction" = 0.2, "default" = MAT_GLASS, "label" = "Exposed liner", "description" = "Controls corrosion, sorption, and contact chemistry.", "optional" = FALSE),
		MATERIAL_ROLE_INSULATION = list("fraction" = 0.1, "default" = MAT_PLASTIC, "label" = "Thermal isolation", "description" = "Layer controlling heat transfer through the vessel wall.", "optional" = FALSE)
	)

/datum/material_template/machine_part
	application = MATERIAL_APPLICATION_MACHINE_PART
	roles = list(
		MATERIAL_ROLE_CONDUCTOR = list("fraction" = 0.6, "default" = MAT_COPPER, "label" = "Functional element", "description" = "Controls electrical or electromechanical performance.", "optional" = FALSE),
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.3, "default" = MAT_STEEL, "label" = "Housing", "description" = "Controls integrity, mass, and operating tolerance.", "optional" = FALSE),
		MATERIAL_ROLE_THERMAL = list("fraction" = 0.1, "default" = MAT_COPPER, "label" = "Thermal element", "description" = "Heat-spreading or phase-buffering element.", "optional" = FALSE)
	)

/datum/material_template/projectile
	application = MATERIAL_APPLICATION_PROJECTILE
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.5, "default" = MAT_STEEL, "label" = "Projectile core", "description" = "Controls penetration, deformation, mass, and impact response.", "optional" = FALSE),
		MATERIAL_ROLE_JACKET = list("fraction" = 0.2, "default" = MAT_COPPER, "label" = "Projectile jacket", "description" = "Controls barrel interaction and exposed surface effects.", "optional" = FALSE),
		MATERIAL_ROLE_CASING = list("fraction" = 0.25, "default" = MAT_STEEL, "label" = "Cartridge case", "description" = "Contains propellant and seals the firing chamber.", "optional" = FALSE),
		MATERIAL_ROLE_PRIMER = list("fraction" = 0.05, "default" = MAT_COPPER, "label" = "Primer cup", "description" = "Holds the impact-sensitive ignition charge.", "optional" = FALSE)
	)

/datum/material_template/electronics
	application = MATERIAL_APPLICATION_ELECTRONICS
	roles = list(
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 1, "default" = MAT_PLASTIC, "label" = "Casing", "description" = "The device's user-selectable external shell; controls impact protection, mass, and environmental durability.", "optional" = FALSE)
	)

/datum/material_template/firearm
	application = MATERIAL_APPLICATION_FIREARM
	roles = list(
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.45, "default" = MAT_STEEL, "label" = "Receiver", "description" = "Controls integrity, recoil tolerance, and mass.", "optional" = FALSE),
		MATERIAL_ROLE_BARREL = list("fraction" = 0.4, "default" = MAT_STEEL, "label" = "Barrel", "description" = "Controls pressure tolerance, accuracy retention, and heat handling.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.15, "default" = MAT_PLASTIC, "label" = "Grip and furniture", "description" = "Controls handling, insulation, and weight.", "optional" = FALSE)
	)

/datum/material_template/container
	application = MATERIAL_APPLICATION_CONTAINER
	roles = list(
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.7, "default" = MAT_GLASS, "label" = "Vessel wall", "description" = "Controls integrity, mass, and temperature tolerance.", "optional" = FALSE),
		MATERIAL_ROLE_LINER = list("fraction" = 0.3, "default" = MAT_GLASS, "label" = "Wetted surface", "description" = "The surface touching the contents; controls corrosion, contamination, and chemical interaction.", "optional" = FALSE)
	)

/datum/material_template/capacitor
	application = MATERIAL_APPLICATION_CAPACITOR
	roles = list(
		MATERIAL_ROLE_ELECTRODE = list("fraction" = 0.42, "default" = MAT_COPPER, "label" = "Electrode foils", "description" = "Stores and releases charge; conductivity and surface stability control performance.", "optional" = FALSE),
		MATERIAL_ROLE_DIELECTRIC = list("fraction" = 0.33, "default" = MAT_GLASS, "label" = "Dielectric separator", "description" = "Separates the foils; dielectric strength controls voltage tolerance.", "optional" = FALSE),
		MATERIAL_ROLE_CONTACTS = list("fraction" = 0.1, "default" = MAT_GOLD, "label" = "Terminals", "description" = "Carries current into the component and resists contact corrosion.", "optional" = FALSE),
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.15, "default" = MAT_STEEL, "label" = "Casing", "description" = "Protects the rolled element from impact and heat.", "optional" = FALSE)
	)

/datum/material_template/manipulator
	application = MATERIAL_APPLICATION_MANIPULATOR
	roles = list(
		MATERIAL_ROLE_ACTUATOR = list("fraction" = 0.35, "default" = MAT_COPPER, "label" = "Actuator windings", "description" = "Converts current into precise motion.", "optional" = FALSE),
		MATERIAL_ROLE_BEARINGS = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Bearings and guides", "description" = "Controls friction, precision, and wear.", "optional" = FALSE),
		MATERIAL_ROLE_FRAME = list("fraction" = 0.3, "default" = MAT_STEEL, "label" = "Linkage frame", "description" = "Carries mechanical load and maintains alignment.", "optional" = FALSE),
		MATERIAL_ROLE_INSULATION = list("fraction" = 0.15, "default" = MAT_PLASTIC, "label" = "Winding insulation", "description" = "Electrically isolates the actuator and limits heat leakage.", "optional" = FALSE)
	)

/datum/material_template/matter_bin
	application = MATERIAL_APPLICATION_MATTER_BIN
	roles = list(
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.55, "default" = MAT_STEEL, "label" = "Containment chamber", "description" = "Carries pressure and mechanical loads around stored matter.", "optional" = FALSE),
		MATERIAL_ROLE_LINER = list("fraction" = 0.25, "default" = MAT_GLASS, "label" = "Chamber liner", "description" = "Contacts stored matter and controls contamination and corrosion.", "optional" = FALSE),
		MATERIAL_ROLE_FRAME = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Mounting frame", "description" = "Keeps the chamber aligned inside its parent machine.", "optional" = FALSE)
	)

/datum/material_template/scanner
	application = MATERIAL_APPLICATION_SCANNER
	roles = list(
		MATERIAL_ROLE_SENSOR = list("fraction" = 0.35, "default" = MAT_SILVER, "label" = "Sensor element", "description" = "Converts the measured field into an electrical signal.", "optional" = FALSE),
		MATERIAL_ROLE_OPTICAL = list("fraction" = 0.25, "default" = MAT_GLASS, "label" = "Optical window", "description" = "Admits and focuses radiation onto the sensor.", "optional" = FALSE),
		MATERIAL_ROLE_CONDUCTOR = list("fraction" = 0.2, "default" = MAT_COPPER, "label" = "Signal traces", "description" = "Carries weak sensor signals with minimal loss.", "optional" = FALSE),
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Shielded housing", "description" = "Maintains alignment and screens environmental noise.", "optional" = FALSE)
	)

/datum/material_template/laser
	application = MATERIAL_APPLICATION_LASER
	roles = list(
		MATERIAL_ROLE_EMITTER = list("fraction" = 0.35, "default" = MAT_GLASS, "label" = "Emitter crystal", "description" = "Generates the coherent output and controls energy tolerance.", "optional" = FALSE),
		MATERIAL_ROLE_OPTICAL = list("fraction" = 0.25, "default" = MAT_GLASS, "label" = "Focusing optics", "description" = "Shapes and focuses the emitted beam.", "optional" = FALSE),
		MATERIAL_ROLE_THERMAL = list("fraction" = 0.25, "default" = MAT_COPPER, "label" = "Heat sink", "description" = "Carries waste heat away from the emitter.", "optional" = FALSE),
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.15, "default" = MAT_STEEL, "label" = "Emitter mount", "description" = "Maintains optical alignment under heat and vibration.", "optional" = FALSE)
	)

/datum/material_template/magazine
	application = MATERIAL_APPLICATION_MAGAZINE
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.32, "default" = MAT_STEEL, "label" = "Projectile cores", "description" = "Controls the loaded rounds' penetration, deformation, and impact response.", "optional" = FALSE),
		MATERIAL_ROLE_JACKET = list("fraction" = 0.13, "default" = MAT_COPPER, "label" = "Projectile jackets", "description" = "Controls barrel interaction and exposed projectile behavior.", "optional" = FALSE),
		MATERIAL_ROLE_CASING = list("fraction" = 0.16, "default" = MAT_STEEL, "label" = "Cartridge cases", "description" = "Contains propellant and seals the firing chamber.", "optional" = FALSE),
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.18, "default" = MAT_STEEL, "label" = "Magazine body", "description" = "Protects and aligns the ammunition stack.", "optional" = FALSE),
		MATERIAL_ROLE_FEED = list("fraction" = 0.11, "default" = MAT_STEEL, "label" = "Feed lips and follower", "description" = "Controls reliable presentation of each round.", "optional" = FALSE),
		MATERIAL_ROLE_SPRING = list("fraction" = 0.1, "default" = MAT_STEEL, "label" = "Feed spring", "description" = "Maintains feed pressure through repeated compression cycles.", "optional" = FALSE)
	)

/datum/material_template/circuit_board
	application = MATERIAL_APPLICATION_CIRCUIT_BOARD
	roles = list(
		MATERIAL_ROLE_SUBSTRATE = list("fraction" = 0.5, "default" = MAT_GLASS, "label" = "Board substrate", "description" = "Supports and isolates the circuit under heat and flexing.", "optional" = FALSE),
		MATERIAL_ROLE_CONDUCTOR = list("fraction" = 0.35, "default" = MAT_COPPER, "label" = "Circuit traces", "description" = "Carries power and signals across the board.", "optional" = FALSE),
		MATERIAL_ROLE_CONTACTS = list("fraction" = 0.15, "default" = MAT_GOLD, "label" = "Edge contacts", "description" = "Provides reliable, corrosion-resistant external connections.", "optional" = FALSE)
	)

/datum/material_template/soft_goods
	application = MATERIAL_APPLICATION_SOFT_GOODS
	roles = list(
		MATERIAL_ROLE_FABRIC = list("fraction" = 0.7, "default" = MAT_CLOTH, "label" = "Fabric panels", "description" = "Forms the flexible body and controls comfort, mass, and thermal behavior.", "optional" = FALSE),
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.2, "default" = MAT_CLOTH, "label" = "Reinforcement", "description" = "Carries loads around seams and attachment points.", "optional" = FALSE),
		MATERIAL_ROLE_FASTENERS = list("fraction" = 0.1, "default" = MAT_STEEL, "label" = "Fasteners", "description" = "Joins panels and secures closures.", "optional" = FALSE)
	)

/datum/material_template/mechanical
	application = MATERIAL_APPLICATION_MECHANICAL
	roles = list(
		MATERIAL_ROLE_FRAME = list("fraction" = 0.5, "default" = MAT_STEEL, "label" = "Load-bearing frame", "description" = "Carries the assembly's structural and operating loads.", "optional" = FALSE),
		MATERIAL_ROLE_BEARINGS = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Moving interfaces", "description" = "Controls friction, alignment, and mechanical wear.", "optional" = FALSE),
		MATERIAL_ROLE_ACTUATOR = list("fraction" = 0.2, "default" = MAT_COPPER, "label" = "Drive element", "description" = "Transfers electrical or mechanical power into motion.", "optional" = FALSE),
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.1, "default" = MAT_STEEL, "label" = "Protective shell", "description" = "Protects the mechanism from impact and contamination.", "optional" = FALSE)
	)

/datum/material_template/cable
	application = MATERIAL_APPLICATION_CABLE
	roles = list(
		MATERIAL_ROLE_CONDUCTOR = list("fraction" = 0.75, "default" = MAT_COPPER, "label" = "Conductive strands", "description" = "Carries electrical current; resistance and current density control losses and capacity.", "optional" = FALSE),
		MATERIAL_ROLE_INSULATION = list("fraction" = 0.25, "default" = MAT_PLASTIC, "label" = "Insulating jacket", "description" = "Prevents shorts and protects the conductor from heat and chemicals.", "optional" = FALSE)
	)

/datum/material_template/light
	application = MATERIAL_APPLICATION_LIGHT
	roles = list(
		MATERIAL_ROLE_EMITTER = list("fraction" = 0.35, "default" = MAT_GLASS, "label" = "Light emitter", "description" = "Converts electrical energy into visible light.", "optional" = FALSE),
		MATERIAL_ROLE_OPTICAL = list("fraction" = 0.4, "default" = MAT_GLASS, "label" = "Envelope and optics", "description" = "Protects the emitter and shapes its output.", "optional" = FALSE),
		MATERIAL_ROLE_CONTACTS = list("fraction" = 0.25, "default" = MAT_COPPER, "label" = "Electrical contacts", "description" = "Carries power into the light source.", "optional" = FALSE)
	)

/datum/material_template/energy_device
	application = MATERIAL_APPLICATION_ENERGY_DEVICE
	roles = list(
		MATERIAL_ROLE_EMITTER = list("fraction" = 0.3, "default" = MAT_GLASS, "label" = "Energy emitter", "description" = "Converts stored power into the weapon's emitted field or beam.", "optional" = FALSE),
		MATERIAL_ROLE_OPTICAL = list("fraction" = 0.2, "default" = MAT_GLASS, "label" = "Beam-forming assembly", "description" = "Focuses and stabilizes the emitted energy.", "optional" = FALSE),
		MATERIAL_ROLE_CONDUCTOR = list("fraction" = 0.2, "default" = MAT_COPPER, "label" = "Power bus", "description" = "Carries discharge current from the cell to the emitter.", "optional" = FALSE),
		MATERIAL_ROLE_THERMAL = list("fraction" = 0.15, "default" = MAT_COPPER, "label" = "Heat sink", "description" = "Absorbs and spreads waste heat between shots.", "optional" = FALSE),
		MATERIAL_ROLE_STRUCTURE = list("fraction" = 0.15, "default" = MAT_STEEL, "label" = "Chassis", "description" = "Maintains alignment and protects the power train.", "optional" = FALSE)
	)

/datum/material_template/monolithic
	application = MATERIAL_APPLICATION_MONOLITHIC
	roles = list(
		MATERIAL_ROLE_BODY = list("fraction" = 1, "default" = MAT_STEEL, "label" = "Material", "description" = "The single continuous material from which this object is formed.", "optional" = FALSE)
	)

/datum/material_template/product/wrench
	application = MATERIAL_APPLICATION_TOOL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.45, "default" = MAT_STEEL, "label" = "Wrench jaws", "description" = "Controls grip on fasteners, deformation, and wear.", "optional" = FALSE),
		MATERIAL_ROLE_FRAME = list("fraction" = 0.4, "default" = MAT_STEEL, "label" = "Handle shank", "description" = "Carries torque between the hand and jaws.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.15, "default" = MAT_PLASTIC, "label" = "Grip", "description" = "Controls handling and electrical isolation.", "optional" = FALSE)
	)

/datum/material_template/product/screwdriver
	application = MATERIAL_APPLICATION_TOOL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.3, "default" = MAT_STEEL, "label" = "Driver tip", "description" = "Controls fit, wear, and transmitted torque.", "optional" = FALSE),
		MATERIAL_ROLE_FRAME = list("fraction" = 0.4, "default" = MAT_STEEL, "label" = "Driver shaft", "description" = "Carries torque without twisting or snapping.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.3, "default" = MAT_PLASTIC, "label" = "Insulated handle", "description" = "Controls handling and electrical isolation.", "optional" = FALSE)
	)

/datum/material_template/product/wirecutters
	application = MATERIAL_APPLICATION_TOOL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.4, "default" = MAT_STEEL, "label" = "Cutting jaws", "description" = "Controls edge life and cutting force.", "optional" = FALSE),
		MATERIAL_ROLE_BEARINGS = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Pivot joint", "description" = "Keeps the jaws aligned through repeated use.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.4, "default" = MAT_PLASTIC, "label" = "Insulated handles", "description" = "Controls leverage and electrical isolation.", "optional" = FALSE)
	)

/datum/material_template/product/crowbar
	application = MATERIAL_APPLICATION_TOOL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.35, "default" = MAT_STEEL, "label" = "Prying ends", "description" = "Controls bite, deformation, and wear against edges.", "optional" = FALSE),
		MATERIAL_ROLE_FRAME = list("fraction" = 0.5, "default" = MAT_STEEL, "label" = "Lever shaft", "description" = "Carries bending load while prying.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.15, "default" = MAT_PLASTIC, "label" = "Grip", "description" = "Controls handling and electrical isolation.", "optional" = FALSE)
	)

/datum/material_template/product/scalpel
	application = MATERIAL_APPLICATION_SURGICAL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.65, "default" = MAT_STEEL, "label" = "Blade", "description" = "Controls sharpness, edge retention, corrosion, and surgical precision.", "optional" = FALSE),
		MATERIAL_ROLE_FRAME = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Tang", "description" = "Transfers force from the handle into the blade without flexing.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.15, "default" = MAT_PLASTIC, "label" = "Grip", "description" = "Controls handling, insulation, and cleanability.", "optional" = FALSE)
	)

/datum/material_template/product/circular_saw
	application = MATERIAL_APPLICATION_SURGICAL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.5, "default" = MAT_STEEL, "label" = "Saw blade", "description" = "Controls cutting rate, tooth retention, heat, and wear.", "optional" = FALSE),
		MATERIAL_ROLE_BEARINGS = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Spindle and bearings", "description" = "Keeps the rotating blade aligned under load.", "optional" = FALSE),
		MATERIAL_ROLE_ACTUATOR = list("fraction" = 0.15, "default" = MAT_COPPER, "label" = "Motor windings", "description" = "Drives the blade and controls electrical efficiency.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.15, "default" = MAT_PLASTIC, "label" = "Insulated housing", "description" = "Protects and isolates the powered mechanism.", "optional" = FALSE)
	)

/datum/material_template/product/surgicaldrill
	application = MATERIAL_APPLICATION_SURGICAL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.35, "default" = MAT_STEEL, "label" = "Drill bit", "description" = "Controls cutting precision, wear, and heat generation.", "optional" = FALSE),
		MATERIAL_ROLE_BEARINGS = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Chuck and bearings", "description" = "Holds the bit concentric under surgical loads.", "optional" = FALSE),
		MATERIAL_ROLE_ACTUATOR = list("fraction" = 0.25, "default" = MAT_COPPER, "label" = "Motor windings", "description" = "Provides torque and controls electrical losses.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.2, "default" = MAT_PLASTIC, "label" = "Insulated housing", "description" = "Provides safe handling and encloses the drive.", "optional" = FALSE)
	)

/datum/material_template/product/hemostat
	application = MATERIAL_APPLICATION_SURGICAL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.45, "default" = MAT_STEEL, "label" = "Clamping jaws", "description" = "Controls grip precision, surface cleanliness, and corrosion.", "optional" = FALSE),
		MATERIAL_ROLE_BEARINGS = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Box joint", "description" = "Maintains jaw alignment through repeated use.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.35, "default" = MAT_STEEL, "label" = "Finger rings", "description" = "Transfers hand force and controls handling.", "optional" = FALSE)
	)

/datum/material_template/product/retractor
	application = MATERIAL_APPLICATION_SURGICAL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.5, "default" = MAT_STEEL, "label" = "Retractor blades", "description" = "Controls tissue contact, rigidity, and cleanability.", "optional" = FALSE),
		MATERIAL_ROLE_FRAME = list("fraction" = 0.3, "default" = MAT_STEEL, "label" = "Spreader frame", "description" = "Carries sustained opening force without flexing.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Adjustment handles", "description" = "Controls secure adjustment and handling.", "optional" = FALSE)
	)

/datum/material_template/product/cautery
	application = MATERIAL_APPLICATION_SURGICAL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.3, "default" = MAT_STEEL, "label" = "Cautery tip", "description" = "Contacts tissue and controls heat delivery and corrosion.", "optional" = FALSE),
		MATERIAL_ROLE_CONDUCTOR = list("fraction" = 0.35, "default" = MAT_COPPER, "label" = "Heating conductor", "description" = "Carries energy to the tip and controls resistive heating.", "optional" = FALSE),
		MATERIAL_ROLE_INSULATION = list("fraction" = 0.35, "default" = MAT_PLASTIC, "label" = "Thermal insulation", "description" = "Keeps operating heat away from the user's hand.", "optional" = FALSE)
	)

/datum/material_template/product/bonesetter
	application = MATERIAL_APPLICATION_SURGICAL
	roles = list(
		MATERIAL_ROLE_WORKING = list("fraction" = 0.5, "default" = MAT_STEEL, "label" = "Setting jaws", "description" = "Controls alignment, rigidity, and tissue-facing surface behavior.", "optional" = FALSE),
		MATERIAL_ROLE_BEARINGS = list("fraction" = 0.2, "default" = MAT_STEEL, "label" = "Pivot", "description" = "Keeps the jaws aligned under setting force.", "optional" = FALSE),
		MATERIAL_ROLE_GRIP = list("fraction" = 0.3, "default" = MAT_STEEL, "label" = "Handles", "description" = "Transfers controlled hand force into the jaws.", "optional" = FALSE)
	)
/// Fallback blueprint for an application with no dedicated template.
/datum/material_template/generic
	roles = list(
		MATERIAL_ROLE_BODY = list("fraction" = 1, "default" = MAT_STEEL, "label" = "Body", "description" = "The primary structural and functional material.", "optional" = FALSE),
	)

/// The application-level template (not a product-specific one) for a MATERIAL_APPLICATION_*.
/proc/material_template_for_application(application) as /datum/material_template
	var/static/list/by_application
	if(isnull(by_application))
		by_application = list()
		for(var/path in subtypesof(/datum/material_template) - typesof(/datum/material_template/product) - typesof(/datum/material_template/mix) - /datum/material_template/pump)
			var/datum/material_template/template = path
			var/app = initial(template.application)
			if(app && !by_application[app])
				by_application[app] = path
	var/path = by_application[application]
	return material_template_singleton(path || /datum/material_template/generic)

/// The per-type mix table declared with MATERIAL_MIX, registered at world start by the
/// macro's static initialiser. Called only from MATERIAL_MIX.
/proc/dq_register_material_mix(path, list/mix)
	var/datum/material_template/mix/template = material_mix_template(mix)
	if(isnull(GLOB_material_mix_registry))
		GLOB_material_mix_registry = list()
	GLOB_material_mix_registry[path] = template
	return template

/// Declared mix templates by type. No initialiser: static inits run in no fixed order.
GLOBAL_REAL_VAR(list/GLOB_material_mix_registry)

/// A type's MATERIAL_MIX template, from its nearest declaring ancestor, without an instance.
/proc/dq_type_material_mix(path) as /datum/material_template/mix
	for(var/datum/T = path; T; T = initial(T.parent_type))
		if(GLOB_material_mix_registry && (T in GLOB_material_mix_registry))
			return GLOB_material_mix_registry[T]
	return null

// ---- Type blueprints ----
// Products whose real construction differs from their application's generic
// blueprint. Totals come from each type's declared material_total.

/obj/item/tool/wrench
	material_template = /datum/material_template/product/wrench

/obj/item/tool/screwdriver
	material_template = /datum/material_template/product/screwdriver

/obj/item/tool/wirecutters
	material_template = /datum/material_template/product/wirecutters

/obj/item/tool/crowbar
	material_template = /datum/material_template/product/crowbar

/obj/item/tool/prybar
	material_template = /datum/material_template/product/crowbar

/obj/item/surgical/scalpel
	material_template = /datum/material_template/product/scalpel

/obj/item/surgical/circular_saw
	material_template = /datum/material_template/product/circular_saw

/obj/item/surgical/surgicaldrill
	material_template = /datum/material_template/product/surgicaldrill

/obj/item/surgical/hemostat
	material_template = /datum/material_template/product/hemostat

/obj/item/surgical/retractor
	material_template = /datum/material_template/product/retractor

/obj/item/surgical/cautery
	material_template = /datum/material_template/product/cautery

/obj/item/surgical/bonesetter
	material_template = /datum/material_template/product/bonesetter

/obj/item/surgical/bone_clamp
	material_template = /datum/material_template/product/bonesetter

/// Path of the application-level template for a MATERIAL_APPLICATION_*.
/proc/material_template_path_for_application(application)
	var/datum/material_template/template = material_template_for_application(application)
	return template.type
