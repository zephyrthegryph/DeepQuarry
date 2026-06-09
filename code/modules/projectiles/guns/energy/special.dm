/obj/item/gun/energy/ionrifle
	name = "ion rifle"
	desc = "The RayZar Mk60 EW Halicon is a man portable anti-armor weapon designed to disable mechanical threats, produced by NT. Not the best of its type."
	description_fluff = "RayZar is Ward-Takahashi’s main consumer weapons brand, known for producing and licensing a wide variety of specialist energy weapons of various types and quality primarily for the civilian market."
	icon = 'icons/obj/64x32guns_ch.dmi' // Gun Sprites
	icon_state = "ionrifle"
	item_state = "ionrifle"
	icon_expected_width = 64 // Gun Sprites
	wielded_item_state = "ionrifle-wielded"
	w_class = ITEMSIZE_HUGE //.
	force = 10
	slot_flags = SLOT_BACK
	projectile_type = /obj/item/projectile/ion

/obj/item/gun/energy/ionrifle/empty
	cell_type = null

/obj/item/gun/energy/ionrifle/pistol
	name = "ion pistol"
	desc = "The RayZar Mk63 EW Pan is a man portable anti-armor weapon designed to disable mechanical threats, produced by NT. This model sacrifices capacity for portability."
	icon = 'icons/obj/gun.dmi' // Gun Sprites
	icon_state = "ionpistol"
	item_state = null
	w_class = ITEMSIZE_NORMAL
	force = 5
	slot_flags = SLOT_BELT|SLOT_HOLSTER
	charge_cost = 480
	projectile_type = /obj/item/projectile/ion/pistol
	move_delay = 0 // Pistols have move_delay of 0

/obj/item/gun/energy/decloner
	name = "biological demolecularisor"
	desc = "A gun that discharges high amounts of controlled radiation to slowly break a target into component elements."
	icon = 'icons/obj/gun.dmi' // Gun Sprites
	icon_state = "decloner"
	item_state = "decloner"
	projectile_type = /obj/item/projectile/energy/declone

/obj/item/gun/energy/floragun
	name = "floral somatoray"
	desc = "A tool that discharges controlled radiation which induces mutation in plant cells."
	description_fluff = "The floral somatoray is a relatively recent invention of the NanoTrasen corporation, turning a process that once involved transferring plants to massive mutating racks, into a remote interface. Do not look directly into the transmission end."
	icon = 'icons/obj/gun.dmi'
	icon_state = "floramut100"
	item_state = "floramut"
	projectile_type = /obj/item/projectile/energy/floramut
	modifystate = "floramut"
	cell_type = /obj/item/cell/device/weapon/recharge
	battery_lock = 1

	var/datum/decl/plantgene/gene = null
	recoil_mode = 0
	var/obj/item/stock_parts/micro_laser/emitter

	firemodes = list(
		list(mode_name="induce mutations", projectile_type=/obj/item/projectile/energy/floramut, modifystate="floramut"),
		list(mode_name="increase yield", projectile_type=/obj/item/projectile/energy/florayield, modifystate="florayield"),
		list(mode_name="induce specific mutations", projectile_type=/obj/item/projectile/energy/floramut/gene, modifystate="floramut"),
		list(mode_name="prune reagents", projectile_type=/obj/item/projectile/energy/floraprune, modifystate="floramut"),
		)

/obj/item/gun/energy/floragun/Initialize(mapload)
	. = ..()
	emitter = new(src)

/obj/item/gun/energy/floragun/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "It has [emitter ? emitter : "no micro laser"] installed."

/obj/item/gun/energy/floragun/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/stock_parts/micro_laser))
		if(!emitter)
			user.drop_item()
			W.loc = src
			emitter = W
			to_chat(user, span_notice("You install a [emitter.name] in [src]."))
		else
			to_chat(user, span_notice("[src] already has a laser."))

	else if(W.has_tool_quality(TOOL_SCREWDRIVER))
		if(emitter)
			to_chat(user, span_notice("You remove the [emitter.name] from the [src]."))
			emitter.loc = get_turf(src.loc)
			playsound(src, W.usesound, 50, 1)
			emitter = null
			return
		else
			to_chat(user, span_notice("There is no micro laser in this [src]."))
			return

/obj/item/gun/energy/floragun/afterattack(obj/target, mob/user, adjacent_flag)
	//allow shooting into adjacent hydrotrays regardless of intent
	if(!emitter)
		to_chat(user, span_notice("The [src] has no laser! "))
		playsound(src, 'sound/weapons/empty.ogg', 50, 1)
		return
	if(adjacent_flag && istype(target,/obj/machinery/portable_atmospherics/hydroponics))
		user.visible_message(span_danger("\The [user] fires \the [src] into \the [target]!"))
		Fire(target,user)
		return
	..()

/obj/item/gun/energy/floragun/verb/select_gene()
	set name = "Select Gene"
	set category = "Object"
	set src in view(1)

	var/genemask = tgui_input_list(usr, "Choose a gene to modify.", "Gene Choice", SSplants.plant_gene_datums)

	if(!genemask)
		return

	gene = SSplants.plant_gene_datums[genemask]

	to_chat(usr, span_info("You set the [src]'s targeted genetic area to [genemask]."))

	return

/obj/item/gun/energy/floragun/consume_next_projectile()
	. = ..()
	var/obj/item/projectile/energy/floramut/gene/G = .
	var/obj/item/projectile/energy/florayield/GY = .
	var/obj/item/projectile/energy/floramut/GM = .
	var/obj/item/projectile/energy/floraprune/GP = .
	// Inserting the upgrade level of the gun to the projectile as there isn't a better way to do this.
	if(istype(G))
		G.gene = gene
		G.lasermod = emitter.rating
	else if(istype(GY))
		GY.lasermod = emitter.rating
	else if(istype(GM))
		GM.lasermod = emitter.rating
	else if(istype(GP))
		GP.lasermod = emitter.rating

/obj/item/gun/energy/meteorgun
	name = "meteor gun"
	desc = "For the love of god, make sure you're aiming this the right way!"
	icon_state = "riotgun"
	item_state = "c20r"
	slot_flags = SLOT_BELT|SLOT_BACK
	w_class = ITEMSIZE_HUGE //.
	projectile_type = /obj/item/projectile/meteor
	cell_type = /obj/item/cell/potato
	charge_cost = 100
	self_recharge = 1
	recharge_time = 5 //Time it takes for shots to recharge (in ticks)
	charge_meter = 0

/obj/item/gun/energy/meteorgun/pen
	name = "meteor pen"
	desc = "The pen is mightier than the sword."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "pen"
	item_state = "pen"
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_BELT


/obj/item/gun/energy/mindflayer
	name = "mind flayer"
	desc = "A custom-built weapon of some kind."
	icon_state = "xray"
	projectile_type = /obj/item/projectile/beam/mindflayer
	w_class = ITEMSIZE_HUGE //.

/obj/item/gun/energy/toxgun
	name = "phoron pistol"
	desc = "A specialized firearm designed to fire lethal bolts of phoron."
	icon = 'icons/obj/gun.dmi'
	icon_state = "toxgun"
	w_class = ITEMSIZE_NORMAL
	projectile_type = /obj/item/projectile/energy/phoron

/* Staves */

/obj/item/gun/energy/staff
	name = "staff of change"
	desc = "An artifact that spits bolts of coruscating energy which cause the target's very form to reshape itself."
	icon = 'icons/obj/gun.dmi'
	item_icons = null
	icon_state = "staffofchange"
	slot_flags = SLOT_BACK
	w_class = ITEMSIZE_LARGE
	charge_cost = 480
	projectile_type = /obj/item/projectile/change
	cell_type = /obj/item/cell/device/weapon/recharge
	battery_lock = 1
	charge_meter = 0

/obj/item/gun/energy/staff/special_check(mob/user)
	if((user.mind && !GLOB.wizards.is_antagonist(user.mind)))
		to_chat(user, span_warning("You focus your mind on \the [src], but nothing happens!"))
		return 0

	return ..()

/obj/item/gun/energy/staff/handle_click_empty(mob/user = null)
	if (user)
		user.visible_message("*fizzle*", span_danger("*fizzle*"))
	else
		src.visible_message("*fizzle*")
	playsound(src, 'sound/effects/sparks1.ogg', 100, 1)
/*
/obj/item/gun/energy/staff/animate
	name = "staff of animation"
	desc = "An artifact that spits bolts of life force, which causes objects which are hit by it to animate and come to life! This magic doesn't affect machines."
	projectile_type = /obj/item/projectile/animate
	charge_cost = 240
*/
/obj/item/gun/energy/staff/focus
	name = "mental focus"
	desc = "An artifact that channels the will of the user into destructive bolts of force. If you aren't careful with it, you might poke someone's brain out."
	icon = 'icons/obj/wizard.dmi'
	icon_state = "focus"
	slot_flags = SLOT_BACK
	projectile_type = /obj/item/projectile/forcebolt
	/*
	attack_self(mob/living/user as mob)
		if(projectile_type == "/obj/item/projectile/forcebolt")
			charge_cost = 400
			to_chat(user, span_warning("The [src.name] will now strike a small area."))
			projectile_type = "/obj/item/projectile/forcebolt/strong"
		else
			charge_cost = 200
			to_chat(user, span_warning("The [src.name] will now strike only a single person."))
			projectile_type = "/obj/item/projectile/forcebolt"
	*/

/obj/item/gun/energy/dakkalaser
	name = "suppression gun"
	desc = "A massive weapon designed to pressure the opposition by raining down a torrent of energy pellets."
	icon_state = "dakkalaser"
	item_state = "dakkalaser"
	wielded_item_state = "dakkalaser-wielded"
	w_class = ITEMSIZE_HUGE
	charge_cost = 24 // 100 shots, it's a spray and pray (to RNGesus) weapon.
	projectile_type = /obj/item/projectile/energy/blue_pellet
	cell_type = /obj/item/cell/device/weapon/recharge
	battery_lock = 1
	accuracy = 75 // Suppressive weapons don't work too well if there's no risk of being hit.
	burst_delay = 1 // Burst faster than average.

	firemodes = list(
		list(mode_name="single shot", burst = 1, burst_accuracy = list(75), dispersion = list(0), charge_cost = 24),
		list(mode_name="five shot burst", burst = 5, burst_accuracy = list(75,75,75,75,75), dispersion = list(1,1,1,1,1)),
		list(mode_name="ten shot burst", burst = 10, burst_accuracy = list(75,75,75,75,75,75,75,75,75,75), dispersion = list(2,2,2,2,2,2,2,2,2,2)),
		)

/obj/item/gun/energy/maghowitzer
	name = "portable MHD howitzer"
	desc = "A massive weapon designed to destroy fortifications with a stream of molten tungsten."
	description_fluff = "A weapon designed by joint cooperation of NanoTrasen, Hephaestus, and SCG scientists. Everything else is red tape and black highlighters."
	description_info = "This weapon requires a wind-up period before being able to fire. Clicking on a target will create a beam between you and its turf, starting the timer. Upon completion, it will fire at the designated location."
	icon_state = "mhdhowitzer"
	item_state = "mhdhowitzer"
	wielded_item_state = "mhdhowitzer-wielded"
	w_class = ITEMSIZE_HUGE

	charge_cost = 10000 // Uses large cells, can at max have 3 shots.
	projectile_type = /obj/item/projectile/beam/tungsten
	cell_type = /obj/item/cell/high
	accept_cell_type = /obj/item/cell

	accuracy = 75
	charge_meter = 0
	one_handed_penalty = 30

	var/power_cycle = FALSE

/obj/item/gun/energy/maghowitzer/proc/pick_random_target(turf/T)
	var/foundmob = FALSE
	var/foundmobs = list()
	for(var/mob/living/L in T.contents)
		foundmob = TRUE
		foundmobs += L
	if(foundmob)
		var/return_target = pick(foundmobs)
		return return_target
	return FALSE

/obj/item/gun/energy/maghowitzer/attack(mob/living/A, mob/living/user, target_zone, attack_modifier)
	if(power_cycle)
		to_chat(user, span_notice("\The [src] is already powering up!"))
		return ITEM_INTERACT_FAILURE
	var/turf/target_turf = get_turf(A)
	var/beameffect = user.Beam(target_turf,icon_state="sat_beam",icon='icons/effects/beam.dmi',time=31, maxdistance=10,beam_type=/obj/effect/ebeam,beam_sleep_time=3)
	if(beameffect)
		user.visible_message(span_cult("[user] aims \the [src] at \the [A]."))
	if(power_supply && power_supply.charge >= charge_cost) //Do a delay for pointblanking too.
		power_cycle = TRUE
		if(do_after(user, 3 SECONDS, target = src))
			if(A.loc == target_turf)
				..(A, user, target_zone, attack_modifier)
			else
				var/rand_target = pick_random_target(target_turf)
				if(rand_target)
					..(rand_target, user, target_zone, attack_modifier)
				else
					..(target_turf, user, target_zone, attack_modifier)
			return ITEM_INTERACT_SUCCESS
		else
			if(beameffect)
				qdel(beameffect)
		power_cycle = FALSE
	else
		..(A, user, target_zone, attack_modifier) //If it can't fire, just bash with no delay.

/obj/item/gun/energy/maghowitzer/afterattack(atom/A, mob/living/user, adjacent, params)
	if(power_cycle)
		to_chat(user, span_notice("\The [src] is already powering up!"))
		return 0

	var/turf/target_turf = get_turf(A)

	var/beameffect = user.Beam(target_turf,icon_state="sat_beam",icon='icons/effects/beam.dmi',time=31, maxdistance=10,beam_type=/obj/effect/ebeam,beam_sleep_time=3)

	if(beameffect)
		user.visible_message(span_cult("[user] aims \the [src] at \the [A]."))

	if(!power_cycle)
		power_cycle = TRUE
		if(do_after(user, 3 SECONDS, target = src))
			if(A.loc == target_turf)
				..(A, user, adjacent, params)
			else
				var/rand_target = pick_random_target(target_turf)
				if(rand_target)
					..(rand_target, user, adjacent, params)
				else
					..(target_turf, user, adjacent, params)
		else
			if(beameffect)
				qdel(beameffect)
			handle_click_empty(user)
		power_cycle = FALSE
	else
		to_chat(user, span_notice("\The [src] is already powering up!"))


// === merged from special_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/gun/energy/ionrifle/pistol
	projectile_type = /obj/item/projectile/ion/pistol // still packs a punch but no AoE
	w_class = ITEMSIZE_NORMAL //.
	move_delay = 0 // Pistols have move_delay of 0

/obj/item/gun/energy/ionrifle/weak
	projectile_type = /obj/item/projectile/ion/small

/obj/item/gun/energy/medigun //Adminspawn/ERT etc // CH edit - Changes ML3M  to NERD
	name = "directed restoration system"
	desc = "The BL-3 'Phoenix' is an adaptation on the NERD 'Medbeam' design that channels the power of the beam into a single healing laser. It is highly energy-inefficient, but its medical power cannot be denied."
	force = 5
	icon_state = "medbeam"
	item_state = "medbeam"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_guns_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_guns_vr.dmi',
		)
	slot_flags = SLOT_BELT
	accuracy = 100
	fire_delay = 12
	fire_sound = 'sound/weapons/eluger.ogg'

	projectile_type = /obj/item/projectile/beam/medigun

	accept_cell_type = /obj/item/cell
	cell_type = /obj/item/cell/high
	charge_cost = 2500

/obj/item/gun/energy/bfgtaser
	name = "9000-series Ball Lightning Taser"
	desc = "The brainchild of Hephaestus Industries Civil Pacification Division, the BLT-9000 was intended for riot control but despite enthusiastic interest from law-enforcement agencies across the Commonwealth and beyond, its indiscriminate nature led to it being banned from civilian use in virtually all jurisdictions. As a result, most pieces are found in the hands of collectors."
	icon_state = "BFG"
	fire_sound = 'sound/effects/phasein.ogg'
	item_state = "mhdhowitzer"
	wielded_item_state = "mhdhowitzer-wielded" //Placeholder
	slot_flags = SLOT_BELT|SLOT_BACK
	projectile_type = /obj/item/projectile/bullet/BFGtaser
	fire_delay = 20
	w_class = ITEMSIZE_LARGE
	one_handed_penalty = 90 // The thing's heavy and huge.
	accuracy = 45
	charge_cost = 2400 //yes, this bad boy empties an entire weapon cell in one shot. What of it?
	var/spinning_up = FALSE

/obj/item/gun/energy/bfgtaser/Fire(atom/target, mob/living/user, clickparams, pointblank=0, reflex=0)
	if(spinning_up)
		return
	if(!power_supply || !power_supply.check_charge(charge_cost))
		handle_click_empty(user)
		return

	playsound(src, 'sound/weapons/chargeup.ogg', 100, 1)
	spinning_up = TRUE
	update_icon()
	user.visible_message(span_notice("[user] starts charging the [src]!"), \
						span_notice("You start charging the [src]!"))
	if(do_after(user, 8, target = src))
		spinning_up = FALSE
		..()
	else
		spinning_up = FALSE

/obj/item/projectile/beam/stun/weak/BFG
	fire_sound = 'sound/effects/sparks6.ogg'
	hitsound = 'sound/effects/sparks4.ogg'
	hitsound_wall = 'sound/effects/sparks7.ogg'

/obj/item/projectile/bullet/BFGtaser
	name = "lightning ball"
	icon = 'icons/obj/projectiles_vr.dmi'
	icon_state = "minitesla"
	speed=5
	damage = 100
	damage_type = AGONY
	check_armour = "energy"
	embed_chance = 0
	hitsound = 'sound/weapons/zapbang.ogg'
	hitsound_wall = 'sound/weapons/effects/searwall.ogg'
	var/zaptype = /obj/item/projectile/beam/stun/weak/BFG

/obj/item/projectile/bullet/BFGtaser/process()
	var/list/victims = list()
	for(var/mob/living/M in living_mobs(world.view))
		if(M != firer)
			victims += M
	if(LAZYLEN(victims))
		var/target = pick(victims)
		var/obj/item/projectile/P = new zaptype(src.loc)
		P.launch_projectile_from_turf(target = target, target_zone = null, user = firer, params = null, angle_override = null, forced_spread = 0)
	..()

/obj/item/projectile/bullet/BFGtaser/on_hit()
	var/list/victims = list()
	for(var/mob/living/M in living_mobs(world.view))
		if(M != firer)
			victims += M
	if(LAZYLEN(victims))
		for(var/target in victims)
			var/obj/item/projectile/P = new zaptype(src.loc)
			P.launch_projectile_from_turf(target = target, target_zone = null, user = firer, params = null, angle_override = null, forced_spread = 0)
	..()


// === merged from special_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/gun/energy/medigun/mounted
	name = "mounted directed restoration system"
	self_recharge = 1
	use_external_power = 1

/obj/item/gun/energy/taser/disabler/slow
	name = "plasma snare device"
	desc = "A modified disabler adjusted to impulse a target with a restrictive slowdown."
	icon_state = "disabler"
	projectile_type = /obj/item/projectile/energy/plasmastun/slow
	charge_cost = 480
	self_recharge = 1
	recharge_time = 3

/obj/item/projectile/energy/plasmastun/slow
	name = "plasma pulse"
	icon_state = "plasma_stun"
	fire_sound = 'sound/weapons/weaponsounds_laserstrong.ogg'
	armor_penetration = 10
	range = 9
	damage = 0
	agony = 0
	vacuum_traversal = 1
	hud_state = "plasma_rifle_blast"

/obj/item/projectile/energy/plasmastun/slow/on_hit(atom/target)
	if(isliving(target))
		var/mob/living/L = target
		L.add_modifier(/datum/modifier/entangled, 10 SECONDS)


/obj/item/gun/energy/rednetgun
	name = "experimental capture gun"
	desc = "An experimental gun, in efforts to expand net gun technology. Utilizing eletronic interferance and a \
	heat aura it in theory stops the subject from fighting back."
	icon_state = "goldstunrevolver"
	item_state = null
	projectile_type = /obj/item/projectile/energy/rednet
	charge_cost = 1440 //so a taser has 15 shots at 480 and I want five but this feels goofy


/obj/item/projectile/energy/rednet
	name = "expirmental energy net"
	icon_state = "toxin"
	damage = 0
	check_armour = "energy"
	hud_state = "pistol_tranq"
	fire_sound = 'sound/weapons/Taser.ogg'
	nodamage = 1
	modifier_type_to_apply = /datum/modifier/rednet
	modifier_duration = 0.5 MINUTE
	speed = 1.5

/datum/modifier/rednet
	mob_overlay_state = "red_electricity_constant"
	slowdown = 1

/obj/item/projectile/bullet/magnetic/supercannon
	name = "railcannon slug"
	icon_state = "fuel-supermatter"
	damage = 1500 //You are not being defibbed from this.
	weaken = 2
	armor_penetration = 100
	penetrating = 1500 //Theoretically, this shouldn't stop flying for a while, unless someoneI t lines it up with a wall or fires it into a mountain.
	range = 200
	hud_state = "rocket_thermobaric"
	speed = 0.2

/obj/item/projectile/bullet/magnetic/supercannon/on_hit(atom/target, blocked = 0, def_zone = null)
	if(istype(target,/turf/simulated/wall) || istype(target,/mob/living))
		target.visible_message(span_danger("The [src] burns a perfect hole through \the [target] with a blinding flash!"))
		playsound(target, 'sound/effects/teleport.ogg', 40, 0)
	return ..(target, blocked, def_zone)

/obj/item/projectile/bullet/magnetic/supercannon/Bump(atom/target) //On hit doesnt work on turfs, gotta snowflake it. Why is on_hit() called by the target, NOT the proj?????
	..()
	if(istype(target,/turf/simulated/wall))
		var/turf/simulated/wall/B = target
		B.dismantle_wall(1,1,0)

/obj/item/projectile/bullet/magnetic/supercannon/check_penetrate()
	return 1


/obj/item/gun/energy/supercannon
	name = "Super-Rail Cannon"
	desc = "This weapon seems to be vibrating with a barely containable energy, with no charging ports or battery ports in sight, you only have a singlular shot of this. Ever"
	icon = 'icons/obj/guns/supercannon/supercannon.dmi'
	icon_state = "supercannon"
	item_state = "supercannon"
	wielded_item_state = "supercannon-wielded"
	w_class = ITEMSIZE_HUGE
	fire_sound = 'sound/weapons/Gunshot_cannon.ogg'
	slot_flags = SLOT_BELT|SLOT_BACK
	charge_cost = 2400 //You got 1 shot...
	self_recharge = TRUE
	recharge_time = 6 HOURS //This is how to get around rechargers being able to recharge it, I dont wanna rewrite base level code
	projectile_type = /obj/item/projectile/bullet/magnetic/supercannon //Fuck you.
	cell_type = /obj/item/cell/device/weapon
	battery_lock = 1
	force = 15 //pretty robust
	one_handed_penalty = 90
	item_icons = list(
		slot_l_hand_str = 'icons/obj/guns/supercannon/lefthand_guns.dmi',
		slot_r_hand_str = 'icons/obj/guns/supercannon/righthand_guns.dmi',
		)
