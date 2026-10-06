/obj/mecha/combat/phazon
	desc = "An exosuit which can only be described as 'WTF?'."
	name = "Phazon"
	icon_state = "phazon"
	initial_icon = "phazon"
	step_in = 1
	dir_in = 1 //Facing North.
	step_energy_drain = 3
	max_integrity = 250 // Don't forget to update the /old variant if you change this number.
	max_temperature = 25000
	infra_luminosity = 3
	wreckage = /obj/effect/decal/mecha_wreckage/phazon
	add_req_access = 1
	internal_damage_threshold = 25
	force = 15
	max_equip = 4

// start
	max_hull_equip = 2
	max_weapon_equip = 2
	max_utility_equip = 3
	max_universal_equip = 2
	max_special_equip = 2
// end
	encumbrance_gap = 2


	cloak_possible = FALSE // Cloaking is too much for something like this, and is moderately useless anyway.
	phasing_possible = TRUE
	switch_dmg_type_possible = TRUE

TYPE_TABLE(/obj/mecha/combat/phazon, mecha_starting_components, list( \
		/obj/item/mecha_parts/component/hull, /* normal hull */ \
		/obj/item/mecha_parts/component/actuator, \
		/obj/item/mecha_parts/component/armor/alien, \
		/obj/item/mecha_parts/component/gas, \
		/obj/item/mecha_parts/component/electrical \
		))

TYPE_TABLE_DECLARE(/obj/mecha/combat/phazon, phazon_damage_absorption, list("brute"=0.7,"fire"=0.7,"bullet"=0.7,"laser"=0.7,"energy"=0.7,"bomb"=0.7))

TYPE_TABLE(/obj/mecha/combat/phazon/equipped, mecha_starting_equipment, list( \
		/obj/item/mecha_parts/mecha_equipment/tool/rcd, \
		/obj/item/mecha_parts/mecha_equipment/gravcatapult \
		))

/* Leaving this until we are really sure we don't need it for reference.
/obj/mecha/combat/phazon/proc/phase_recharged()
	can_phase = TRUE

/obj/mecha/combat/phazon/Bump(atom/obstacle)
	if(phasing && get_charge()>=phasing_energy_drain)
		if(can_phase)
			can_phase = FALSE
			flick("[initial_icon]-phase", src)
			src.loc = get_step(src,src.dir)
			src.use_power(phasing_energy_drain)
			after(src, step_in*3, PROC_REF(phase_recharged))
	else
		. = ..()
	return
*/


/obj/mecha/combat/phazon/get_commands()
	var/output = {"<div class='wr'>
						<div class='header'>Special</div>
						<div class='links'>
						<a href='byond://?src=\ref[src];phasing=1'><span id="phasing_command">[phasing?"Dis":"En"]able phasing</span></a><br>
						<a href='byond://?src=\ref[src];switch_damtype=1'>Change melee damage type</a><br>
						</div>
						</div>
						"}
	output += ..()
	return output



/obj/mecha/combat/phazon/janus
	name = "Phazon Prototype Janus Class"
	desc = "An exosuit which a more crude civilization such as yours might describe as WTF?."
	description_fluff = "An incredibly high-tech exosuit constructed out of salvaged alien and cutting-edge modern technology.\
	This machine, theoretically, is capable of travelling through time, however due to the strange nature of its miniaturized \
	supermatter-fueled bluespace drive, it is uncertain how this ability manifests."
	icon_state = "janus"
	initial_icon = "janus"
	step_in = 1
	dir_in = 1 //Facing North.
	step_energy_drain = 3
	max_integrity = 350
	max_temperature = 10000
	infra_luminosity = 3
	wreckage = /obj/effect/decal/mecha_wreckage/janus
	internal_damage_threshold = 25
	force = 20
	phasing_energy_drain = 300
// start
	max_hull_equip = 2
	max_weapon_equip = 3
	max_utility_equip = 3
	max_universal_equip = 4
	max_special_equip = 2
// end
	phasing_possible = TRUE
	switch_dmg_type_possible = TRUE
	cloak_possible = TRUE // Allows Janus to cloak.

TYPE_TABLE(/obj/mecha/combat/phazon/janus, phazon_damage_absorption, list("brute"=0.6,"fire"=0.7,"bullet"=0.7,"laser"=0.9,"energy"=0.7,"bomb"=0.5))

/obj/mecha/combat/phazon/janus/take_damage(amount, type="brute")
	..()
	if(phasing)
		phasing = FALSE
		radiation_pulse(
			src,
			max_range = 7,
			threshold = RAD_HEAVY_INSULATION,
			chance = URANIUM_IRRADIATION_CHANCE * 5,
			strength = 250
		)
		log_append_to_last("WARNING: BLUESPACE DRIVE INSTABILITY DETECTED. DISABLING DRIVE.",1)
		visible_message(span_alien("The [src.name] appears to flicker, before its silhouette stabilizes!"))

	return

/// Phase armour: absorbs kinetic rounds and reflects beams before they reach the body.
/obj/mecha/combat/phazon/janus/negate_projectile(obj/item/projectile/Proj)
	if((Proj.damage && !Proj.nodamage) && !istype(Proj, /obj/item/projectile/beam) && prob(max(1, 33 - round(Proj.damage / 4))))
		src.occupant_message(span_alien("The armor absorbs the incoming projectile's force, negating it!"))
		src.visible_message(span_alien("The [src.name] absorbs the incoming projectile's force, negating it!"))
		src.log_append_to_last("Armor negated.")
		return TRUE
	else if((Proj.damage && !Proj.nodamage) && istype(Proj, /obj/item/projectile/beam) && prob(max(1, (50 - round((Proj.damage / 2) * TYPE_TABLE_GET(src, phazon_damage_absorption)["laser"])) * (1 - (Proj.armor_penetration / 100)))))	// Base 50% chance to deflect a beam,lowered by half the beam's damage scaled to laser absorption, then multiplied by the remaining percent of non-penetrated armor, with a minimum chance of 1%.
		src.occupant_message(span_alien("The armor reflects the incoming beam, negating it!"))
		src.visible_message(span_alien("The [src.name] reflects the incoming beam, negating it!"))
		src.log_append_to_last("Armor reflected.")
		return TRUE

	return ..()

/obj/mecha/combat/phazon/janus/dynattackby(obj/item/W as obj, mob/user as mob)
	if(prob(max(1, (50 - round((W.force / 2) * TYPE_TABLE_GET(src, phazon_damage_absorption)["brute"])) * (1 - (W.armor_penetration / 100)))))
		src.occupant_message(span_alien("The armor absorbs the incoming attack's force, negating it!"))
		src.visible_message(span_alien("The [src.name] absorbs the incoming attack's force, negating it!"))
		src.log_append_to_last("Armor absorbed.")
		return

	..()

/obj/mecha/combat/phazon/janus/query_damtype()
	open_request(src, /datum/prompt/choice, PROC_REF(janus_damtype_chosen), answerer = src?.slot_item(MECHA_SLOT_PILOT), title = "Damage Type", question = "Gauntlet Phase Emitter Mode", choices = list("Force","Energy","Stun"), buttons = TRUE, ask_flags = ASK_INSIDE, timeout = 0)

/obj/mecha/combat/phazon/janus/proc/janus_damtype_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/new_damtype = A.answer.value
	switch(new_damtype)
		if("Force")
			melee_injury_kind = INJURY_BLUNT
		if("Energy")
			melee_injury_kind = INJURY_BURN
		if("Stun")
			melee_injury_kind = INJURY_PAIN
	occupant_message("Melee damage type switched to [new_damtype]")
	return

//Meant for random spawns.
/obj/mecha/combat/phazon/old
	desc = "An exosuit which can only be described as 'WTF?'. This one is particularly worn looking and likely isn't as sturdy."

// ALLOW(init/INSTANCE_STATE): an old exosuit starts worn, damaged and with a random charge
/obj/mecha/combat/phazon/old/Initialize(mapload)
	. = ..()
	max_integrity = 150	//Just slightly worse.
	update_integrity(25)
	cell.charge = rand(0, (cell.charge/2))
