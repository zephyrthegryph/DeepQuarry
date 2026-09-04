/// Generic material construction shared by lathes, hand crafting, and objects.
/// Slot definitions are plain immutable lists owned by a recipe/design. Finished
/// objects store only role -> canonical material id and role -> amount.

/proc/material_slot(role, label, amount, default_material, optional = FALSE, description = null, migrated_description = null)
	// Accept the former seven-argument call shape during the source migration;
	// the discarded sixth value carried the deleted categorical restriction.
	if(!isnull(migrated_description))
		description = migrated_description
	return list(
		"role" = role,
		"label" = label,
		"amount" = amount,
		"default" = default_material,
		"optional" = optional,
		"description" = description,
	)

/proc/default_material_slots(application, total_amount)
	var/amount = max(round(total_amount), 1)
	switch(application)
		if(MATERIAL_APPLICATION_TOOL)
			return list(
				MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Working head", round(amount * 0.7), MAT_STEEL, FALSE, null, "Controls hardness, wear, force, and heat tolerance."),
				MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Grip", max(1, amount - round(amount * 0.7)), MAT_PLASTIC, FALSE, null, "Controls insulation, handling, and shock isolation."),
			)
		if(MATERIAL_APPLICATION_SURGICAL)
			return list(
				MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Working surface", round(amount * 0.75), MAT_STEEL, FALSE, null, "Controls precision, edge retention, cleanliness, and corrosion."),
				MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Grip", max(1, amount - round(amount * 0.75)), MAT_PLASTIC, FALSE, null, "Controls handling and thermal/electrical isolation."),
			)
		if(MATERIAL_APPLICATION_CELL)
			return list(
				MATERIAL_ROLE_CONDUCTOR = material_slot(MATERIAL_ROLE_CONDUCTOR, "Current collector", round(amount * 0.35), MAT_COPPER, FALSE, null, "Controls resistance, discharge current, and resistive heat."),
				MATERIAL_ROLE_ELECTRODE = material_slot(MATERIAL_ROLE_ELECTRODE, "Electrodes", round(amount * 0.3), MAT_COPPER, FALSE, null, "Controls charge capacity and electrochemical stability."),
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Casing", round(amount * 0.2), MAT_STEEL, FALSE, null, "Controls impact, pressure, and chemical durability."),
				MATERIAL_ROLE_THERMAL = material_slot(MATERIAL_ROLE_THERMAL, "Thermal buffer", round(amount * 0.1), MAT_COPPER, FALSE, null, "Absorbs and spreads operating heat around the cell."),
				MATERIAL_ROLE_INSULATION = material_slot(MATERIAL_ROLE_INSULATION, "Insulation", max(1, round(amount * 0.05)), MAT_GLASS, FALSE, null, "Controls heat leakage, electrical isolation, and EMP coupling."),
			)
		if(MATERIAL_APPLICATION_ARMOR)
			return list(
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Load-bearing layer", round(amount * 0.65), MAT_STEEL, FALSE, null, "Controls strength, mass, and fracture behavior."),
				MATERIAL_ROLE_LINER = material_slot(MATERIAL_ROLE_LINER, "Inner liner", round(amount * 0.15), MAT_CLOTH, FALSE, null, "Controls wearer contact, biocompatibility, and thermal comfort."),
				MATERIAL_ROLE_JACKET = material_slot(MATERIAL_ROLE_JACKET, "Outer layer", max(1, round(amount * 0.2)), MAT_PLASTIC, FALSE, null, "Controls corrosion, radiation exposure, and surface responses."),
			)
		if(MATERIAL_APPLICATION_PRESSURE)
			return list(
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Pressure shell", round(amount * 0.7), MAT_STEEL, FALSE, null, "Controls pressure limit, fracture, and high-temperature strength."),
				MATERIAL_ROLE_LINER = material_slot(MATERIAL_ROLE_LINER, "Exposed liner", round(amount * 0.2), MAT_GLASS, FALSE, null, "Controls corrosion, sorption, and contact chemistry."),
				MATERIAL_ROLE_INSULATION = material_slot(MATERIAL_ROLE_INSULATION, "Thermal isolation", max(1, round(amount * 0.1)), MAT_PLASTIC, FALSE, null, "Layer controlling heat transfer through the vessel wall."),
			)
		if(MATERIAL_APPLICATION_MACHINE_PART)
			return list(
				MATERIAL_ROLE_CONDUCTOR = material_slot(MATERIAL_ROLE_CONDUCTOR, "Functional element", round(amount * 0.6), MAT_COPPER, FALSE, null, "Controls electrical or electromechanical performance."),
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Housing", round(amount * 0.3), MAT_STEEL, FALSE, null, "Controls integrity, mass, and operating tolerance."),
				MATERIAL_ROLE_THERMAL = material_slot(MATERIAL_ROLE_THERMAL, "Thermal element", max(1, round(amount * 0.1)), MAT_COPPER, FALSE, null, "Heat-spreading or phase-buffering element."),
			)
		if(MATERIAL_APPLICATION_PROJECTILE)
			return list(
				MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Projectile core", round(amount * 0.5), MAT_STEEL, FALSE, null, "Controls penetration, deformation, mass, and impact response."),
				MATERIAL_ROLE_JACKET = material_slot(MATERIAL_ROLE_JACKET, "Projectile jacket", round(amount * 0.2), MAT_COPPER, FALSE, null, "Controls barrel interaction and exposed surface effects."),
				MATERIAL_ROLE_CASING = material_slot(MATERIAL_ROLE_CASING, "Cartridge case", round(amount * 0.25), MAT_STEEL, FALSE, "Contains propellant and seals the firing chamber."),
				MATERIAL_ROLE_PRIMER = material_slot(MATERIAL_ROLE_PRIMER, "Primer cup", max(1, round(amount * 0.05)), MAT_COPPER, FALSE, "Holds the impact-sensitive ignition charge."),
			)
		if(MATERIAL_APPLICATION_ELECTRONICS)
			return list(
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Casing", amount, MAT_PLASTIC, FALSE, "The device's user-selectable external shell; controls impact protection, mass, and environmental durability."),
			)
		if(MATERIAL_APPLICATION_FIREARM)
			return list(
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Receiver", round(amount * 0.45), MAT_STEEL, FALSE, "Controls integrity, recoil tolerance, and mass."),
				MATERIAL_ROLE_BARREL = material_slot(MATERIAL_ROLE_BARREL, "Barrel", round(amount * 0.4), MAT_STEEL, FALSE, "Controls pressure tolerance, accuracy retention, and heat handling."),
				MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Grip and furniture", max(1, round(amount * 0.15)), MAT_PLASTIC, FALSE, "Controls handling, insulation, and weight."),
			)
		if(MATERIAL_APPLICATION_CONTAINER)
			return list(
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Vessel wall", round(amount * 0.7), MAT_GLASS, FALSE, "Controls integrity, mass, and temperature tolerance."),
				MATERIAL_ROLE_LINER = material_slot(MATERIAL_ROLE_LINER, "Wetted surface", max(1, round(amount * 0.3)), MAT_GLASS, FALSE, "The surface touching the contents; controls corrosion, contamination, and chemical interaction."),
			)
		if(MATERIAL_APPLICATION_CAPACITOR)
			return list(
				MATERIAL_ROLE_ELECTRODE = material_slot(MATERIAL_ROLE_ELECTRODE, "Electrode foils", round(amount * 0.42), MAT_COPPER, FALSE, "Stores and releases charge; conductivity and surface stability control performance."),
				MATERIAL_ROLE_DIELECTRIC = material_slot(MATERIAL_ROLE_DIELECTRIC, "Dielectric separator", round(amount * 0.33), MAT_GLASS, FALSE, "Separates the foils; dielectric strength controls voltage tolerance."),
				MATERIAL_ROLE_CONTACTS = material_slot(MATERIAL_ROLE_CONTACTS, "Terminals", round(amount * 0.1), MAT_GOLD, FALSE, "Carries current into the component and resists contact corrosion."),
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Casing", max(1, round(amount * 0.15)), MAT_STEEL, FALSE, "Protects the rolled element from impact and heat."),
			)
		if(MATERIAL_APPLICATION_MANIPULATOR)
			return list(
				MATERIAL_ROLE_ACTUATOR = material_slot(MATERIAL_ROLE_ACTUATOR, "Actuator windings", round(amount * 0.35), MAT_COPPER, FALSE, "Converts current into precise motion."),
				MATERIAL_ROLE_BEARINGS = material_slot(MATERIAL_ROLE_BEARINGS, "Bearings and guides", round(amount * 0.2), MAT_STEEL, FALSE, "Controls friction, precision, and wear."),
				MATERIAL_ROLE_FRAME = material_slot(MATERIAL_ROLE_FRAME, "Linkage frame", round(amount * 0.3), MAT_STEEL, FALSE, "Carries mechanical load and maintains alignment."),
				MATERIAL_ROLE_INSULATION = material_slot(MATERIAL_ROLE_INSULATION, "Winding insulation", max(1, round(amount * 0.15)), MAT_PLASTIC, FALSE, "Electrically isolates the actuator and limits heat leakage."),
			)
		if(MATERIAL_APPLICATION_MATTER_BIN)
			return list(
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Containment chamber", round(amount * 0.55), MAT_STEEL, FALSE, "Carries pressure and mechanical loads around stored matter."),
				MATERIAL_ROLE_LINER = material_slot(MATERIAL_ROLE_LINER, "Chamber liner", round(amount * 0.25), MAT_GLASS, FALSE, "Contacts stored matter and controls contamination and corrosion."),
				MATERIAL_ROLE_FRAME = material_slot(MATERIAL_ROLE_FRAME, "Mounting frame", max(1, round(amount * 0.2)), MAT_STEEL, FALSE, "Keeps the chamber aligned inside its parent machine."),
			)
		if(MATERIAL_APPLICATION_SCANNER)
			return list(
				MATERIAL_ROLE_SENSOR = material_slot(MATERIAL_ROLE_SENSOR, "Sensor element", round(amount * 0.35), MAT_SILVER, FALSE, "Converts the measured field into an electrical signal."),
				MATERIAL_ROLE_OPTICAL = material_slot(MATERIAL_ROLE_OPTICAL, "Optical window", round(amount * 0.25), MAT_GLASS, FALSE, "Admits and focuses radiation onto the sensor."),
				MATERIAL_ROLE_CONDUCTOR = material_slot(MATERIAL_ROLE_CONDUCTOR, "Signal traces", round(amount * 0.2), MAT_COPPER, FALSE, "Carries weak sensor signals with minimal loss."),
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Shielded housing", max(1, round(amount * 0.2)), MAT_STEEL, FALSE, "Maintains alignment and screens environmental noise."),
			)
		if(MATERIAL_APPLICATION_LASER)
			return list(
				MATERIAL_ROLE_EMITTER = material_slot(MATERIAL_ROLE_EMITTER, "Emitter crystal", round(amount * 0.35), MAT_GLASS, FALSE, "Generates the coherent output and controls energy tolerance."),
				MATERIAL_ROLE_OPTICAL = material_slot(MATERIAL_ROLE_OPTICAL, "Focusing optics", round(amount * 0.25), MAT_GLASS, FALSE, "Shapes and focuses the emitted beam."),
				MATERIAL_ROLE_THERMAL = material_slot(MATERIAL_ROLE_THERMAL, "Heat sink", round(amount * 0.25), MAT_COPPER, FALSE, "Carries waste heat away from the emitter."),
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Emitter mount", max(1, round(amount * 0.15)), MAT_STEEL, FALSE, "Maintains optical alignment under heat and vibration."),
			)
		if(MATERIAL_APPLICATION_MAGAZINE)
			return list(
				MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Projectile cores", round(amount * 0.32), MAT_STEEL, FALSE, "Controls the loaded rounds' penetration, deformation, and impact response."),
				MATERIAL_ROLE_JACKET = material_slot(MATERIAL_ROLE_JACKET, "Projectile jackets", round(amount * 0.13), MAT_COPPER, FALSE, "Controls barrel interaction and exposed projectile behavior."),
				MATERIAL_ROLE_CASING = material_slot(MATERIAL_ROLE_CASING, "Cartridge cases", round(amount * 0.16), MAT_STEEL, FALSE, "Contains propellant and seals the firing chamber."),
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Magazine body", round(amount * 0.18), MAT_STEEL, FALSE, "Protects and aligns the ammunition stack."),
				MATERIAL_ROLE_FEED = material_slot(MATERIAL_ROLE_FEED, "Feed lips and follower", round(amount * 0.11), MAT_STEEL, FALSE, "Controls reliable presentation of each round."),
				MATERIAL_ROLE_SPRING = material_slot(MATERIAL_ROLE_SPRING, "Feed spring", max(1, round(amount * 0.1)), MAT_STEEL, FALSE, "Maintains feed pressure through repeated compression cycles."),
			)
		if(MATERIAL_APPLICATION_CIRCUIT_BOARD)
			return list(
				MATERIAL_ROLE_SUBSTRATE = material_slot(MATERIAL_ROLE_SUBSTRATE, "Board substrate", round(amount * 0.5), MAT_GLASS, FALSE, "Supports and isolates the circuit under heat and flexing."),
				MATERIAL_ROLE_CONDUCTOR = material_slot(MATERIAL_ROLE_CONDUCTOR, "Circuit traces", round(amount * 0.35), MAT_COPPER, FALSE, "Carries power and signals across the board."),
				MATERIAL_ROLE_CONTACTS = material_slot(MATERIAL_ROLE_CONTACTS, "Edge contacts", max(1, round(amount * 0.15)), MAT_GOLD, FALSE, "Provides reliable, corrosion-resistant external connections."),
			)
		if(MATERIAL_APPLICATION_SOFT_GOODS)
			return list(
				MATERIAL_ROLE_FABRIC = material_slot(MATERIAL_ROLE_FABRIC, "Fabric panels", round(amount * 0.7), MAT_CLOTH, FALSE, "Forms the flexible body and controls comfort, mass, and thermal behavior."),
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Reinforcement", round(amount * 0.2), MAT_CLOTH, FALSE, "Carries loads around seams and attachment points."),
				MATERIAL_ROLE_FASTENERS = material_slot(MATERIAL_ROLE_FASTENERS, "Fasteners", max(1, round(amount * 0.1)), MAT_STEEL, FALSE, "Joins panels and secures closures."),
			)
		if(MATERIAL_APPLICATION_MECHANICAL)
			return list(
				MATERIAL_ROLE_FRAME = material_slot(MATERIAL_ROLE_FRAME, "Load-bearing frame", round(amount * 0.5), MAT_STEEL, FALSE, "Carries the assembly's structural and operating loads."),
				MATERIAL_ROLE_BEARINGS = material_slot(MATERIAL_ROLE_BEARINGS, "Moving interfaces", round(amount * 0.2), MAT_STEEL, FALSE, "Controls friction, alignment, and mechanical wear."),
				MATERIAL_ROLE_ACTUATOR = material_slot(MATERIAL_ROLE_ACTUATOR, "Drive element", round(amount * 0.2), MAT_COPPER, FALSE, "Transfers electrical or mechanical power into motion."),
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Protective shell", max(1, round(amount * 0.1)), MAT_STEEL, FALSE, "Protects the mechanism from impact and contamination."),
			)
		if(MATERIAL_APPLICATION_CABLE)
			return list(
				MATERIAL_ROLE_CONDUCTOR = material_slot(MATERIAL_ROLE_CONDUCTOR, "Conductive strands", round(amount * 0.75), MAT_COPPER, FALSE, "Carries electrical current; resistance and current density control losses and capacity."),
				MATERIAL_ROLE_INSULATION = material_slot(MATERIAL_ROLE_INSULATION, "Insulating jacket", max(1, round(amount * 0.25)), MAT_PLASTIC, FALSE, "Prevents shorts and protects the conductor from heat and chemicals."),
			)
		if(MATERIAL_APPLICATION_LIGHT)
			return list(
				MATERIAL_ROLE_EMITTER = material_slot(MATERIAL_ROLE_EMITTER, "Light emitter", round(amount * 0.35), MAT_GLASS, FALSE, "Converts electrical energy into visible light."),
				MATERIAL_ROLE_OPTICAL = material_slot(MATERIAL_ROLE_OPTICAL, "Envelope and optics", round(amount * 0.4), MAT_GLASS, FALSE, "Protects the emitter and shapes its output."),
				MATERIAL_ROLE_CONTACTS = material_slot(MATERIAL_ROLE_CONTACTS, "Electrical contacts", max(1, round(amount * 0.25)), MAT_COPPER, FALSE, "Carries power into the light source."),
			)
		if(MATERIAL_APPLICATION_ENERGY_DEVICE)
			return list(
				MATERIAL_ROLE_EMITTER = material_slot(MATERIAL_ROLE_EMITTER, "Energy emitter", round(amount * 0.3), MAT_GLASS, FALSE, "Converts stored power into the weapon's emitted field or beam."),
				MATERIAL_ROLE_OPTICAL = material_slot(MATERIAL_ROLE_OPTICAL, "Beam-forming assembly", round(amount * 0.2), MAT_GLASS, FALSE, "Focuses and stabilizes the emitted energy."),
				MATERIAL_ROLE_CONDUCTOR = material_slot(MATERIAL_ROLE_CONDUCTOR, "Power bus", round(amount * 0.2), MAT_COPPER, FALSE, "Carries discharge current from the cell to the emitter."),
				MATERIAL_ROLE_THERMAL = material_slot(MATERIAL_ROLE_THERMAL, "Heat sink", round(amount * 0.15), MAT_COPPER, FALSE, "Absorbs and spreads waste heat between shots."),
				MATERIAL_ROLE_STRUCTURE = material_slot(MATERIAL_ROLE_STRUCTURE, "Chassis", max(1, round(amount * 0.15)), MAT_STEEL, FALSE, "Maintains alignment and protects the power train."),
			)
		if(MATERIAL_APPLICATION_MONOLITHIC)
			return list(
				MATERIAL_ROLE_BODY = material_slot(MATERIAL_ROLE_BODY, "Material", amount, MAT_STEEL, FALSE, "The single continuous material from which this object is formed."),
			)
	return list(MATERIAL_ROLE_BODY = material_slot(MATERIAL_ROLE_BODY, "Body", amount, MAT_STEEL, FALSE, "The primary structural and functional material."))

/// Product-specific blueprints sit above the reusable family profiles. These
/// distinguish tools whose real construction differs despite sharing a common
/// gameplay parent type.
/proc/material_slots_for_product(product_path, application, total_amount)
	var/amount = max(round(total_amount), 1)
	if(ispath(product_path, /obj/item/tool/wrench))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Wrench jaws", round(amount * 0.45), MAT_STEEL, FALSE, "Controls grip on fasteners, deformation, and wear."),
			MATERIAL_ROLE_FRAME = material_slot(MATERIAL_ROLE_FRAME, "Handle shank", round(amount * 0.4), MAT_STEEL, FALSE, "Carries torque between the hand and jaws."),
			MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Grip", max(1, round(amount * 0.15)), MAT_PLASTIC, FALSE, "Controls handling and electrical isolation."),
		)
	if(ispath(product_path, /obj/item/tool/screwdriver))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Driver tip", round(amount * 0.3), MAT_STEEL, FALSE, "Controls fit, wear, and transmitted torque."),
			MATERIAL_ROLE_FRAME = material_slot(MATERIAL_ROLE_FRAME, "Driver shaft", round(amount * 0.4), MAT_STEEL, FALSE, "Carries torque without twisting or snapping."),
			MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Insulated handle", max(1, round(amount * 0.3)), MAT_PLASTIC, FALSE, "Controls handling and electrical isolation."),
		)
	if(ispath(product_path, /obj/item/tool/wirecutters))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Cutting jaws", round(amount * 0.4), MAT_STEEL, FALSE, "Controls edge life and cutting force."),
			MATERIAL_ROLE_BEARINGS = material_slot(MATERIAL_ROLE_BEARINGS, "Pivot joint", round(amount * 0.2), MAT_STEEL, FALSE, "Keeps the jaws aligned through repeated use."),
			MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Insulated handles", max(1, round(amount * 0.4)), MAT_PLASTIC, FALSE, "Controls leverage and electrical isolation."),
		)
	if(ispath(product_path, /obj/item/tool/crowbar) || ispath(product_path, /obj/item/tool/prybar))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Prying ends", round(amount * 0.35), MAT_STEEL, FALSE, "Controls bite, deformation, and wear against edges."),
			MATERIAL_ROLE_FRAME = material_slot(MATERIAL_ROLE_FRAME, "Lever shaft", round(amount * 0.5), MAT_STEEL, FALSE, "Carries bending load while prying."),
			MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Grip", max(1, round(amount * 0.15)), MAT_PLASTIC, FALSE, "Controls handling and electrical isolation."),
		)
	if(ispath(product_path, /obj/item/surgical/scalpel))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Blade", round(amount * 0.65), MAT_STEEL, FALSE, "Controls sharpness, edge retention, corrosion, and surgical precision."),
			MATERIAL_ROLE_FRAME = material_slot(MATERIAL_ROLE_FRAME, "Tang", round(amount * 0.2), MAT_STEEL, FALSE, "Transfers force from the handle into the blade without flexing."),
			MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Grip", max(1, round(amount * 0.15)), MAT_PLASTIC, FALSE, "Controls handling, insulation, and cleanability."),
		)
	if(ispath(product_path, /obj/item/surgical/circular_saw))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Saw blade", round(amount * 0.5), MAT_STEEL, FALSE, "Controls cutting rate, tooth retention, heat, and wear."),
			MATERIAL_ROLE_BEARINGS = material_slot(MATERIAL_ROLE_BEARINGS, "Spindle and bearings", round(amount * 0.2), MAT_STEEL, FALSE, "Keeps the rotating blade aligned under load."),
			MATERIAL_ROLE_ACTUATOR = material_slot(MATERIAL_ROLE_ACTUATOR, "Motor windings", round(amount * 0.15), MAT_COPPER, FALSE, "Drives the blade and controls electrical efficiency."),
			MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Insulated housing", max(1, round(amount * 0.15)), MAT_PLASTIC, FALSE, "Protects and isolates the powered mechanism."),
		)
	if(ispath(product_path, /obj/item/surgical/surgicaldrill))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Drill bit", round(amount * 0.35), MAT_STEEL, FALSE, "Controls cutting precision, wear, and heat generation."),
			MATERIAL_ROLE_BEARINGS = material_slot(MATERIAL_ROLE_BEARINGS, "Chuck and bearings", round(amount * 0.2), MAT_STEEL, FALSE, "Holds the bit concentric under surgical loads."),
			MATERIAL_ROLE_ACTUATOR = material_slot(MATERIAL_ROLE_ACTUATOR, "Motor windings", round(amount * 0.25), MAT_COPPER, FALSE, "Provides torque and controls electrical losses."),
			MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Insulated housing", max(1, round(amount * 0.2)), MAT_PLASTIC, FALSE, "Provides safe handling and encloses the drive."),
		)
	if(ispath(product_path, /obj/item/surgical/hemostat))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Clamping jaws", round(amount * 0.45), MAT_STEEL, FALSE, "Controls grip precision, surface cleanliness, and corrosion."),
			MATERIAL_ROLE_BEARINGS = material_slot(MATERIAL_ROLE_BEARINGS, "Box joint", round(amount * 0.2), MAT_STEEL, FALSE, "Maintains jaw alignment through repeated use."),
			MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Finger rings", max(1, round(amount * 0.35)), MAT_STEEL, FALSE, "Transfers hand force and controls handling."),
		)
	if(ispath(product_path, /obj/item/surgical/retractor))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Retractor blades", round(amount * 0.5), MAT_STEEL, FALSE, "Controls tissue contact, rigidity, and cleanability."),
			MATERIAL_ROLE_FRAME = material_slot(MATERIAL_ROLE_FRAME, "Spreader frame", round(amount * 0.3), MAT_STEEL, FALSE, "Carries sustained opening force without flexing."),
			MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Adjustment handles", max(1, round(amount * 0.2)), MAT_STEEL, FALSE, "Controls secure adjustment and handling."),
		)
	if(ispath(product_path, /obj/item/surgical/cautery))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Cautery tip", round(amount * 0.3), MAT_STEEL, FALSE, "Contacts tissue and controls heat delivery and corrosion."),
			MATERIAL_ROLE_CONDUCTOR = material_slot(MATERIAL_ROLE_CONDUCTOR, "Heating conductor", round(amount * 0.35), MAT_COPPER, FALSE, "Carries energy to the tip and controls resistive heating."),
			MATERIAL_ROLE_INSULATION = material_slot(MATERIAL_ROLE_INSULATION, "Thermal insulation", max(1, round(amount * 0.35)), MAT_PLASTIC, FALSE, "Keeps operating heat away from the user's hand."),
		)
	if(ispath(product_path, /obj/item/surgical/bonesetter) || ispath(product_path, /obj/item/surgical/bone_clamp))
		return list(
			MATERIAL_ROLE_WORKING = material_slot(MATERIAL_ROLE_WORKING, "Setting jaws", round(amount * 0.5), MAT_STEEL, FALSE, "Controls alignment, rigidity, and tissue-facing surface behavior."),
			MATERIAL_ROLE_BEARINGS = material_slot(MATERIAL_ROLE_BEARINGS, "Pivot", round(amount * 0.2), MAT_STEEL, FALSE, "Keeps the jaws aligned under setting force."),
			MATERIAL_ROLE_GRIP = material_slot(MATERIAL_ROLE_GRIP, "Handles", max(1, round(amount * 0.3)), MAT_STEEL, FALSE, "Transfers controlled hand force into the jaws."),
		)
	return default_material_slots(application, amount)

/proc/material_slot_choice_valid(list/spec, material_id)
	if(!islist(spec))
		return FALSE
	if(!material_id)
		return !!spec["optional"]
	var/datum/material/material = get_material_by_name(material_id)
	if(!material)
		return FALSE
	return TRUE

/// Scores continuous physical properties for the job a part performs. This is
/// used only to choose and rank defaults; every solid stack remains selectable.
/proc/material_role_score(datum/material/material, role)
	if(!istype(material))
		return -INFINITY
	switch(role)
		if(MATERIAL_ROLE_CONDUCTOR, MATERIAL_ROLE_CONTACTS, MATERIAL_ROLE_ACTUATOR)
			return material.conductivity * 2 + material.corrosion_resistance + material.critical_current_density * 0.02 - material.electrical_resistivity
		if(MATERIAL_ROLE_INSULATION, MATERIAL_ROLE_GRIP, MATERIAL_ROLE_SUBSTRATE, MATERIAL_ROLE_DIELECTRIC)
			return material.dielectric_strength + material.thermal_insulation + material.integrity * 0.2 - material.conductivity
		if(MATERIAL_ROLE_WORKING, MATERIAL_ROLE_BARREL, MATERIAL_ROLE_BEARINGS, MATERIAL_ROLE_FEED, MATERIAL_ROLE_SPRING)
			return material.hardness + material.heat_resistance + material.fracture_toughness * 0.5 - material.brittleness
		if(MATERIAL_ROLE_SENSOR, MATERIAL_ROLE_EMITTER, MATERIAL_ROLE_OPTICAL)
			return material.purity_equivalent() + material.heat_resistance + material.conductivity * 0.5 - material.reactivity
		if(MATERIAL_ROLE_THERMAL)
			return material.specific_heat * 0.05 + material.heat_resistance + material.phase_change_capacity * 0.1
		if(MATERIAL_ROLE_LINER, MATERIAL_ROLE_JACKET)
			return material.corrosion_resistance + material.heat_resistance * 0.5 + material.biocompatibility - material.reactivity - material.toxicity
	return material.integrity + material.yield_strength * 0.2 + material.fracture_toughness - material.brittleness * 0.5 - material.density * 0.05

/proc/material_slot_resolve(list/slots, list/requested)
	var/list/resolved = list()
	for(var/role in slots)
		var/list/spec = slots[role]
		var/material_id = requested?[role]
		if(!material_id)
			material_id = spec["default"]
		if(!material_slot_choice_valid(spec, material_id))
			if(spec["optional"] && !material_id)
				continue
			return null
		resolved[role] = material_id
	return resolved

/proc/material_slots_tgui(list/slots)
	var/list/out = list()
	for(var/role in slots)
		var/list/spec = slots[role]
		out += list(list(
			"role" = role,
			"label" = spec["label"],
			"amount" = spec["amount"],
			"defaultMaterial" = spec["default"],
			"optional" = !!spec["optional"],
			"description" = spec["description"],
		))
	return out

/// Correct independent percentage rounding so a blueprint consumes exactly
/// the recipe's original amount. The final required part absorbs the small
/// rounding remainder; no material is created or lost.
/proc/material_slots_normalize_total(list/slots, target_total)
	if(!length(slots) || target_total < 1)
		return FALSE
	var/current_total = 0
	var/list/adjustment_spec
	for(var/role in slots)
		var/list/spec = slots[role]
		current_total += spec["amount"]
		if(!spec["optional"])
			adjustment_spec = spec
	if(!adjustment_spec)
		return FALSE
	adjustment_spec["amount"] += target_total - current_total
	return adjustment_spec["amount"] > 0

/obj
	/// Canonical material IDs by functional construction role. Lazy per object.
	var/list/construction_materials
	/// Material units by role, used for inspection, recycling, and weighted behavior.
	var/list/construction_material_amounts

/obj/proc/material_for_role(role) as /datum/material
	var/material_id = construction_materials?[role]
	return material_id ? get_material_by_name(material_id) : null

/obj/proc/primary_construction_material() as /datum/material
	for(var/role in list(MATERIAL_ROLE_WORKING, MATERIAL_ROLE_CONDUCTOR, MATERIAL_ROLE_STRUCTURE, MATERIAL_ROLE_FRAME, MATERIAL_ROLE_EMITTER, MATERIAL_ROLE_FABRIC, MATERIAL_ROLE_BODY, MATERIAL_ROLE_JACKET))
		var/datum/material/material = material_for_role(role)
		if(material)
			return material
	return null

/obj/proc/apply_material_construction(list/materials_by_role, list/slots, application_profile)
	var/list/resolved = material_slot_resolve(slots, materials_by_role)
	if(!length(resolved))
		return FALSE
	construction_materials = resolved.Copy()
	construction_material_amounts = list()
	for(var/role in resolved)
		var/list/spec = slots[role]
		construction_material_amounts[role] = spec?["amount"] || 0
	if(isitem(src))
		var/obj/item/item = src
		item.apply_material_role_effects(application_profile)
	return TRUE

/// Preserve the complete functional assembly when an item becomes an installed
/// object (or is taken apart again).  Copying only the visually dominant
/// material silently discarded liners, insulation, contacts, and similar parts.
/obj/proc/copy_material_construction_from(obj/source)
	if(!source)
		return FALSE
	construction_materials = source.construction_materials?.Copy()
	construction_material_amounts = source.construction_material_amounts?.Copy()
	return length(construction_materials)

/// Give legacy/map-built infrastructure the same canonical assembly used by
/// fabrication, without pretending that it was a custom engineered product.
/obj/proc/ensure_material_construction(application_profile, total_amount = SHEET_MATERIAL_AMOUNT)
	if(length(construction_materials))
		return TRUE
	var/list/slots = default_material_slots(application_profile, total_amount)
	return apply_material_construction(null, slots, application_profile)

/obj/proc/construction_summary()
	var/list/summary = list()
	for(var/role in construction_materials)
		var/datum/material/material = material_for_role(role)
		if(material)
			summary += "[role]: [material.display_name]"
	return summary

/// Role-aware constitutive APIs. Systems consume the part that physically
/// performs the job instead of averaging an item into one magic material.
/obj/proc/construction_electrical_resistance(length_m, area_mm2, temperature, current_density = 0)
	var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR) || primary_construction_material()
	return conductor ? conductor.material_electrical_resistance(length_m, area_mm2, temperature, current_density) : null

/obj/proc/construction_thermal_conductance(area_m2, thickness_m, temperature)
	var/datum/material/thermal = material_for_role(MATERIAL_ROLE_THERMAL) || material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	var/conductance = thermal ? thermal.material_thermal_conductance(area_m2, thickness_m, temperature) : null
	var/datum/material/insulator = material_for_role(MATERIAL_ROLE_INSULATION)
	if(!isnull(conductance) && insulator)
		conductance *= clamp(1 - insulator.thermal_insulation / 110, 0.02, 1)
	return conductance

/obj/proc/construction_pressure_limit(radius_mm, wall_thickness_mm, temperature)
	var/datum/material/structure = material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	return structure ? structure.material_pressure_limit(radius_mm, wall_thickness_mm, temperature) : null

/obj/proc/construction_radiation_transmission(thickness_mm)
	var/datum/material/jacket = material_for_role(MATERIAL_ROLE_JACKET) || material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	return jacket ? jacket.material_radiation_transmission(thickness_mm) : 1

/obj/examine(mob/user)
	. = ..()
	if(length(construction_materials))
		. += span_notice("Construction: [jointext(construction_summary(), "; ")].")
