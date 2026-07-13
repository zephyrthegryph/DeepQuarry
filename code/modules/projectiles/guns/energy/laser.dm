/*
 * Laser Rifle
 */
/obj/item/gun/energy/laser
	name = "laser rifle"
	desc = "A Hephaestus Industries G40E rifle, designed to kill with concentrated energy blasts.  This variant has the ability to \
	switch between standard fire and a more efficent but weaker 'suppressive' fire."
	description_fluff = "The leading arms producer in the SCG, Hephaestus typically only uses its 'top level' branding for its military-grade equipment used by armed forces across human space."
	icon_state = "laser"
	item_state = "laser"
	wielded_item_state = "laser-wielded"
	fire_delay = 8
	slot_flags = SLOT_BELT|SLOT_BACK
	w_class = ITEMSIZE_LARGE //huge was dumb for this.
	force = 10
	matter = list(MAT_STEEL = 2000)
	projectile_type = /obj/item/projectile/beam/midlaser
	one_handed_penalty = 30

	firemodes = list(
		list(mode_name="normal", fire_delay=8, projectile_type=/obj/item/projectile/beam/midlaser, charge_cost = 240),
		list(mode_name="suppressive", fire_delay=5, projectile_type=/obj/item/projectile/beam/weaklaser, charge_cost = 60),
		)

/obj/item/gun/energy/laser/empty
	cell_type = null

/obj/item/gun/energy/laser/mounted
	self_recharge = 1
	use_external_power = 1
	one_handed_penalty = 0 // Not sure if two-handing gets checked for mounted weapons, but better safe than sorry.

/obj/item/gun/energy/laser/mounted/augment
	name = "arm-laser"
	desc = "A cruel malformation of a Hephaestus Industries G40E rifle, designed to kill with concentrated energy blasts, all while being stowable in the arm. This variant has the ability to \
	switch between standard fire and a more efficent but weaker 'suppressive' fire."
	use_external_power = FALSE
	use_organic_power = TRUE
	wielded_item_state = null
	item_state = "augment_laser"
	canremove = FALSE
	one_handed_penalty = 5
	battery_lock = 1

/obj/item/gun/energy/laser/practice
	name = "practice laser carbine"
	desc = "A modified version of the HI G40E, this one fires less concentrated energy bolts designed for target practice."
	projectile_type = /obj/item/projectile/beam/practice
	charge_cost = 48

	cell_type = /obj/item/cell/device

	firemodes = list(
		list(mode_name="normal", projectile_type=/obj/item/projectile/beam/practice, charge_cost = 48),
		list(mode_name="suppressive", projectile_type=/obj/item/projectile/beam/practice, charge_cost = 12),
		)

/*
 * Sleek Laser Rifle
 */
/obj/item/gun/energy/laser/sleek
	name = "\improper LR1 \"Shishi\""
	desc = "A Bishamonten Company LR1 \"Shishi\" rifle, a rare early 23rd century futurist design with a nonetheless timeless ability to kill."
	description_fluff = "Bisamonten was arms company that operated from roughly 2150-2280 - the height of the first extrasolar colonisation boom - before filing for \
	bankruptcy and selling off its assets to various companies that would go on to become today’s TSCs. Focused on sleek ‘futurist’ designs which have largely \
	fallen out of fashion but remain popular with collectors and people hoping to make some quick thalers from replica weapons. Their weapons tended to be form \
	over function - despite their flashy looks, most were completely unremarkable one way or another as weapons and used very standard firing mechanisms."
	icon_state = "lrifle"
	item_state = "lrifle"

/*
 * Retro Laser Rifle
 */
/obj/item/gun/energy/retro
	name = "retro laser"
	icon_state = "retro"
	item_state = "retro"
	desc = "A 23rd century model of the basic lasergun. Nevertheless, it is still quite deadly and easy to maintain, making it a favorite amongst pirates and other outlaws."
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_NORMAL
	projectile_type = /obj/item/projectile/beam
	fire_delay = 10 //old technology

/obj/item/gun/energy/retro/mounted
	self_recharge = 1
	use_external_power = 1

/obj/item/gun/energy/retro/empty
	icon_state = "retro"
	cell_type = null

/*
 * Alien Pistol
 */
/obj/item/gun/energy/alien
	name = "alien pistol"
	desc = "A weapon that works very similarly to a traditional energy weapon. How this came to be will likely be a mystery for the ages."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_pistol)
	icon = 'icons/obj/gun.dmi' // Override back to base gun.dmi
	icon_state = "alienpistol"
	item_state = "alienpistol"
	fire_delay = 9 // changed cooldown from 10 to 9.
	charge_cost = 380 // changed from 480 to 380. Aka five shots to six shots.

	projectile_type = /obj/item/projectile/beam/precursor // changed beam type
	cell_type = /obj/item/cell/device/weapon/recharge/alien // Self charges.
	modifystate = "alienpistol"
	battery_lock = 1 // adds battery lock.
	move_delay = 0 // Pistols have move_delay of 0

/datum/category_item/catalogue/anomalous/precursor_a/alien_pistol
	name = "Precursor Alpha Weapon - Appendageheld Laser"
	desc = "This object strongly resembles a weapon, and if one were to pull the \
	trigger located on the handle of the object, it would fire a deadly \
	laser at whatever it was pointed at. The beam fired appears to cause too \
	much damage to whatever it would hit to have served as a long ranged repair tool, \
	therefore this object was most likely designed to be a deadly weapon. If so, this \
	has several implications towards its creators;\
	<br><br>\
	Firstly, it implies that these precursors, at some point during their development, \
	had needed to defend themselves, or otherwise had a need to utilize violence, and \
	as such created better tools to do so. It is unclear if violence was employed against \
	themselves as a form of in-fighting, or if violence was exclusive to outside species.\
	<br><br>\
	Secondly, the shape and design of the weapon implies that the creators of this \
	weapon were able to grasp objects, and be able to manipulate the trigger independently \
	from merely holding onto the weapon, making certain types of appendages like tentacles be \
	unlikely.\
	<br><br>\
	An interesting note about this weapon, when compared to contemporary energy weapons, is \
	that this gun appears to be only slightly superior to modern laser weapons. The beam fired has \
	roughly the same ability to harm, yet the power consumption is higher than average \
	for a human-made energy side-arm. One possible explaination is that the creators of this \
	weapon, in their later years, had less of a need to optimize their capability for war, \
	and instead focused on other endeavors. Another explanation is that the vast age of the weapon \
	may have caused it to degrade, yet still remain functional at a reduced capability." //CHOMPedit changed description to be accurate with new projectile
	value = CATALOGUER_REWARD_MEDIUM

/*
 * Antique Laser Gun
 */
/obj/item/gun/energy/captain
	name = "antique laser gun"
	icon_state = "caplaser"
	item_state = "caplaser"
	desc = "A rare weapon, produced by the Lunar Arms Company around 2105 - one of humanity's first wholly extra-terrestrial weapon designs. It's certainly aged well."
	description_fluff = "The Lunar Arms Company was founded to provide home-grown arms to the Selene Federation from 2101-2108 during the Second Cold War, the conflict that sparked the \
	formation of the SCG. The LAC produced the first weapons wholly designed and produced outside of Earth. Post-war, the company relocated and rebranded as MarsTech, which survives \
	to this day as a major subsidiary of Hephaestus Industries."
	force = 5
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_NORMAL
	unacidable = TRUE
	projectile_type = /obj/item/projectile/beam
	fire_delay = 10		//Old pistol
	charge_cost = 480	//to compensate a bit for self-recharging
	cell_type = /obj/item/cell/device/weapon/recharge/captain
	battery_lock = 1
/* 	var/remainingshots = 0 // you may get a limited number of shots regardless of the charge // no
	var/failurechance = 0 //chance per shot of something going awry

/obj/item/gun/energy/captain/Initialize(mapload)
	//it's an antique and it's been sitting in a case, unmaintained, for who the hell knows how long - who knows what'll happen when you pull it out?
	..()
	//first, we decide, does it have a different type of beam? 75% of just being a 40-damage laser, 15% of being less or 0, 10% of being better
	projectile_type = pick(prob(1);/obj/item/projectile/beam/pulse,
						prob(2);/obj/item/projectile/beam/heavylaser/cannon,
						prob(2);/obj/item/projectile/beam/heavylaser,
						prob(5);/obj/item/projectile/beam/sniper,
						prob(45);/obj/item/projectile/beam,
						prob(10);/obj/item/projectile/beam/cyan,
						prob(10);/obj/item/projectile/beam/eluger,
						prob(10);/obj/item/projectile/beam/imperial,
						prob(10);/obj/item/projectile/beam/weaklaser,
						prob(5);/obj/item/projectile/beam/practice)
	//now, decide whether it has a shot limit and if so how many
	if(prob(50))
		remainingshots = rand(1,40)
	if(prob(50))
		failurechance = rand(1,5)

	//finally, update the description so it has a tell if it's gonna burn out on you
	if(remainingshots || failurechance)
		desc = "A rare weapon, produced by the Lunar Arms Company around 2105 - one of humanity's first wholly extra-terrestrial weapon designs. It's been reasonably well-preserved."

/obj/item/gun/energy/captain/special_check(mob/user)
	if(remainingshots)
		remainingshots -= 1
		if(!remainingshots) //you've shot your load, sonny
			burnout(user)
			return 0
	else if(prob(failurechance))
		malfunction(user)
		return 0
	return ..()

/obj/item/gun/energy/captain/proc/burnout(mob/user)
	//your gun is now rendered useless
	projectile_type = /obj/item/projectile/beam/practice //just in case you somehow manage to get it to fire again, its beam type is set to one that sucks
	power_supply.charge = 0
	power_supply.maxcharge = 1 //just to avoid div/0 runtimes
	desc = "A rare weapon, produced by the Lunar Arms Company around 2105 - one of humanity's first wholly extra-terrestrial weapon designs. It looks to have completely burned out."
	user.visible_message(span_warning("\The [src] erupts in a shower of sparks!"), span_danger("\the [src] bursts into a shower of sparks!"))
	var/turf/T = get_turf(src)
	var/datum/effect/effect/system/spark_spread/sparks = new /datum/effect/effect/system/spark_spread()
	sparks.set_up(2, 1, T)
	sparks.start()
	update_icon()

/obj/item/gun/energy/captain/proc/malfunction(mob/user)
	var/screwup = rand(1,10)
	switch(screwup)
		if(1 to 5) //50% of just draining the battery and making future malfunctions more likely
			power_supply.charge = 0
			var/turf/T = get_turf(src)
			var/datum/effect/effect/system/spark_spread/sparks = new /datum/effect/effect/system/spark_spread()
			sparks.set_up(2, 1, T)
			sparks.start()
			update_icon()
			user.visible_message(span_warning("\The [src] shorts out!"), span_danger("\the [src] shorts out!"))
			failurechance += rand(1,5)
			return
		if(6 to 7) //20% chance of weakening the beam type, possibly to uselessness
			var/obj/item/projectile/beam/B = new projectile_type
			switch(B.damage)
				if(0)
					return //can't weaken it any further
				if(1 to 15) //weaklaser becomes practice
					projectile_type = /obj/item/projectile/beam/practice
				if(16 to 40) //regular becomes weaklaser
					projectile_type = /obj/item/projectile/beam/weaklaser
				if(41 to 50) //sniper becomes regular
					projectile_type = /obj/item/projectile/beam
				if(51 to 60) //heavy becomes sniper
					projectile_type = /obj/item/projectile/beam/sniper
				if(61 to 80) //cannon becomes heavy
					projectile_type = /obj/item/projectile/beam/heavylaser
				if(81 to 100) //pulse becomes cannon
					projectile_type = /obj/item/projectile/beam/heavylaser/cannon
			user.visible_message(span_warning("\The [src] dims slightly!"), span_danger("\the [src] dims slightly!"))
			return
		if(8) //10% chance of reducing the number of shots you have left, or giving you a limit if there isn't one
			if(!remainingshots)
				remainingshots = rand(1,40)
			else
				remainingshots = min(1, round(remainingshots/2))
			user.visible_message(span_warning("\The [src] lets out a faint pop."), span_danger("\the [src] lets out a faint pop."))
		if(9) //10% chance of permanently reducing the cell's max charge
			power_supply.maxcharge = power_supply.maxcharge/2
			power_supply.charge = min(power_supply.charge, power_supply.maxcharge)
			user.visible_message(span_warning("\The [src] sparks,letting off a puff of smoke!"), span_danger("\the [src] sparks,letting off a puff of smoke!"))
			var/turf/T = get_turf(src)
			var/datum/effect/effect/system/spark_spread/sparks = new /datum/effect/effect/system/spark_spread()
			sparks.set_up(2, 1, T)
			sparks.start()
			update_icon()
		if(10) //10% chance of just straight-up breaking on the spot
			burnout(user)
			return
*/

/*
 * Laser Cannon
 */
/obj/item/gun/energy/lasercannon
	name = "laser cannon"
	desc = "With the laser cannon, the lasing medium is enclosed in a tube lined with uranium-235 and subjected to high neutron \
	flux in a nuclear reactor core. This incredible technology may help YOU achieve high excitation rates with small laser volumes!"
	icon = 'icons/obj/gun.dmi' // Override back to base gun.dmi
	icon_state = "lasercannon"
	item_state = null
	wielded_item_state = "mhdhowitzer-wielded" //Placeholder
	slot_flags = SLOT_BELT|SLOT_BACK
	projectile_type = /obj/item/projectile/beam/heavylaser/cannon
	battery_lock = 0 // This thing is worthless with this.
	fire_delay = 20
	w_class = ITEMSIZE_HUGE //. Lol a cannon used to be just large size? Are you kidding me? A CANNON. Deserves this.
	one_handed_penalty = 90 // The thing's heavy and huge.
	accuracy = 45
	charge_cost = 400 //. Let's give this thing some more shots, seeing as it needs to be recharged at a charger - Most everything else is cheaper on charge cost now or smaller, this can stay the same, but with replacable batteries.

/obj/item/gun/energy/lasercannon/mounted
	name = "mounted laser cannon"
	self_recharge = 1
	use_external_power = 1
	recharge_time = 10
	accuracy = 0 // Mounted cannons are just fine the way they are.
	one_handed_penalty = 0 // Not sure if two-handing gets checked for mounted weapons, but better safe than sorry.
	projectile_type = /obj/item/projectile/beam/heavylaser
	charge_cost = 400
	fire_delay = 20

/*
 * X-ray
 */
/obj/item/gun/energy/xray
	name = "xray laser gun"
	desc = "A high-power laser gun capable of expelling concentrated xray blasts, which are able to penetrate matter easier than \
	standard photonic beams, resulting in an effective 'anti-armor' energy weapon."
	icon = 'icons/obj/gun.dmi' // Override back to base gun.dmi
	icon_state = "xray"
	item_state = "xray"
	projectile_type = /obj/item/projectile/beam/xray
	charge_cost = 200
	w_class = ITEMSIZE_LARGE //. - huge is too big, this thing hits for 25

/*
 * Marksman Rifle
 */
/obj/item/gun/energy/sniperrifle
	name = "marksman energy rifle"
	desc = "The HI DMR 9E is an older design of Hephaestus Industries. A designated marksman rifle capable of shooting powerful \
	ionized beams, this is a weapon to kill from a distance."
	description_fluff = "The leading arms producer in the SCG, Hephaestus typically only uses its 'top level' branding for its military-grade equipment used by armed forces across human space."
	icon = 'icons/obj/64x32guns_ch.dmi' // Gun Sprites
	icon_expected_width = 64 // Gun Sprites
	icon_state = "sniper"
	item_state = "sniper"
	item_state_slots = list(slot_r_hand_str = "lsniper", slot_l_hand_str = "lsniper")
	wielded_item_state = "lsniper-wielded"
	projectile_type = /obj/item/projectile/beam/sniper
	slot_flags = SLOT_BACK
	actions_types = list(/datum/action/item_action/use_scope)
	//Begin CHOMPstation Edit for making this thing not trash
	//battery_lock = 0
	charge_cost = 360
	fire_delay = 40
	force = 10
	w_class = ITEMSIZE_HUGE // So it can't fit in a backpack.
	accuracy = -30 //shooting at the hip
	scoped_accuracy = 100
	one_handed_penalty = 60 // The weapon itself is heavy, and the long barrel makes it hard to hold steady with just one hand.
	//End .

/obj/item/gun/energy/sniperrifle/ui_action_click(mob/user, actiontype)
	scope()

/obj/item/gun/energy/sniperrifle/verb/scope()
	set category = "Object"
	set name = "Use Scope"
	set popup_menu = 1

	toggle_scope(2.0)

/*
 * Laser Scattergun (proof of concept)
 */
/obj/item/gun/energy/lasershotgun
	name = "laser scattergun"
	icon = 'icons/obj/energygun.dmi'
	item_state = "laser"
	icon_state = "scatter"
	desc = "A strange Almachi weapon, utilizing a refracting prism to turn a single laser blast into a diverging cluster."

	projectile_type = /obj/item/projectile/scatter/laser
	w_class = ITEMSIZE_HUGE //.
	slot_flags = SLOT_BELT|SLOT_BACK //because you can still holster it despite it not fitting in a backpack.


/*
 * Imperial Pistol
 */
/obj/item/gun/energy/imperial
	name = "imperial energy pistol"
	desc = "An elegant weapon developed by the Imperium Auream. Their weaponsmiths have cleverly found a way to make a gun that \
	is only about the size of an average energy pistol, yet with the fire power of a laser carbine."
	icon_override = 'icons/obj/gun.dmi'
	icon_state = "ge_pistol"
	item_state = "ge_pistol"
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_NORMAL
	force = 10
	matter = list(MAT_STEEL = 2000)
	fire_sound = 'sound/weapons/mandalorian.ogg'
	projectile_type = /obj/item/projectile/beam/imperial

/*
 * Mining-Laser Rifle
 */
/obj/item/gun/energy/mininglaser
	name = "mining-laser rifle"
	desc = "An industrial grade mining laser. Comes with a built-in 'stun' mode for encounters with local wildlife."
	icon_state = "mininglaser"
	item_state = "mininglaser"
	fire_delay = 8
	slot_flags = SLOT_BELT|SLOT_BACK
	w_class = ITEMSIZE_LARGE
	force = 15
	matter = list(MAT_STEEL = 2000)
	projectile_type = /obj/item/projectile/beam/mininglaser

	firemodes = list(
		list(mode_name="mining", fire_delay=8, projectile_type=/obj/item/projectile/beam/mininglaser, charge_cost = 200),
		list(mode_name="deter", fire_delay=5, projectile_type=/obj/item/projectile/beam/weaklaser, charge_cost = 80),
		)

/*
 * Old Laser Rifle
 */
/obj/item/gun/energy/laser/old
	name = "vintage laser rifle"
	desc = "A Hephaestus Industries G32E rifle, designed to kill with concentrated energy blasts. This older model laser rifle only has one firemode."
	description_fluff = "The leading arms producer in the SCG, Hephaestus typically only uses its 'top level' branding for its military-grade \
	equipment used by armed forces across human space."
	icon_state = "oldlaser"
	item_state = "laser"
	fire_delay = 6
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_NORMAL
	force = 8
	matter = list(MAT_STEEL = 1500)
	projectile_type = /obj/item/projectile/beam/midlaser

/*
 * Mono-Rifle
 */
/obj/item/gun/energy/monorifle
	name = "antique mono-rifle"
	desc = "An old model laser rifle with a nice wood finish. This weapon was only designed to fire once before requiring a recharge."
	description_fluff = "Modeled after ancient hunting rifles designs, this rifle was dubbed the 'Rainy Day Special' by some, due to its use as the \
	choice \"fight-stopper\" of barkeeps. One shot is all it takes... so they say."
	icon_state = "mono"
	item_state = "shotgun"
	projectile_type = /obj/item/projectile/beam/sniper
	slot_flags = SLOT_BACK
	actions_types = list(/datum/action/item_action/aim_down_sights)
	charge_cost = 2400
	fire_delay = 20
	force = 8
	w_class = ITEMSIZE_HUGE //.
	accuracy = 10
	scoped_accuracy = 15
	charge_meter = FALSE
	var/scope_multiplier = 1.5

/obj/item/gun/energy/monorifle/ui_action_click(mob/user, actiontype)
	sights()

/obj/item/gun/energy/monorifle/verb/sights()
	set category = "Object"
	set name = "Aim Down Sights"
	set popup_menu = 1

	toggle_scope(scope_multiplier)

/obj/item/gun/energy/monorifle/combat
	name = "combat mono-rifle"
	desc = "A modernized version of the classic mono-rifle. This one has an optimized capacitor bank that allows the rifle to fire twice before requiring a recharge."
	description_fluff = "A modern design of a classic rifle produced by a small arms company operating out of Saint Columbia. It was based on the \
	antique mono-rifle design that was dubbed the 'Rainy Day Special' by many of its users."
	icon = 'icons/obj/gun.dmi'
	icon_state = "cmono"
	item_state = "cshotgun"
	charge_cost = 1200
	force = 12
	accuracy = 0
	scoped_accuracy = 20

/obj/item/gun/energy/zip
	name = "Zip-Las"
	desc = "A homemade (and somehow safe) laser gun designed around shooting single powerful laser beam draining the cell entirely. Better not miss and better have spare cells."
	icon = 'icons/obj/gun.dmi'
	icon_state = "ziplas"
	item_state = "ziplas"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT|SLOT_BACK
	charge_cost = 1500 //You got 1 shot...
	projectile_type = /obj/item/projectile/beam/heavylaser //But it hurts a lot
	cell_type = /obj/item/cell/device/weapon

/obj/item/gun/energy/zip/craftable
	battery_lock = 1 //makeshift gun has flaws


// === merged from laser_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/gun/energy/laser
	icon = 'icons/obj/64x32guns_ch.dmi'
	icon_state = "lcarbine"
	name = "NT LC-525 Laser Rifle"
	desc = "A relatively new, mass produced Nanotrasen laser carbine designed to kill with concentrated energy blasts. Just like the G40E, it has two firemodes, standard, and suppressive, which fires more efficent but weaker beams."
	icon_expected_width = 64
	var/is64x32 = TRUE
	var/is64x32_override = FALSE
	var/is_picked_up = FALSE

/obj/item/gun/energy/laser/equipped(mob/living/user, slot)
	. = ..()
	is_picked_up = TRUE
	update_transform()

/obj/item/gun/energy/laser/pickup()
	. = ..()
	is_picked_up = TRUE
	update_transform()

/obj/item/gun/energy/laser/dropped(mob/user, equipping, slot)
	. = ..()
	if(!istype(loc,/mob/living))
		is_picked_up = FALSE
	update_transform()

/obj/item/gun/energy/laser/Initialize(mapload)
	. = ..()
	if((!(type == /obj/item/gun/energy/laser)) && !is64x32_override)
		is64x32 = FALSE
		if(icon_expected_width == 64)
			icon_expected_width = 32
		if(icon == 'icons/obj/64x32guns_ch.dmi')
			icon = 'icons/obj/gun.dmi'
	if(is64x32)
		update_transform()

/obj/item/gun/energy/laser/update_transform()
	. = ..()
	if(is64x32)
		if(is_picked_up)
			transform = transform.Turn(-45)
		transform = transform.Translate(-16,0)

/obj/item/gun/energy/laser/empty
	is64x32_override = TRUE

/obj/item/gun/energy/laser/mounted
	is64x32_override = TRUE

/obj/item/gun/energy/laser/practice
	is64x32_override = TRUE

/obj/item/gun/energy/laser/vepr
	name = "WKHM 'Vepr'"
	desc = "The Vepr lasgun, in 40 Watt range. One of the most robust laser rifles out there, but not one that's commonly seen. This piece is WKHM's latest entry into the energy weapon market, competing with the Hephaestus Industries G40E. Uses its own proprietary energy cells. It has three settings, standard, suppressive, and burst. This one bears the 'WKHM Adamant' arkship's production stamp."
	description_fluff = "WKHM, is a minor arms company that has been around for quite some time, established in 2408. Known for being one of the many suppliers of weapons to dangerous worlds on the rim, and a part of the FTU. They produce a large variety of firearms, strike craft, and armored vehicles to fufill various their various contracts, and are largely migrant, moving wherever the money is. Found almost entirely on mobile production ships and various escort craft. Identifiable by their logo, a red Omega symbol with a black or white W in the middle. The sheer quantity of their firearms produced ensures they can be found.. just about anywhere, and they are very sought after by pirates for their reliability."
	icon_expected_width = 64
	icon_state = "vepr"
	firemodes = list(
		list(mode_name="normal", fire_delay=8, projectile_type=/obj/item/projectile/beam/midlaser, charge_cost = 240),
		list(mode_name="suppressive", fire_delay=5, projectile_type=/obj/item/projectile/beam/weaklaser, charge_cost = 60),
		list(mode_name="burst", burst=3, fire_delay=null, move_delay=4, burst_accuracy=list(0,0,0), dispersion=list(0.0, 0.2, 0.5), projectile_type=/obj/item/projectile/beam/burstlaser, charge_cost = 200),
		)
	force = 8
	w_class = ITEMSIZE_HUGE //Probably gonna make it a rifle sooner or later //and so I did.
	slot_flags = SLOT_BELT|SLOT_BACK //. Let's make it so that if it doesn't fit in a backpack, it doesn't fit in a holster either.
	is64x32_override = TRUE
	accept_cell_type = /obj/item/cell/vepr
	cell_type = /obj/item/cell/vepr

/obj/item/cell/vepr
	name = "VEPR cell"
	icon = 'icons/obj/ammo_ch.dmi'
	icon_state = "veprcell"
	item_state = "egg6"
	w_class = ITEMSIZE_SMALL
	maxcharge = 7200
	charge = 7200
	charge_amount = 20
	matter = list(MAT_METAL = 350, MAT_GLASS = 50)
	preserve_item = 1

/obj/item/gun/energy/tommylaser
	name = "M-2421 'Tommy-Laser'"
	desc = "A automatic laser weapon resembling a Tommy-Gun. Designed by Cybersun Industries to be a man portable supressive fire laser weapon."
	icon_state = "etommy"
	item_state = "etommy"
	w_class = ITEMSIZE_LARGE
	slot_flags = SLOT_BACK
	charge_cost = 60 // 40 shots, lay down the firepower
	projectile_type = /obj/item/projectile/beam/weaklaser
	cell_type = /obj/item/cell/device/weapon

	firemodes = list(
		list(mode_name="single shot", burst = 1, fire_delay=4, move_delay=null, burst_accuracy = null, dispersion = null),
		list(mode_name="three shot bursts", burst=3, fire_delay=10 , move_delay=4,    burst_accuracy=list(65,65,65), dispersion=list(1,1,1)),
		list(mode_name="short bursts",	burst=5, fire_delay=10 ,move_delay=6, burst_accuracy = list(65,65,65,65,65), dispersion = list(4,4,4,4,4)),
		)

/obj/item/gun/energy/vepr/plasma
	name = "WKHM 'Vepr-Prisma'"
	desc = "The Vepr-Prisma plasma rifle, in 40 Watt range. A very robust version of the Vepr lasrifle, made to fire energized bolts of plasma. The Vepr-Prisma is very uncommon, reserved mainly for W-K's internal security forces, and organizations with lots of money to spend. Lacks a burst mode, but it probably doesn't need it. This one bears the 'WKHM Adamant' arkship's production stamp."
	description_fluff = "WKHM, is a minor arms company that has been around for quite some time, established in 2408. Known for being one of the many suppliers of weapons to dangerous worlds on the rim, and a part of the FTU. They produce a large variety of firearms, strike craft, and armored vehicles to fufill various their various contracts, and are largely migrant, moving wherever the money is. Found almost entirely on mobile production ships and various escort craft. Identifiable by their logo, a red Omega symbol with a black or white W in the middle. The sheer quantity of their firearms produced ensures they can be found.. just about anywhere, and they are very sought after by pirates for their reliability."
	icon_expected_width = 64
	icon = 'icons/obj/64x32guns_ch.dmi'
	icon_state = "vepr"
	fire_delay = 0.5
	projectile_type = /obj/item/projectile/energy/plasma/vepr
	force = 8
	w_class = ITEMSIZE_HUGE //Probably gonna make it a rifle sooner or later //and so I did.
	slot_flags = SLOT_BELT|SLOT_BACK //. Let's make it so that if it doesn't fit in a backpack, it doesn't fit in a holster either.
	var/is64x32_override = TRUE
	accept_cell_type = /obj/item/cell/vepr
	cell_type = /obj/item/cell/vepr


// === merged from laser_chomp.dm during hard-fork de-suffix (manually verified: all-new types/defines, no base re-open) ===
/obj/item/gun/energy/floragun
	charge_cost = 80

/*
//Combat refactor walk-back
/obj/item/gun/energy
	charge_cost = 80

/obj/item/gun/energy/laser
	firemodes = list(
		list(mode_name="normal", fire_delay=8, projectile_type=/obj/item/projectile/beam/midlaser, charge_cost = 80),
		list(mode_name="suppressive", fire_delay=5, projectile_type=/obj/item/projectile/beam/weaklaser, charge_cost = 20),
		)

/obj/item/gun/energy/lasercannon //This is me trying to make ammo worth while but the cannon...is a cannon.
	charge_cost = 300

/obj/item/gun/energy/lasercannon/mounted
	charge_cost = 300

/obj/item/gun/energy/xray
	charge_cost = 65

/obj/item/gun/energy/sniperrifle
	charge_cost = 120

/obj/item/gun/energy/mininglaser
	firemodes = list(
		list(mode_name="mining", fire_delay=8, projectile_type=/obj/item/projectile/beam/mininglaser, charge_cost = 65),
		list(mode_name="deter", fire_delay=5, projectile_type=/obj/item/projectile/beam/weaklaser, charge_cost = 25),
		)

/obj/item/gun/energy/laser/vepr
	firemodes = list(
		list(mode_name="normal", fire_delay=8, projectile_type=/obj/item/projectile/beam/midlaser, charge_cost = 80),
		list(mode_name="suppressive", fire_delay=5, projectile_type=/obj/item/projectile/beam/weaklaser, charge_cost = 20),
		list(mode_name="burst", burst=3, fire_delay=null, move_delay=4, burst_accuracy=list(0,0,0), dispersion=list(0.0, 0.2, 0.5), projectile_type=/obj/item/projectile/beam/burstlaser, charge_cost = 65),
		)

/obj/item/gun/energy/gun
	firemodes = list(
		list(mode_name="stun", projectile_type=/obj/item/projectile/beam/stun/med, modifystate="egunstun", fire_sound='sound/weapons/taser.ogg', charge_cost = 80),
		list(mode_name="lethal", projectile_type=/obj/item/projectile/beam, modifystate="egunkill", fire_sound='sound/weapons/Laser.ogg', charge_cost = 160),
		)

/obj/item/gun/energy/gun/rifle
	firemodes = list(
		list(mode_name="stun", projectile_type=/obj/item/projectile/beam/stun, modifystate="riflestun", fire_sound='sound/weapons/taser.ogg', wielded_item_state="riflestun-wielded", charge_cost = 40),
		list(mode_name="lethal", projectile_type=/obj/item/projectile/beam, modifystate="riflekill", fire_sound='sound/weapons/Laser.ogg', wielded_item_state="riflekill-wielded", charge_cost = 80),
		)

/obj/item/gun/energy/gun/burst //Halving since by 3 seems too much
	firemodes = list(
		list(mode_name="stun", burst=1, projectile_type=/obj/item/projectile/beam/stun/weak, modifystate="energystun", charge_cost = 50),
		list(mode_name="stun burst", burst=3, fire_delay=null, move_delay=4, burst_accuracy=list(0,0,0), dispersion=list(0.0, 0.2, 0.5), projectile_type=/obj/item/projectile/beam/stun/weak, modifystate="energystun"),
		list(mode_name="lethal", burst=1, projectile_type=/obj/item/projectile/beam/burstlaser, modifystate="energykill", charge_cost = 100),
		list(mode_name="lethal burst", burst=3, fire_delay=null, move_delay=4, burst_accuracy=list(0,0,0), dispersion=list(0.0, 0.2, 0.5), projectile_type=/obj/item/projectile/beam/burstlaser, modifystate="energykill"),
		)

/obj/item/gun/energy/gun/etommy //Halving this one
	firemodes = list(
		list(mode_name="lethal", burst=1, projectile_type=/obj/item/projectile/beam/burstlaser, charge_cost = 100),
		list(mode_name="lethal burst", burst=4, fire_delay=null, move_delay=4, burst_accuracy=list(0,0,0), dispersion=list(0.0, 0.2, 0.5), projectile_type=/obj/item/projectile/beam/burstlaser),
		)

/obj/item/gun/energy/gun/compact
	firemodes = list(
		list(mode_name="stun", projectile_type=/obj/item/projectile/beam/stun/med, modifystate="PDWstun", fire_sound='sound/weapons/taser.ogg', charge_cost = 80),
		list(mode_name="lethal", projectile_type=/obj/item/projectile/beam, modifystate="PDWkill", fire_sound='sound/weapons/Laser.ogg', charge_cost = 160),
		)

/obj/item/gun/energy/gun/eluger
	firemodes = list(
		list(mode_name="stun", projectile_type=/obj/item/projectile/beam/stun, modifystate="ep08stun", fire_sound='sound/weapons/taser.ogg', charge_cost = 40),
		list(mode_name="lethal", projectile_type=/obj/item/projectile/beam/eluger, modifystate="ep08kill", fire_sound='sound/weapons/Laser.ogg', charge_cost = 80),
		)

/obj/item/gun/energy/sf2000
	firemodes = list(
		list(mode_name="stun", projectile_type=/obj/item/projectile/beam/stun/weak, modifystate="lasgunstun", fire_sound='sound/weapons/taser.ogg', charge_cost = 80),
		list(mode_name="lethal", projectile_type=/obj/item/projectile/beam, modifystate="lasgunkill", fire_sound='sound/weapons/Laser.ogg', charge_cost = 160),
		)


/obj/item/gun/energy/gun/burst/mg42 //I am unsure what this weapon is, and it seems cheap on paper but just putting it at 80 for unity
	firemodes = list(
		list(mode_name="single fire", burst=1, projectile_type=/obj/item/projectile/beam/burstlaser, modifystate="mg42-e", fire_sound='sound/weapons/Laser.ogg', charge_cost = 80),
		list(mode_name="burst fire", burst=3, fire_delay=null, move_delay=4, burst_accuracy=list(0,0,0), dispersion=list(0.0, 0.2, 0.5), projectile_type=/obj/item/projectile/beam/burstlaser, modifystate="mg42-e", fire_sound='sound/weapons/Laser.ogg'),
		list(mode_name="5 laser burst", burst=5, fire_delay=null, move_delay=4, burst_accuracy=list(0,0,0,0,0), dispersion=list(0.0, 0.2, 0.5, 0.5, 0.5), projectile_type=/obj/item/projectile/beam/burstlaser, modifystate="mg42-e", fire_sound='sound/weapons/Laser.ogg'),
		list(mode_name="15 laser burst, ye boi.", burst=15, fire_delay=null, move_delay=4, burst_accuracy=list(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0), dispersion=list(0.0, 0.2, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5), projectile_type=/obj/item/projectile/beam/burstlaser, modifystate="mg42-e", fire_sound='sound/weapons/Laser.ogg'),
		)

/obj/item/gun/energy/x01
	firemodes = list(
		list(mode_name="stun", fire_delay = 8, projectile_type= /obj/item/projectile/beam/stun, modifystate="x01stun", fire_sound='sound/weapons/taser.ogg', charge_cost = 80),
		list(mode_name="laser", fire_delay = 8, projectile_type=/obj/item/projectile/beam, modifystate="x01laser", fire_sound='sound/weapons/Laser.ogg', charge_cost = 160),
		list(mode_name="gauss", fire_delay=15, projectile_type=/obj/item/projectile/energy/gauss, modifystate="x01gauss", fire_sound='sound/weapons/gauss_shoot.ogg', charge_cost = 120)
		)
*/
