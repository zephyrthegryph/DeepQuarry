//This will likely drive me insane, but fuck it. Let's give it a shot. -k22
//This was heavily assisted by MoondancerPony
/obj/item/gun/energy/modular
	name = "modular weapon"
	desc = "You shouldn't be seeing this. Contact your local time-police station."
	icon_state = "mod_pistol"
	cell_type = /obj/item/cell/device/weapon
	charge_cost = 120

	var/max_components = 3 //How many components we can hold.
	var/capacitor_rating = 0 //How good are the capacitors inside us?
	var/laser_rating = 0 //How good are the lasers inside of us?
	var/manipulator_rating = 0 //How good are the manipulators inside us?
	var/assembled = 1 //Are we closed up?
	var/list/guncomponents //Generate our list of components.
	var/static/list/accepted_components = list(
		/obj/item/stock_parts/capacitor/,
		/obj/item/stock_parts/capacitor,
		/obj/item/stock_parts/capacitor,
		/obj/item/stock_parts/micro_laser/,
		/obj/item/stock_parts/micro_laser,
		/obj/item/stock_parts/micro_laser,
		/obj/item/stock_parts/manipulator/,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		)
	//Excessively long because it won't accept subtypes for some reason!


// Fitted parts sit in the gun's contents.
/obj/item/gun/energy/modular/ownership()
	. = ..()
	. += owns(nameof(guncomponents), policy = OWN_CONTAINED, is_list = TRUE)

/obj/item/gun/energy/modular/Initialize(mapload)
	. = ..()
	rel_add(src, nameof(guncomponents), new /obj/item/stock_parts/capacitor(src))
	rel_add(src, nameof(guncomponents), new /obj/item/stock_parts/micro_laser(src))
	rel_add(src, nameof(guncomponents), new /obj/item/stock_parts/manipulator(src))
	CheckParts()
	FireModeModify()

/obj/item/gun/energy/modular/CheckParts() //What parts do we have inside us, and how good are they?
	..()
	capacitor_rating = 0
	laser_rating = 0
	manipulator_rating = 0
	for(var/obj/item/stock_parts/capacitor/CA in guncomponents)
		capacitor_rating += CA.rating
	for(var/obj/item/stock_parts/micro_laser/ML in guncomponents)
		laser_rating += ML.rating
	for(var/obj/item/stock_parts/manipulator/MA in guncomponents)
		manipulator_rating += MA.rating
	FireModeModify()

/obj/item/gun/energy/modular/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	to_chat(user, span_notice("You [assembled ? "disassemble" : "assemble"] the gun."))
	assembled = !assembled
	playsound(src, tool.usesound, 50, 1)
	return OP_OK

CAPABILITIES(/obj/item/gun/energy/modular)
	op("use_crowbar", tool(TOOL_CROWBAR), wait(0), then(PROC_REF(crowbar_used)))

/obj/item/gun/energy/modular/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(assembled == 1)
		to_chat(user, span_warning("Disassemble the [src] first!"))
		return OP_OK
	for(var/obj/item/I in guncomponents)
		to_chat(user, span_notice("You remove the gun's components."))
		playsound(src, tool.usesound, 50, 1)
		rel_take(src, nameof(guncomponents), I)
		I.forceMove(get_turf(src))
		CheckParts()
	return OP_OK

/// Old attackby: the parent's first, then fitting a component.
/obj/item/gun/energy/modular/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	//Someone's attacking us, and it's not anything we have a special case for (i.e. a tool)
	. = ..()
	if(assembled) // can't put anything in
		return
	if(!(O.type in accepted_components))//check if we can accept it
		to_chat(user, span_warning("You can't add this to [src]!"))
		return
	if(length(guncomponents) >= max_components) //We have too many componenets and can't fit more.
		to_chat(user, span_warning("You can't add any more components!"))
		return
	if(istype(O, /obj/item/stock_parts/capacitor) && capacitor_rating == 5)
		to_chat(user, span_warning("You can't add any more capacitors!"))
		return
	if(!move_into(src, nameof(src.guncomponents), O, user))
		return
	to_chat(user, span_notice("You add a component to the [src]"))
	CheckParts()


/obj/item/gun/energy/modular/proc/FireModeModify() //Check our laser, manipulator, and capacitor ratings, adjust stun and lethal firemodes depending on laser / manipulator rating and burst size depending on capacitors.
	//check our lethal and stun ratings depending on laser and manipulator rating.
	var/burstmode = capacitor_rating
	var/beammode
	var/beammode_lethal
	var/chargecost
	var/chargecost_lethal

	if(laser_rating >= 15)
		beammode_lethal = /obj/item/projectile/beam/sniper
		beammode = /obj/item/projectile/beam/stun
		chargecost = 300
		chargecost_lethal = 600
	else if(laser_rating >= 10)
		beammode_lethal = /obj/item/projectile/beam/xray
		beammode = /obj/item/projectile/beam/stun
		chargecost = 300
		chargecost_lethal = 200
	else if(laser_rating == 8 && manipulator_rating == 5) //very specific set of combinations. No, you can't make a pulse rifle. Sorry research.
		beammode_lethal = /obj/item/projectile/beam/heavylaser
		beammode = /obj/item/projectile/beam/stun
		chargecost = 300
		chargecost_lethal = 600
	else if(laser_rating >= 5)
		beammode_lethal = /obj/item/projectile/beam/midlaser
		beammode = /obj/item/projectile/beam/stun/med
		chargecost = 180
		chargecost_lethal = 240
	else if(laser_rating < 5)
		beammode_lethal = /obj/item/projectile/beam/weaklaser
		beammode = /obj/item/projectile/beam/stun/weak
		chargecost = 100
		chargecost_lethal = 200

	rel_clear(src, nameof(firemodes))
	rel_add(src, nameof(firemodes), new /datum/firemode(src, list(mode_name="stun", projectile_type=beammode, charge_cost = chargecost)))
	rel_add(src, nameof(firemodes), new /datum/firemode(src, list(mode_name="lethal", projectile_type=beammode_lethal, charge_cost = chargecost_lethal)))
	rel_add(src, nameof(firemodes), new /datum/firemode(src, list(mode_name="[burstmode] shot stun", projectile_type=beammode, charge_cost = chargecost, burst = burstmode)))
	rel_add(src, nameof(firemodes), new /datum/firemode(src, list(mode_name="[burstmode] shot lethal", projectile_type=beammode_lethal, charge_cost = chargecost_lethal, burst = burstmode)))

/obj/item/gun/energy/modular/cell_fits(obj/item/cell/P)
	return istype(P, cell_type)

/obj/item/gun/energy/modular/cell_load_time(datum/act/op/A)
	return 1 SECOND

/obj/item/gun/energy/modular/pistol
	name = "modular pistol"
	icon_state = "mod_pistol"
	max_components = 6
	desc = "A bulky modular pistol frame. This only only accepts six parts."
	burst_delay = 2
	move_delay = 0 // Pistols have move_delay of 0

/obj/item/gun/energy/modular/carbine
	name = "modular carbine"
	icon_state = "mod_carbine"
	max_components = 8
	desc = "A modular version of the standard laser carbine. This one can hold 8 components."
	burst_delay = 2

/obj/item/gun/energy/modular/cannon
	name = "modular cannon"
	icon_state = "mod_cannon"
	max_components = 14
	desc = "Say hello, to my little friend!"
	one_handed_penalty = 4 //dual wielding = no.
	cell_type = /obj/item/cell //We're bigger. We can use much larger power cells.
	burst_delay = 4 //preventing extreme silliness.
