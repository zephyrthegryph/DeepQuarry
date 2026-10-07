/obj/item/integrated_circuit/manipulation
	category_text = "Manipulation"

/obj/item/integrated_circuit/manipulation/weapon_firing
	name = "weapon firing mechanism"
	desc = "This somewhat complicated system allows one to slot in a gun, direct it towards a position, and remotely fire it."
	extended_desc = "The firing mechanism can slot in most ranged weapons, ballistic and energy.  \
	The first and second inputs need to be numbers.  They are coordinates for the gun to fire at, relative to the machine itself.  \
	The 'fire' activator will cause the mechanism to attempt to fire the weapon at the coordinates, if possible.  Note that the \
	normal limitations to firearms, such as ammunition requirements and firing delays, still hold true if fired by the mechanism. \
	Additionally, the complexity of the circuit increases based on the weapon's size. A tiny gun will have 30 complexity, a small 60, medium 90, large 120, and bulky 150. \
	It can likewise not shoot while obscured (inside a container, such as a closet or backpack) or if there is a closet or container on the same tile as it."
	complexity = 30 // Increased due to clear balance necessity.
	w_class = ITEMSIZE_NORMAL
	size = 3
	inputs = list(
		"target X rel" = IC_PINTYPE_NUMBER,
		"target Y rel" = IC_PINTYPE_NUMBER
		)
	outputs = list()
	activators = list(
		"fire" = IC_PINTYPE_PULSE_IN
	)
	var/obj/item/gun/installed_gun = null // owned, in our contents
	spawn_flags = IC_SPAWN_RESEARCH
	power_draw_per_use = 50 // The targeting mechanism uses this.  The actual gun uses its own cell for firing if it's an energy weapon.

/// Old attackby.
/obj/item/integrated_circuit/manipulation/weapon_firing/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/O = A.held
	if(istype(O, /obj/item/gun))
		var/obj/item/gun/gun = O
		if(installed_gun)
			to_chat(user, span_warning("There's already a weapon installed."))
			return OP_PASS
		size += gun.w_class
		complexity = complexity * gun.w_class //Max complexity that a case can reach is 240. This means a small gun = 60 complexity, normal = 90, large = 120. This means you could fit 3 small guns, 2 normal guns, or 1 large gun in the circuit.
		if(!move_into(src, nameof(src.installed_gun), gun, user))
			return OP_PASS
		to_chat(user, span_notice("You slide \the [gun] into the firing mechanism."))
		play_sfx(src, SFX_ITEMS_CROWBAR)
	else
		return OP_DECLINE
	return OP_PASS

CAPABILITIES(/obj/item/integrated_circuit/manipulation/weapon_firing)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_self.
/obj/item/integrated_circuit/manipulation/weapon_firing/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(installed_gun)
		installed_gun.forceMove(get_turf(src))
		to_chat(user, span_notice("You slide \the [installed_gun] out of the firing mechanism."))
		size = initial(size)
		complexity = initial(complexity)
		play_sfx(src, SFX_ITEMS_CROWBAR)
		rel_take(src, nameof(installed_gun))
	else
		to_chat(user, span_notice("There's no weapon to remove from the mechanism."))
	return TRUE

/obj/item/integrated_circuit/manipulation/weapon_firing/do_work()
	if(!installed_gun)
		return
	if(!assembly())
		return
	if(!istype(loc, /obj/item/electronic_assembly))
		return

	//Check to see if we are in a banned position (inside a closet, backpack, etc)
	//LOC is The circuit we are in. loc.loc is 'what that circuit is in'.
	//Generally, this should be a mob, the floor, or a circuitry clothing item.
	var/our_position = loc.loc
	if(!ismob(our_position) && !isturf(our_position)) //If we're being held by a mob or we're on the ground, that's fine, continue.
		var/list/banned_positions = list(
			/obj/item/storage,
			/obj/structure/closet,
			/obj/mecha
		)
		if(is_type_in_list(our_position, banned_positions))
			return
	//Prevents shoving 40 of these into a closet, opening it, and having it annihilate some poor sap.
	else if(isturf(our_position) && (locate_in_list(range(0, our_position), /obj/structure/closet)))
		return

	var/datum/integrated_io/target_x = inputs[1]
	var/datum/integrated_io/target_y = inputs[2]

	if(isnum(target_x.data))
		target_x.data = round(target_x.data)
	if(isnum(target_y.data))
		target_y.data = round(target_y.data)

	var/turf/T = get_turf(src.assembly())

	if(target_x.data == 0 && target_y.data == 0) // Don't shoot ourselves.
		return

	// We need to do this in order to enable relative coordinates, as locate() only works for absolute coordinates.
	var/i
	if(target_x.data > 0)
		i = abs(target_x.data)
		while(i > 0)
			T = get_step(T, EAST)
			i--
	else
		i = abs(target_x.data)
		while(i > 0)
			T = get_step(T, WEST)
			i--

	i = 0
	if(target_y.data > 0)
		i = abs(target_y.data)
		while(i > 0)
			T = get_step(T, NORTH)
			i--
	else if(target_y.data < 0)
		i = abs(target_y.data)
		while(i > 0)
			T = get_step(T, SOUTH)
			i--

	if(!T)
		return
	installed_gun.Fire_userless(T)

/obj/item/integrated_circuit/manipulation/locomotion
	name = "locomotion circuit"
	desc = "This allows a machine to move in a given direction."
	icon_state = "locomotion"
	extended_desc = "The circuit accepts a 'dir' number as a direction to move towards.<br>\
	Pulsing the 'step towards dir' activator pin will cause the machine to move a meter in that direction, assuming it is not \
	being held, or anchored in some way.  It should be noted that the ability to move is dependent on the type of assembly that this circuit inhabits."
	w_class = ITEMSIZE_NORMAL
	complexity = 20
	inputs = list("direction" = IC_PINTYPE_DIR)
	outputs = list()
	activators = list("step towards dir" = IC_PINTYPE_PULSE_IN)
	spawn_flags = IC_SPAWN_RESEARCH
	power_draw_per_use = 100

/obj/item/integrated_circuit/manipulation/locomotion/do_work()
	..()
	var/turf/T = get_turf(src)
	if(T && assembly())
		if(assembly().anchored || !assembly().can_move())
			return
		if(assembly().loc == T) // Check if we're held by someone.  If the loc is the floor, we're not held.
			var/datum/integrated_io/wanted_dir = inputs[1]
			if(isnum(wanted_dir.data))
				step(assembly(), wanted_dir.data)

/obj/item/integrated_circuit/manipulation/grenade
	name = "grenade primer"
	desc = "This circuit comes with the ability to attach most types of grenades at prime them at will."
	extended_desc = "Time between priming and detonation is limited to between 1 to 12 seconds but is optional. \
					If unset, not a number, or a number less than 1 then the grenade's built-in timing will be used. \
					Beware: Once primed there is no aborting the process!"
	icon_state = "grenade"
	complexity = 30
	size = 2
	inputs = list("detonation time" = IC_PINTYPE_NUMBER)
	outputs = list()
	activators = list("prime grenade" = IC_PINTYPE_PULSE_IN)
	spawn_flags = IC_SPAWN_RESEARCH
	var/obj/item/grenade/attached_grenade
	var/pre_attached_grenade_type

CAPABILITIES(/obj/item/integrated_circuit/manipulation/grenade)
	owns_one(nameof(attached_grenade), /obj/item/grenade)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/obj/item/integrated_circuit/manipulation/grenade/Initialize(mapload)
	. = ..()
	if(pre_attached_grenade_type)
		var/grenade = new pre_attached_grenade_type(src)
		attach_grenade(grenade)

// An unarmed grenade drops out.
/obj/item/integrated_circuit/manipulation/grenade/on_destroy(force)
	if(attached_grenade && !attached_grenade.active)
		attached_grenade.dropInto(loc)
	detach_grenade()
	..()

/// Old attackby.
/obj/item/integrated_circuit/manipulation/grenade/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/grenade/G = A.held
	if(istype(G))
		if(attached_grenade)
			to_chat(user, span_warning("There is already a grenade attached!"))
		else if(user.unEquip(G, force=1))
			act_message(user, src, MSG_SELF(span_notice("You attach %I% to %T%.")), MSG_OTHERS(span_warning("%U% attaches \a [G] to %T%!")), item = G)
			attach_grenade(G)
			G.forceMove(src)
	else
		return OP_DECLINE
	return OP_PASS

/// Old attack_self.
/obj/item/integrated_circuit/manipulation/grenade/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(attached_grenade)
		act_message(user, src, MSG_SELF(span_notice("You remove \the [attached_grenade] from %T%.")), \
			MSG_OTHERS(span_warning("%U% removes \an [attached_grenade] from %T%!")))
		user.put_in_any_hand_if_possible(attached_grenade) || attached_grenade.dropInto(loc)
		detach_grenade()
	else
		return OP_DECLINE
	return TRUE

/obj/item/integrated_circuit/manipulation/grenade/do_work()
	if(attached_grenade && !attached_grenade.active)
		var/datum/integrated_io/detonation_time = inputs[1]
		if(isnum(detonation_time.data) && detonation_time.data > 0)
			attached_grenade.det_time = between(1, detonation_time.data, 12) SECONDS
		attached_grenade.activate()
		var/atom/holder = loc
		log_and_message_admins("activated a grenade assembly. Last touches: Assembly: [holder.forensic_data?.get_lastprint()] Circuit: [forensic_data?.get_lastprint()] Grenade: [attached_grenade.forensic_data?.get_lastprint()]")

// These procs do not relocate the grenade, that's the callers responsibility
/obj/item/integrated_circuit/manipulation/grenade/proc/attach_grenade(obj/item/grenade/G)
	rel_set(src, nameof(attached_grenade), G)
	observe(attached_grenade, /datum/notice/qdeleting, src, then(PROC_REF(detach_grenade)))
	size += G.w_class
	desc += " \An [attached_grenade] is attached to it!"

/obj/item/integrated_circuit/manipulation/grenade/proc/detach_grenade(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	if(!attached_grenade)
		return
	unobserve(attached_grenade, /datum/notice/qdeleting, src)
	rel_take(src, nameof(attached_grenade))
	size = initial(size)
	desc = initial(desc)

/obj/item/integrated_circuit/manipulation/grenade/frag
	pre_attached_grenade_type = /obj/item/grenade/explosive
	spawn_flags = null			// Used for world initializing, see the #defines above.

// ITION: Size Circuit
/obj/item/integrated_circuit/manipulation/Size
	name = "size circuit"
	desc = "This allows a given target to be resized."
	icon_state = "locomotion"
	extended_desc = "The Circuit accepts a reference to a creature and the size toset them to."
	w_class = ITEMSIZE_NORMAL
	complexity = 20
	inputs = list(	"target ref",
					"size" = IC_PINTYPE_NUMBER)
	outputs = list()
	activators = list("set size" = IC_PINTYPE_PULSE_IN,"on size set" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_RESEARCH
	power_draw_per_use = 100

/obj/item/integrated_circuit/manipulation/size/do_work()
	pull_data()
	var/mob/living/target = get_pin_data(IC_INPUT, 1)
	var/size = get_pin_data(IC_INPUT, 2)
	var/turf/tt = get_turf(target)
	var/turf/st = get_turf(src)
	if(!tt || !st)
		return

	var/distance = sqrt((st.x - tt.x)**2 + (st.y - tt.y)**2)
	if (distance >= 6)
		return
	if(target && istype(target,/mob/living/))
		target.resize(size/100)
	activate_pin(2)

/obj/item/integrated_circuit/manipulation/weapon_firing/ownership()
	. = ..()
	. += owns(nameof(installed_gun), policy = OWN_CONTAINED)
