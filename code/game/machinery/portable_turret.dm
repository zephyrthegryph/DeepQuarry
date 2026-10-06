/*		Portable Turrets:
		Constructed from metal, a gun of choice, and a prox sensor.
		This code is slightly more documented than normal, as requested by XSI on IRC.
*/

/datum/category_item/catalogue/technology/turret
	name = "Turrets"
	desc = "This imtimidating machine is essentially an automated gun. It is able to \
	scan its immediate environment, and if it determines that a threat is nearby, it will \
	open up, aim the barrel of the weapon at the threat, and engage it until the threat \
	goes away, it dies (if using a lethal gun), or the turret is destroyed. This has made them \
	well suited for long term defense for a static position, as electricity costs much \
	less than hiring a person to stand around. Despite this, the lack of a sapient entity's \
	judgement has sometimes lead to tragedy when turrets are poorly configured.\
	<br><br>\
	Early models generally had simple designs, and would shoot at anything that moved, with only \
	the option to disable it remotely for maintenance or to let someone pass. More modern iterations \
	of turrets have instead replaced those simple systems with intricate optical sensors and \
	image recognition software that allow the turret to distinguish between several kinds of \
	entities, and to only engage whatever their owners configured them to fight against.\
	Some models also have the ability to switch between a lethal and non-lethal mode.\
	<br><br>\
	Today's cutting edge in static defense development has shifted away from improving the \
	software of the turret, and instead towards the hardware. The newest solutions for \
	automated protection includes new hardware capabilities such as thicker armor, more \
	advanced integrated weapons, and some may even have been built with EM hardening in \
	mind."
	value = CATALOGUER_REWARD_MEDIUM

#define TURRET_PRIORITY_TARGET 2
#define TURRET_SECONDARY_TARGET 1
#define TURRET_NOT_TARGET 0

#define TURRET_RETALIATION_TIME 3 SECONDS
#define TURRET_EMAG_FIRERATE 0.6 SECONDS
/// How often an armed turret looks for targets: while it engages one, and while it watches.
#define TURRET_SCAN_ENGAGED (0.5 SECONDS)
#define TURRET_SCAN_IDLE MACHINE_SERVICE_INTERVAL

// A portable turret is declared (doc/rewrite/final_api.html section 16.3): `enabled` is the setting someone chose (its window, its control panel),
// `armed` is a stat that is true while the turret may fire: switched on and working (powered, whole, not held down by a pulse or by an emag's
// grace). An electromagnetic pulse is emp_disable(): a timed hold on operable that ends by itself and leaves the setting alone; the emag makes it
// fire at everyone after a short grace. The scan is an every() that runs only while armed, quickly while it engages someone; the cover pops up
// while it engages (popup_cover()), and the turret is solid and exposed while it is up. The ID lock (lock()) gates the window, a control panel in
// its area takes the window over, and the silicons' firewall (ailock) keeps them out. Its own work below: targeting and firing.

/obj/machinery/porta_turret
	name = "turret"
	catalogue_data = list(/datum/category_item/catalogue/technology/turret)
	icon = 'icons/obj/turrets.dmi'
	icon_state = "turret_cover_normal"
	anchored = TRUE

	density = FALSE
	use_power = TRUE				//this turret uses and requires power
	idle_power_usage = 50		//when inactive, this turret takes up constant 50 Equipment power
	active_power_usage = 300	//when active, this turret takes up constant 300 Equipment power
	power_channel = EQUIP	//drains power from the EQUIPMENT channel
	req_one_access = list(ACCESS_SECURITY, ACCESS_HEADS)
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE

	max_integrity = 80			//the turret's integrity
	var/auto_repair = FALSE		//if 1 the turret slowly repairs itself (while armed).
	/// The ID lock starts engaged (a lasertag turret's does not).
	var/lock_at_start = TRUE
	var/controllock = FALSE		//if the turret responds to control panels

	var/installation = /obj/item/gun/energy/gun		//the type of weapon installed
	var/gun_charge = 0				//the charge of the gun inserted
	var/projectile = null			//holder for bullettype
	var/lethal_projectile = null	//holder for the shot when emagged
	var/reqpower = 500				//holder for power needed
	var/turret_type = "normal"
	var/icon_color = "blue"
	var/lethal_icon_color = "blue"

	var/last_fired = FALSE			//TRUE: if the turret is cooling down from a shot, FALSE: turret is ready to fire
	var/shot_delay = 1.5 SECONDS	//1.5 seconds between each shot

	var/targetting_is_configurable = TRUE // if false, you cannot change who this turret attacks via its UI
	var/check_arrest = TRUE		//checks if the perp is set to arrest
	var/check_records = TRUE	//checks if a security record exists at all
	var/check_weapons = FALSE	//checks if it can shoot people that have a weapon they aren't authorized to have
	var/check_access = TRUE		//if this is active, the turret shoots everything that does not meet the access requirements
	var/check_anomalies = TRUE	//checks if it can shoot at unidentified lifeforms (ie xenos)
	var/check_synth	 = FALSE 	//if active, will shoot at anything not an AI or cyborg
	var/check_all = FALSE		//If active, will fire on anything, including synthetics.
	var/ailock = FALSE 			// AI cannot use this
	var/check_down = FALSE		//If active, will shoot to kill when lethals are also on
	var/faction = null			//if set, will not fire at people in the same faction for any reason.

	var/attacked = FALSE		//if set to TRUE, the turret gets pissed off and shoots at people nearby (unless they have sec access!)

	/// The turret's capacitors hold its power: TRUE while its area gives power, until a moment after it stops (power_change()).
	var/power_held = TRUE
	var/enabled = TRUE			//determines if the turret is on (the setting someone chose)
	var/lethal = FALSE			//whether in lethal or stun mode
	var/lethal_is_configurable = TRUE // if false, its lethal setting cannot be changed
	/// It has a target in its sights (the cover is up while it engages, and it scans quickly).
	var/engaging = FALSE

	var/shot_sound 				//what sound should play when the turret fires
	var/lethal_shot_sound		//what sound should play when the emagged turret fires

	var/last_target			//last target fired at, prevents turrets from erratically firing at all valid targets in range
	/// How many machine frames the cover stays up after the turret last had a target.
	var/timeout = 10
	var/can_salvage = TRUE	// If false, salvaging doesn't give you anything.
TRACKED(/obj/machinery/porta_turret, icon_color)
TRACKED(/obj/machinery/porta_turret, lethal_icon_color)

TRACKED(/obj/machinery/porta_turret, enabled)
TRACKED(/obj/machinery/porta_turret, power_held)
TRACKED(/obj/machinery/porta_turret, lethal)
TRACKED(/obj/machinery/porta_turret, check_arrest)
TRACKED(/obj/machinery/porta_turret, check_records)
TRACKED(/obj/machinery/porta_turret, check_weapons)
TRACKED(/obj/machinery/porta_turret, check_access)
TRACKED(/obj/machinery/porta_turret, check_anomalies)
TRACKED(/obj/machinery/porta_turret, check_synth)
TRACKED(/obj/machinery/porta_turret, check_all)
TRACKED(/obj/machinery/porta_turret, check_down)
TRACKED(/obj/machinery/porta_turret, controllock)
TRACKED(/obj/machinery/porta_turret, attacked)
TRACKED(/obj/machinery/porta_turret, engaging)
TRACKED(/obj/machinery/porta_turret, auto_repair)

/// Whether the turret fires now: switched on and working.
STAT(/obj/machinery/porta_turret, armed, ALL)

MSG_DEF_SELF(porta_turret/controlled, "It can only be controlled using its assigned turret controller.")
MSG_DEF_SELF(porta_turret/firewall, "There seems to be a firewall preventing you from accessing this device.")
MSG_DEF_SELF(porta_turret/unsecured, "It has to be secured first!")
MSG_DEF_SELF(porta_turret/active, "You cannot unsecure an active turret!")
MSG_DEF_SELF(porta_turret/in_space, "Cannot secure turrets in space!")
MSG_DEF_SELF(porta_turret/wrecked, "It is wrecked: pry it apart instead.")
MSG_DEF(porta_turret/haywire, "You short out %T%'s threat assessment circuits.", "")

CAPABILITIES(/obj/machinery/porta_turret)
	machine_basics(repair = NONE)
	membership(joins = REGISTRY_TURRETS)
	lock(starts_locked = nameof(lock_at_start), alt = FALSE, guarded = FALSE)
	contributes(STAT_ARMED, nameof(enabled))
	// Power loss reaches a turret a moment late (its capacitors): its own reading replaces the area's, and power_change() moves it after the delay.
	contributes(STAT_HAS_POWER, nameof(power_held), key = "turret_power")
	contributes(STAT_ARMED, STAT_OPERABLE)
	emp_disable(list(6 SECONDS, 60 SECONDS))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(scramble_settings)))
	emag(then(PROC_REF(go_haywire)), say = MSG(porta_turret/haywire), disables_for = 6 SECONDS)
	popup_cover(raised_while = PROC_REF(cover_wanted), on_move = PROC_REF(cover_moves))
	every(PROC_REF(scan_interval), then(PROC_REF(scan)), when = STAT_ARMED)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(self_repair)), when = nameof(auto_repair))
	on_change(STAT_ARMED, EXIT, then(PROC_REF(disarmed)))
	anchor()
	extend("anchor.toggle", wait(5 SECONDS), claims(), needs(
		req(PROC_REF(intact), because = MSG(porta_turret/wrecked)),
		req(PROC_REF(idle_for_the_wrench), because = MSG(porta_turret/active)),
		req(PROC_REF(not_anchoring_in_space), because = MSG(porta_turret/in_space))))
	op("salvage", tool(TOOL_CROWBAR), when(TYPE_PROC_REF(/obj/machinery, stat_is_broken)), wait(2 SECONDS), then(PROC_REF(salvaged)))
	op("strike", item(/obj/item), hostile(), then(PROC_REF(struck)))

	section(window, "The turret's window, its buttons, and who may use them")
	interface("PortableTurret")
	extend("ui_open", needs(req(PROC_REF(uncontrolled), because = MSG(porta_turret/controlled)), req_is(nameof(anchored), because = MSG(porta_turret/unsecured))))
	extend(TAG_UI, needs(req(PROC_REF(uncontrolled), because = MSG(porta_turret/controlled)), req_window_usable(remote = PROC_REF(firewall_open), remote_because = MSG(porta_turret/firewall))))
	op("power", ui_act(), toggles(nameof(enabled)))
	op("lethal", ui_act(), toggles(nameof(lethal), when = nameof(lethal_is_configurable)))
	op("authweapon", ui_act(), toggles(nameof(check_weapons), when = nameof(targetting_is_configurable)))
	op("authaccess", ui_act(), toggles(nameof(check_access), when = nameof(targetting_is_configurable)))
	op("authnorecord", ui_act(), toggles(nameof(check_records), when = nameof(targetting_is_configurable)))
	op("autharrest", ui_act(), toggles(nameof(check_arrest), when = nameof(targetting_is_configurable)))
	op("authxeno", ui_act(), toggles(nameof(check_anomalies), when = nameof(targetting_is_configurable)))
	op("authsynth", ui_act(), toggles(nameof(check_synth), when = nameof(targetting_is_configurable)))
	op("authall", ui_act(), toggles(nameof(check_all), when = nameof(targetting_is_configurable)))
	op("authdown", ui_act(), toggles(nameof(check_down), when = nameof(targetting_is_configurable)))

/obj/machinery/porta_turret/can_catalogue(mob/user) // Dead turrets can't be scanned.
	if(has_stat(BROKEN))
		to_chat(user, span_warning("\The [src] was destroyed, so it cannot be scanned."))
		return FALSE
	return ..()

// ---- who may use the window ----

/// No control panel in the turret's area has taken it over.
/obj/machinery/porta_turret/proc/uncontrolled(datum/act/op/A)
	return !has_controller()

/// The turret's area has a control panel.
/obj/machinery/porta_turret/proc/has_controller()
	var/area/here = isturf(loc) ? loc.loc : null // ALLOW(reads): the turret's area is asked when a button is pressed; a bolted turret does not move
	return !!length(here?.turret_controls)

TRACKED(/obj/machinery/porta_turret, ailock)

/// The firewall (ailock) is down: a silicon over its link may work the window (req_window_usable() asks this only of a remote user).
/obj/machinery/porta_turret/proc/firewall_open(datum/act/op/A)
	return !ailock

// ---- the window ----

/obj/machinery/porta_turret/ui_data(datum/act/eval/A)
	return list(
		"locked" = lock_locked(src),
		"on" = enabled,
		"targetting_is_configurable" = targetting_is_configurable, // If false, targetting settings don't show up
		"lethal" = lethal,
		"lethal_is_configurable" = lethal_is_configurable,
		"check_weapons" = check_weapons,
		"neutralize_noaccess" = check_access,
		"neutralize_norecord" = check_records,
		"neutralize_criminals" = check_arrest,
		"neutralize_all" = check_all,
		"neutralize_nonsynth" = check_synth,
		"neutralize_unidentified" = check_anomalies,
		"neutralize_down" = check_down,
	)

// ---- power, pulses, the emag ----

/// Power loss reaches a turret a moment late (its capacitors); power that comes back first cancels the loss. The turret's STAT_HAS_POWER reads
/// `power_held`, which this moves: at once on restore, after the delay on loss (a declared delay on the turret's side, not a second writer of the grid's state).
/obj/machinery/porta_turret/power_change()
	if(powered())
		cancel_after(src, "power_loss")
		set_power_held(TRUE)
	else
		after(src, rand(0 SECONDS, 1.5 SECONDS), PROC_REF(power_off_delayed), key = "power_loss")

/obj/machinery/porta_turret/area_gives_power(datum/act/A)
	return TRUE // the capacitors' reading (power_held) is the turret's own

/obj/machinery/porta_turret/proc/power_off_delayed()
	set_power_held(FALSE)

/// A pulse on a running turret scrambles its targets, with a slight chance of an emag's effect (the outage itself is emp_disable()'s).
/obj/machinery/porta_turret/proc/scramble_settings(datum/act/A)
	if(!enabled)
		return
	var/datum/notice/hit/emp/N = A
	turret_targets_scramble(src)
	if(prob(20 / max(N.packet?.severity, 1))) //sev 1  = 20% chance sev 2 = 10% sev 3 = ~6 sev 4 = 5%
		cap_key_set(src, EMAG_EMAGGED, TRUE, null)

/// The emag: it locks the control panels out and fires at everyone once its grace (the emag's disables_for) is over.
/obj/machinery/porta_turret/proc/go_haywire(datum/act/op/A)
	visible_message(span_info("[src] hums oddly..."))
	set_controllock(TRUE)
	set_enabled(TRUE)
	return OP_OK

/// No longer armed: it stops engaging and forgets its target.
/obj/machinery/porta_turret/proc/disarmed(datum/act/A)
	cancel_after(src, "stand_down")
	set_engaging(FALSE)
	last_target = null

// ---- wrench, crowbar, a blow ----

/obj/machinery/porta_turret/proc/intact(datum/act/op/A)
	return !has_stat(BROKEN)

/// The wrench moves only a switched-off turret with its cover down.
/obj/machinery/porta_turret/proc/idle_for_the_wrench(datum/act/op/A)
	return !enabled && !popup_cover_raised(src)

/// A loose turret cannot be bolted down in space.
/obj/machinery/porta_turret/proc/not_anchoring_in_space(datum/act/op/A)
	return anchored || !istype(loc, /turf/space) // ALLOW(reads): the floor under it is asked when the wrench turns, never cached

/// A wreck pried apart: with luck, its gun and parts come out.
/obj/machinery/porta_turret/proc/salvaged(datum/act/op/A)
	var/mob/user = A.actor
	if(can_salvage && prob(70))
		to_chat(user, span_notice("You remove the turret and salvage some components."))
		if(installation)
			var/obj/item/gun/energy/Gun = new installation(loc)
			Gun.power_supply.charge = gun_charge
			Gun.update_icon()
		if(prob(50))
			new /obj/item/stack/material/steel(loc, rand(1,4))
		if(prob(50))
			new /obj/item/assembly/prox_sensor(loc)
	else
		to_chat(user, span_notice("You remove the turret but did not manage to salvage anything."))
	spent(src)
	return OP_OK

/// A blow meant to hurt it: half the force lands, and it gets angry.
/obj/machinery/porta_turret/proc/struck(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	user.setClickCooldown(user.get_attack_speed(I))
	var/dam = I.force * 0.5
	take_damage(dam, BRUTE, MELEE)
	attempt_retaliate(dam)
	return OP_OK

/obj/machinery/porta_turret/proc/attempt_retaliate(incoming_damage)
	if(QDELETED(src) || attacked || !enabled || emag_emagged(src) || incoming_damage < 1) //if the force of impact dealt at least 1 damage, the turret gets pissed off
		return
	if(!stat_value(src, STAT_OPERABLE))
		return
	set_attacked(TRUE)
	after(src, TURRET_RETALIATION_TIME, PROC_REF(retaliate_end), key = "grudge")
	play_sfx(src, SFX_MACHINES_TERMINAL_ALERT)

/// A stumble's grudge wears off, quietly.
/obj/machinery/porta_turret/proc/calm_down()
	set_attacked(FALSE)

/obj/machinery/porta_turret/proc/retaliate_end()
	set_attacked(FALSE)
	if(!stat_value(src, STAT_OPERABLE))
		return
	play_sfx(src, SFX_MACHINES_BUZZBEEP, 3)

/obj/machinery/porta_turret/attack_generic(mob/living/L, damage)
	if(isanimal(L))
		var/mob/living/simple_mob/S = L
		if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
			var/incoming_damage = round(damage - (damage / 5)) //Turrets are slightly armored, assumedly.
			visible_message(span_danger("\The [S] [pick(S.attacktext)] \the [src]!"))
			receive_generic_attack(S, incoming_damage)
			S.do_attack_animation(src)
			attempt_retaliate(incoming_damage)
			return 1
		visible_message(span_infoplain(span_bold("\The [L]") + " bonks \the [src]'s casing!"))
	return ..()

// While the cover is down the turret is heavily armored: incoming damage is
// cut to an eighth, and anything that small is shrugged off entirely.
/obj/machinery/porta_turret/run_atom_armor(damage_amount, damage_type, damage_flag = 0, attack_dir, armour_penetration = 0)
	. = ..()
	if(!popup_cover_raised(src) && !popup_cover_moving(src))
		. = . / 8
		if(. < 5)
			return 0

/obj/machinery/porta_turret/on_update_integrity(old_value, new_value)
	. = ..()
	if(new_value < old_value && (old_value - new_value) > 5 && prob(45))
		fx_sparks(src, 5, FALSE)

// Reaching zero integrity runs the turret's death process (it persists as a
// broken wreck rather than being deleted).
/obj/machinery/porta_turret/atom_destruction(damage_flag)
	. = ..()
	die()

/obj/machinery/porta_turret/bullet_act(obj/item/projectile/Proj)
	var/damage = Proj.get_structure_damage()

	if(!damage)
		return

	..()
	attempt_retaliate(damage)

/obj/machinery/porta_turret/proc/die()	//called when the turret dies, ie, integrity <= 0
	atom_break()
	fx_sparks(src, 5, FALSE)	//creates some sparks because they look cool

// ---- the look ----

/// The icon_state prefix before turret_type.
/obj/machinery/porta_turret/proc/appearance_prefix()
	if(has_stat(BROKEN))
		return "destroyed_target_prism_"
	if(popup_cover_raised(src) || popup_cover_moving(src))
		if(!has_stat(NOPOWER) && enabled)
			return "[lethal ? lethal_icon_color : icon_color]_target_prism_"
		return "grey_target_prism_"
	return "turret_cover_"

/obj/machinery/porta_turret/draw(datum/look/look)
	..()
	look.state("[appearance_prefix()][turret_type]")
	look.overlay(turret_opening_image(icon, turret_type, layer))

/// The opening the turret sits in, drawn under it: one shared image per icon, turret type and layer.
/proc/turret_opening_image(icon_file, turret_type, base_layer)
	var/static/list/cache = list() // ALLOW(cache): one image per icon file, turret type and layer, made on first draw and never invalidated
	var/key = "[icon_file]|[turret_type]|[base_layer]"
	var/image/I = cache[key]
	if(!I)
		I = image(icon_file, "open_[turret_type]")
		I.layer = base_layer - 0.1
		cache[key] = I
	return I

// ---- the cover ----

/// The cover is up while the turret engages someone.
/obj/machinery/porta_turret/proc/cover_wanted(datum/act/A)
	return armed && engaging

/// The cover starts to move: the animation plays on a stand-in over the turret, and the mechanism sounds.
/obj/machinery/porta_turret/proc/cover_moves(datum/act/A, raising)
	var/atom/movable/flick_holder = new /atom/movable/porta_turret_cover(loc)
	flick_holder.layer = layer + 0.1
	flick("[raising ? "popup" : "popdown"]_[turret_type]", flick_holder)
	play_sfx(src, raising ? SFX_MACHINES_TURRETS_TURRET_DEPLOY : SFX_MACHINES_TURRETS_TURRET_RETRACT)
	after(src, 1 SECOND, PROC_REF(cover_flick_done), with = list(flick_holder))

/obj/machinery/porta_turret/proc/cover_flick_done(atom/movable/flick_holder)
	lapsed(flick_holder)

/atom/movable/porta_turret_cover
	icon = 'icons/obj/turrets.dmi'

// ---- the scan ----

/// How long until the next scan: quickly while it engages someone.
/obj/machinery/porta_turret/proc/scan_interval(datum/act/A)
	return engaging ? TURRET_SCAN_ENGAGED : TURRET_SCAN_IDLE

/// The mobs the turret can see.
/obj/machinery/porta_turret/proc/scan_candidates()
	return mobs_in_view(world.view, src)

/// One look around while armed: it fires at the best target it sees (the cover comes down `timeout` frames after its last shot).
/obj/machinery/porta_turret/proc/scan(datum/act/timer/A)
	var/shot_targets = FALSE
	if(!last_fired) // We cannot fire anyway until our cooldown ends.
		var/list/targets = list()			//list of primary targets
		var/list/secondarytargets = list()	//targets that are least important
		for(var/mob/M in scan_candidates())
			assess_and_assign(M, targets, secondarytargets)
		shot_targets = tryToShootAt(targets) || tryToShootAt(secondarytargets)

/// Nothing was left to shoot for `timeout` frames: the cover goes down.
/obj/machinery/porta_turret/proc/stand_down()
	set_engaging(FALSE)

/// A turret that mends itself does it a point at a time while it is armed: 1HP for 20kJ.
/obj/machinery/porta_turret/proc/self_repair(datum/act/timer/A)
	if(armed && get_integrity() < max_integrity)
		use_power(20000)
		repair_damage(1)

/obj/machinery/porta_turret/proc/assess_and_assign(mob/living/L, list/targets, list/secondarytargets)
	switch(assess_living(L))
		if(TURRET_PRIORITY_TARGET)
			targets += L
		if(TURRET_SECONDARY_TARGET)
			secondarytargets += L

/obj/machinery/porta_turret/proc/target(mob/living/target)
	if(target)
		if(target in check_trajectory(target, src))	//Finally, check if we can actually hit the target
			last_target = target
			set_engaging(TRUE) // the cover pops up
			after(src, timeout * MACHINE_SERVICE_INTERVAL, PROC_REF(stand_down), key = "stand_down")
			if(!popup_cover_raised(src))
				return TRUE // We were delayed, but we really wanted to, so lets not count this as a failure
			var/old_dir = dir
			set_dir(get_dir(src, target))	//even if you can't shoot, follow the target
			if(dir != old_dir) // Play rotating sound, but only if we actually rotated
				play_sfx(src, SFX_MACHINES_TURRETS_TURRET_ROTATE)
			shootAt(target)
			return TRUE
	return FALSE

/obj/machinery/porta_turret/crescent
	req_one_access = list(ACCESS_CENT_SPECOPS)
	enabled = FALSE
	ailock = TRUE
	check_synth = FALSE
	check_access = TRUE
	check_arrest = TRUE
	check_records = TRUE
	check_weapons = TRUE
	check_anomalies = TRUE
	check_all = FALSE
	check_down = TRUE

/obj/machinery/porta_turret/can_catalogue(mob/user) // Dead turrets can't be scanned.
	if(has_stat(BROKEN))
		to_chat(user, span_warning("\The [src] was destroyed, so it cannot be scanned."))
		return FALSE
	return ..()

/obj/machinery/porta_turret/stationary
	ailock = TRUE
	lethal = TRUE
	installation = /obj/item/gun/energy/laser

/obj/machinery/porta_turret/stationary/syndie // Generic turrets for POIs that need to not shoot their buddies.
	req_one_access = list(ACCESS_SYNDICATE)
	enabled = TRUE
	check_all = TRUE
	faction = FACTION_SYNDICATE // Make sure this equals the faction that the mobs in the POI have or they will fight each other.

/obj/machinery/porta_turret/ai_defense
	name = "defense turret"
	desc = "This variant appears to be much more durable."
	req_one_access = list(ACCESS_SYNTH) // Just in case.
	installation = /obj/item/gun/energy/xray // For the armor pen.
	max_integrity = 250

/datum/category_item/catalogue/anomalous/precursor_a/alien_turret
	name = "Precursor Alpha Object - Turrets"
	desc = "An autonomous defense turret created by unknown ancient aliens. It utilizes an \
	integrated laser projector to harm, firing a cyan beam at the target. The signal processing \
	of this mechanism appears to be radically different to conventional electronics used by modern \
	technology, which appears to be much less susceptible to external electromagnetic influences.\
	<br><br>\
	This makes the turret be very resistant to the effects of an EM pulse. It is unknown if whatever \
	species that built the turret had intended for it to have that quality, or if it was an incidental \
	quirk of how they designed their electronics."
	value = CATALOGUER_REWARD_MEDIUM

/obj/machinery/porta_turret/alien // The kind used on the UFO submap.
	name = "interior anti-boarding turret"
	desc = "A very tough looking turret made by alien hands."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_turret)
	icon_state = "turret_cover_alien"
	req_one_access = list(ACCESS_ALIEN)
	installation = /obj/item/gun/energy/alien
	enabled = TRUE
	lethal = TRUE
	ailock = TRUE
	check_all = TRUE
	max_integrity = 250
	turret_type = "alien"

/// Superior alien technology: a pulse knocks it out for a minute or two, but three pulses in four do nothing.
CAPABILITIES(/obj/machinery/porta_turret/alien)
	configure(emp_disable(lasts = list(1 MINUTE, 2 MINUTES), resist = 75))

/obj/machinery/porta_turret/alien/destroyed // Turrets that are already dead, to act as a warning of what the rest of the submap contains.
	name = "broken interior anti-boarding turret"
	desc = "A very tough looking turret made by alien hands. This one looks destroyed, thankfully."
	icon_state = "destroyed_target_prism_alien"
	stat = BROKEN
	can_salvage = FALSE // So you need to actually kill a turret to get the alien gun.

/obj/machinery/porta_turret/industrial
	name = "industrial turret"
	desc = "This variant appears to be much more rugged."
	req_one_access = list(ACCESS_HEADS)
	icon_state = "turret_cover_industrial"
	installation = /obj/item/gun/energy/locked/phasegun/unlocked
	max_integrity = 200
	turret_type = "industrial"

/// Industrial turrets have exposed workings: they catch a third more of a round.
/obj/machinery/porta_turret/industrial/projectile_damage(obj/item/projectile/P, def_zone)
	return receive_projectile(P, def_zone, 1.33)

CAPABILITIES(/obj/machinery/porta_turret/industrial)
	extend(/datum/act/hit/melee, instead(then(PROC_REF(industrial_turret_blow))))

/// The industrial casing takes a fifth off animal blows (a generic attack, not a weapon).
/obj/machinery/porta_turret/industrial/proc/industrial_turret_blow(datum/act/hit/melee/A)
	if(A.packet.entry == DAMAGE_ENTRY_GENERIC)
		A.packet.scale(0.8)
	return HOOK_DECLINE

/obj/machinery/porta_turret/industrial/teleport_defense
	name = "defense turret"
	desc = "This variant appears to be much more durable, with a rugged outer coating."
	req_one_access = list(ACCESS_HEADS)
	installation = /obj/item/gun/energy/gun/burst
	max_integrity = 250

/obj/machinery/porta_turret/poi	//These are always angry
	enabled = TRUE
	lethal = TRUE
	ailock = TRUE
	check_all = TRUE
	can_salvage = FALSE	// So you can't just twoshot a turret and get a fancy gun

/obj/machinery/porta_turret/lasertag
	name = "lasertag turret"
	turret_type = "normal"
	req_one_access = list()
	installation = /obj/item/gun/energy/lasertag/omni
	projectile = /obj/item/projectile/beam/lasertag/omni
	lethal_projectile = /obj/item/projectile/beam/rainbow/non_lethal //Did you know that lasertag vests have 3x weakness to shock?

	targetting_is_configurable = FALSE
	lethal_is_configurable = FALSE

	lock_at_start = FALSE
	enabled = FALSE
	anchored = FALSE
	//These vars aren't used
	check_access = FALSE
	check_arrest = FALSE
	check_records = FALSE
	check_anomalies = FALSE
	check_all = FALSE
	check_down = FALSE

///What vests we will target.
TYPE_TABLE_DECLARE(/obj/machinery/porta_turret/lasertag, turret_vests_to_target, list( \
		/obj/item/clothing/suit/lasertag/redtag, \
		/obj/item/clothing/suit/lasertag/bluetag, \
		/obj/item/clothing/suit/lasertag/omni \
	))

/obj/machinery/porta_turret/lasertag/red
	turret_type = "red"
	installation = /obj/item/gun/energy/lasertag/red
	projectile = /obj/item/projectile/beam/lasertag/red

TYPE_TABLE(/obj/machinery/porta_turret/lasertag/red, turret_vests_to_target, list( \
		/obj/item/clothing/suit/lasertag/bluetag, \
		/obj/item/clothing/suit/lasertag/omni \
	))

/obj/machinery/porta_turret/lasertag/blue
	turret_type = "blue"
	installation = /obj/item/gun/energy/lasertag/blue
	projectile = /obj/item/projectile/beam/lasertag/blue

TYPE_TABLE(/obj/machinery/porta_turret/lasertag/blue, turret_vests_to_target, list( \
		/obj/item/clothing/suit/lasertag/redtag, \
		/obj/item/clothing/suit/lasertag/omni \
	))

/obj/machinery/porta_turret/lasertag/omni
	turret_type = "industrial"

/obj/machinery/porta_turret/lasertag/assess_living(mob/living/L)
	if(emag_emagged(src))	// FUCK YOU, PERISH
		return L.stat ? TURRET_NOT_TARGET : TURRET_PRIORITY_TARGET //we won't be uber evil though. If you're KO'd, let's let you get back up.

	if(!ishuman(L))
		return TURRET_NOT_TARGET

	if(L.invisibility >= INVISIBILITY_LEVEL_ONE) // Cannot see him. see_invisible is a mob-var
		return TURRET_NOT_TARGET

	if(get_dist(src, L) > 7)	//if it's too far away, why bother?
		return TURRET_NOT_TARGET

	if(ishuman(L))
		var/mob/living/carbon/human/M = L
		if(is_type_in_list(M.get_equipped_item(SLOT_ID_SUIT), TYPE_TABLE_GET(src, turret_vests_to_target))) // Checks if they are a red player
			var/obj/item/clothing/suit/lasertag/tag_suit = M.get_equipped_item(SLOT_ID_SUIT)
			if(tag_suit.lasertag_health > 0)
				return TURRET_PRIORITY_TARGET
		return TURRET_NOT_TARGET

/// A lasertag turret's window shows only the settings it has (the parent's list of targets does not apply to it).
/obj/machinery/porta_turret/lasertag/ui_data(datum/act/eval/A)
	var/list/data = list(
		"locked" = lock_locked(src),
		"on" = enabled, // is turret turned on?
		"lethal" = lethal,
		"lethal_is_configurable" = lethal_is_configurable
	)
	return data


/obj/machinery/porta_turret/proc/setup()
	var/obj/item/gun/energy/E = installation	//All energy-based weapons are applicable
	var/obj/item/projectile/P = initial(E.projectile_type)

	projectile = P
	if(!lethal_projectile)
		lethal_projectile = projectile
	shot_sound = initial(P.fire_sound)
	if(!lethal_shot_sound)
		lethal_shot_sound = shot_sound

	if(istype(P, /obj/item/projectile/energy))
		set_icon_color("orange")

	else if(istype(P, /obj/item/projectile/beam/stun))
		set_icon_color("blue")

	else if(istype(P, /obj/item/projectile/beam/lasertag))
		set_icon_color("blue")

	else if(istype(P, /obj/item/projectile/beam))
		set_icon_color("red")

	else
		set_icon_color("blue")

	set_lethal_icon_color(icon_color)

	weapon_setup(installation)

/obj/machinery/porta_turret/proc/weapon_setup(guntype)
	switch(guntype)
		if(/obj/item/gun/energy/gun/burst)
			set_lethal_icon_color("red")
			lethal_projectile = /obj/item/projectile/beam/burstlaser
			lethal_shot_sound = SFX_WEAPONS_LASER
			shot_delay = 1 SECOND

		if(/obj/item/gun/energy/locked/phasegun/unlocked)
			set_icon_color("orange")
			set_lethal_icon_color("orange")
			lethal_projectile = /obj/item/projectile/energy/phase/heavy
			shot_delay = 1 SECOND

		if(/obj/item/gun/energy/gun)
			set_lethal_icon_color("red")
			lethal_projectile = /obj/item/projectile/beam	//If it has, going to kill mode
			lethal_shot_sound = SFX_WEAPONS_LASER

		if(/obj/item/gun/energy/gun/nuclear)
			set_lethal_icon_color("red")
			lethal_projectile = /obj/item/projectile/beam	//If it has, going to kill mode
			lethal_shot_sound = SFX_WEAPONS_LASER

		if(/obj/item/gun/energy/xray)
			set_lethal_icon_color("green")
			lethal_projectile = /obj/item/projectile/beam/xray
			projectile = /obj/item/projectile/beam/stun // Otherwise we fire xrays on both modes.
			lethal_shot_sound = SFX_WEAPONS_ELUGER
			shot_sound = SFX_WEAPONS_TASER


/obj/machinery/porta_turret/proc/assess_living(mob/living/L)
	if(!istype(L))
		return TURRET_NOT_TARGET

	if(L.invisibility >= INVISIBILITY_LEVEL_ONE) // Cannot see him. see_invisible is a mob-var
		return TURRET_NOT_TARGET

	if(faction && L.faction == faction)
		return TURRET_NOT_TARGET

	// ALLOW(silicon_entry): a target filter, not an op: a turret spares silicons unless told to shoot everything
	if((!emag_emagged(src) && siliconaccess(L) && check_all == FALSE) || (issilicon(L) && !check_access && !check_all))	// Don't target silica, unless told to neutralize everything.
		return TURRET_NOT_TARGET

	if(L.stat == DEAD && !emag_emagged(src))		//if the perp is dead, no need to bother really
		return TURRET_NOT_TARGET	//move onto next potential victim!

	if(get_dist(src, L) > 7)	//if it's too far away, why bother?
		return TURRET_NOT_TARGET

	if(emag_emagged(src))		// If emagged not even the dead get a rest
		return L.stat ? TURRET_SECONDARY_TARGET : TURRET_PRIORITY_TARGET

	if(lethal && locate_within(get_turf(L), /mob/living/silicon/ai))		//don't accidentally kill the AI!
		return TURRET_NOT_TARGET

	if(check_synth || check_all)	//If it's set to attack all non-silicons or everything, target them!
		if(L.lying && (L.incapacitated(INCAPACITATION_KNOCKOUT) || L.incapacitated(INCAPACITATION_STUNNED))) // Crawling targets are dangerous, if they are able.
			return check_down ? TURRET_SECONDARY_TARGET : TURRET_NOT_TARGET
		return TURRET_PRIORITY_TARGET

	if(iscuffed(L)) // If the target is handcuffed, leave it alone
		return TURRET_NOT_TARGET

	if(isanimal(L)) // Animals are not so dangerous
		return check_anomalies ? TURRET_SECONDARY_TARGET : TURRET_NOT_TARGET

	if(isxenomorph(L) || isalien(L)) // Xenos are dangerous
		return check_anomalies ? TURRET_PRIORITY_TARGET	: TURRET_NOT_TARGET

	if(ishuman(L))	//if the target is a human, analyze threat level
		if(assess_perp(L) < 4)
			return TURRET_NOT_TARGET	//if threat level < 4, keep going

	if(L.lying && (L.incapacitated(INCAPACITATION_KNOCKOUT) || L.incapacitated(INCAPACITATION_STUNNED)))		//if the perp is lying down, it's still a target but a less-important target - Crawling targets are dangerous, if they are able.
		return check_down ? TURRET_SECONDARY_TARGET : TURRET_NOT_TARGET

	return TURRET_PRIORITY_TARGET	//if the perp has passed all previous tests, congrats, it is now a "shoot-me!" nominee

/obj/machinery/porta_turret/proc/assess_mecha(obj/mecha/M)
	if(!istype(M))
		return TURRET_NOT_TARGET

	if(!M?.slot_item(MECHA_SLOT_PILOT))
		return check_all ? TURRET_SECONDARY_TARGET : TURRET_NOT_TARGET

	return assess_living(M?.slot_item(MECHA_SLOT_PILOT))

/obj/machinery/porta_turret/proc/assess_perp(mob/living/carbon/human/H)
	if(!H || !istype(H))
		return 0

	if(emag_emagged(src))
		return 10

	return H.assess_perp(src, check_access, check_weapons, check_records, check_arrest)

/obj/machinery/porta_turret/proc/tryToShootAt(list/mob/living/targets)
	if(targets.len && last_target && (last_target in targets) && target(last_target))
		return TRUE

	while(targets.len > 0)
		var/mob/living/M = pick(targets)
		targets -= M
		if(target(M))
			return TRUE

	return FALSE


/obj/machinery/porta_turret/proc/shootAt(mob/living/target)
	//any emagged turrets will shoot extremely fast! This not only is deadly, but drains a lot power!
	var/current_delay = shot_delay
	var/emagged_now = emag_emagged(src)
	if(emagged_now || attacked)	//prevents rapid-fire shooting, unless it's been emagged
		current_delay = min(shot_delay,TURRET_EMAG_FIRERATE) // Emag fire rate

	// Can't fire until our reload finishes, AND we have fully raised up.
	if(last_fired || !popup_cover_raised(src))
		return
	last_fired = TRUE
	after(src, current_delay, PROC_REF(shot_reload), key = "reload")

	if(!isturf(get_turf(src)) || !isturf(get_turf(target)))
		return

	var/obj/item/projectile/A
	if(emagged_now || lethal)
		A = new lethal_projectile(loc)
		playsound(src, lethal_shot_sound, 75, 1)
	else
		A = new projectile(loc)
		playsound(src, shot_sound, 75, 1)

	var/power_mult = 1
	if(emagged_now)
		power_mult = 4 // Lethal beams + higher rate of fire
	else if(lethal)
		power_mult = 2 // Lethal beams
	use_power(reqpower * power_mult)

	//Turrets aim for the center of mass by default.
	//If the target is grabbing someone then the turret smartly aims for extremities
	var/def_zone
	var/obj/item/grab/G = locate_within(target, /obj/item/grab)
	if(G && G.state >= GRAB_NECK) //works because mobs are currently not allowed to upgrade to NECK if they are grabbing two people.
		def_zone = pick(BP_HEAD, BP_L_HAND, BP_R_HAND, BP_L_FOOT, BP_R_FOOT, BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG)
	else
		def_zone = pick(BP_TORSO, BP_GROIN)

	//Shooting Code:
	rel_set(A, nameof(A.firer), src)
	A.old_style_target(target)
	A.launch_projectile_from_turf(target, def_zone, src)

/obj/machinery/porta_turret/proc/shot_reload()
	last_fired = FALSE

// ---- what a control panel sets ----

/// The targets a pulse scrambles, the same way for a turret and for its control panel: each targeting check flips a coin, the access check only one
/// time in five (it is a big deal). Written through the holder's setters.
/proc/turret_targets_scramble(datum/D)
	var/list/values = list(
		"check_arrest" = prob(50),
		"check_records" = prob(50),
		"check_weapons" = prob(50),
		"check_access" = prob(20),
		"check_anomalies" = prob(50))
	for(var/name in values)
		call(D, "set_[name]")(values[name])

/// The settings a control panel hands its turrets.
/datum/turret_checks
	var/enabled
	var/lethal
	var/check_synth
	var/check_access
	var/check_records
	var/check_arrest
	var/check_weapons
	var/check_anomalies
	var/check_all
	var/check_down

/// A control panel's settings arrive; a turret an emag locked away from its panels keeps its own.
/obj/machinery/porta_turret/proc/setState(datum/turret_checks/TC)
	if(controllock)
		return
	set_enabled(TC.enabled)
	set_lethal(TC.lethal)
	set_check_synth(TC.check_synth)
	set_check_access(TC.check_access)
	set_check_records(TC.check_records)
	set_check_arrest(TC.check_arrest)
	set_check_weapons(TC.check_weapons)
	set_check_anomalies(TC.check_anomalies)
	set_check_all(TC.check_all)
	set_check_down(TC.check_down)

/*
		Portable turret constructions
		Known as "turret frame"s
*/

STAGE_DEF(turret_frame, loose)
STAGE_DEF(turret_frame, bolted)
STAGE_DEF(turret_frame, plated)
STAGE_DEF(turret_frame, secured)
STAGE_DEF(turret_frame, armed)
STAGE_DEF(turret_frame, sensing)
STAGE_DEF(turret_frame, shut)
STAGE_DEF(turret_frame, armoured)
STAGE_DEF(turret_frame, done)

MSG_DEF_SELF(stage/turret_frame/loose, "It's a loose turret frame.")
MSG_DEF_SELF(stage/turret_frame/bolted, "It is bolted down; it needs interior armour.")
MSG_DEF_SELF(stage/turret_frame/plated, "Its interior armour wants bolting in place.")
MSG_DEF_SELF(stage/turret_frame/secured, "It wants an energy weapon.")
MSG_DEF_SELF(stage/turret_frame/armed, "It has its weapon; it wants a proximity sensor.")
MSG_DEF_SELF(stage/turret_frame/sensing, "Its internal access hatch is open.")
MSG_DEF_SELF(stage/turret_frame/shut, "Its hatch is shut; it wants exterior armour.")
MSG_DEF_SELF(stage/turret_frame/armoured, "Its exterior armour wants welding down.")
MSG_DEF_SELF(stage/turret_frame/done, "It is finished.")
MSG_DEF_SELF(turret_frame/stuck_gun, "It is stuck to your hand, you cannot put it in the frame.")

/// The turret frame's ladder: bolted, plated inside, the plating bolted, a gun, a proximity sensor, the hatch shut, plated outside and welded into
/// a turret with that gun, switched off and named as the builder chose. Each step undoes by its own tool (the gun and the sensor come out by hand);
/// a loose frame pries apart into its five sheets.
/proc/turret_frame()
	return construction(start(STAGE_TURRET_FRAME_LOOSE),
		stage(STAGE_TURRET_FRAME_BOLTED, tool(TOOL_WRENCH), wait(0),
			then(TYPE_PROC_REF(/obj/machinery/porta_turret_construct, bolted_down)), undone(TYPE_PROC_REF(/obj/machinery/porta_turret_construct, bolted_up)),
			undo = list(tool(TOOL_WRENCH), wait(0))),
		stage(STAGE_TURRET_FRAME_PLATED, stack(/obj/item/stack/material/steel, 2), wait(0), undo = list(tool(TOOL_WELDER), wait(2 SECONDS))),
		stage(STAGE_TURRET_FRAME_SECURED, tool(TOOL_WRENCH), wait(0), undo = list(tool(TOOL_WRENCH), wait(0))),
		stage(STAGE_TURRET_FRAME_ARMED, item(/obj/item/gun/energy), put_in(SLOT_CONSTRUCTION)),
		stage(STAGE_TURRET_FRAME_SENSING, item(/obj/item/assembly/prox_sensor), put_in(SLOT_CONSTRUCTION)),
		stage(STAGE_TURRET_FRAME_SHUT, tool(TOOL_SCREWDRIVER), wait(0), undo = list(tool(TOOL_SCREWDRIVER), wait(0))),
		stage(STAGE_TURRET_FRAME_ARMOURED, stack(/obj/item/stack/material/steel, 2), wait(0), undo = list(tool(TOOL_CROWBAR), wait(0), when(nameof(/atom/movable::anchored)))),
		stage(STAGE_TURRET_FRAME_DONE, tool(TOOL_WELDER), wait(3 SECONDS), then(TYPE_PROC_REF(/obj/machinery/porta_turret_construct, finished))),
		dismantle(tool(TOOL_CROWBAR), wait(0), when(cond_not(nameof(/atom/movable::anchored))),
			spawns(/obj/item/stack/material/steel, 5)))

/obj/machinery/porta_turret_construct
	name = "turret frame"
	icon = 'icons/obj/turrets.dmi'
	icon_state = "turret_frame"
	density = TRUE
	anchored = FALSE
	var/target_type = /obj/machinery/porta_turret	// The type we intend to build
	var/finish_name = "turret"	//the name applied to the product turret

CAPABILITIES(/obj/machinery/porta_turret_construct)
	turret_frame()
	op("rename", item(/obj/item/pen), wait(0), asks(/datum/prompt/text/turret_name), then(PROC_REF(renamed)))

/// The name a builder gives the turret to come.
/datum/prompt/text/turret_name
	question = "Enter new turret name"
	max_len = MAX_NAME_LEN
	name_text = TRUE
	encode = FALSE

/// The frame bolted to the floor, or unbolted again.
/obj/machinery/porta_turret_construct/proc/bolted_down(datum/act/op/A)
	set_anchored(TRUE)
	return OP_OK

/obj/machinery/porta_turret_construct/proc/bolted_up(datum/act/op/A)
	set_anchored(FALSE)
	return OP_OK

/// The look follows the build: plated inside, the frame shows its armour.
/obj/machinery/porta_turret_construct/draw(datum/look/look)
	..()
	look.state(built(src, STAGE_TURRET_FRAME_PLATED) ? "turret_frame2" : "turret_frame")

/obj/machinery/porta_turret_construct/proc/renamed(datum/act/op/A)
	var/datum/prompt/P = A.answer
	var/t = sanitizeSafe(P?.value, MAX_NAME_LEN)
	if(t)
		finish_name = t
	return OP_OK

/// The armour is welded down: the turret is made from the frame, with the gun that went in (its type and charge), switched off.
/obj/machinery/porta_turret_construct/proc/finished(datum/act/op/A)
	var/obj/item/gun/energy/gun = locate_within(src, /obj/item/gun/energy)
	var/obj/machinery/porta_turret/Turret = new target_type(loc)
	Turret.name = finish_name
	if(gun)
		Turret.installation = gun.type
		Turret.gun_charge = gun.power_supply?.charge
	Turret.set_enabled(FALSE)
	Turret.setup()
	replace_with(src, Turret)
	return OP_OK

// === merged from portable_turret_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/porta_turret/stationary/CIWS
	name = "CIWS turret"
	desc = "A ship weapons turret designed for light defense."
	req_one_access = list(ACCESS_CENT_GENERAL)
	max_integrity = 200
	enabled = TRUE
	lethal = TRUE
	check_weapons = TRUE
	can_salvage = FALSE

/obj/machinery/porta_turret/stationary/syndie/CIWS
	name = "mercenary CIWS turret"
	desc = "A ship weapons turret designed for light defense."
	req_one_access = list(ACCESS_SYNDICATE)
	max_integrity = 200
	enabled = TRUE
	lethal = TRUE
	check_weapons = TRUE
	can_salvage = FALSE

/obj/machinery/porta_turret/industrial/military
	name = "military CIWS turret"
	desc = "A ship weapons turret designed for anti-fighter defense."
	req_one_access = list(ACCESS_CENT_GENERAL)
	installation = /obj/item/gun/energy/pulse_rifle/destroyer
	max_integrity = 500
	enabled = TRUE
	lethal = TRUE
	check_weapons = TRUE
	auto_repair = TRUE
	can_salvage = FALSE

// === merged from portable_turret_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/porta_turret/rcd
	desc = "A cheap turret printed by a rapid construction device with its own power supply. Not very sturdy, but it still hurts."
	use_power = FALSE
	idle_power_usage = 0
	active_power_usage = 0
	max_integrity = 20	//extremely brittle
	reqpower = 0
	enabled = TRUE
	lethal = TRUE
	ailock = FALSE
	check_all = TRUE
	can_salvage = FALSE
	check_down = TRUE


// Printed pre-stressed: starts at a sliver of integrity ("extremely brittle").
// ALLOW(init/INSTANCE_STATE): an RCD-printed turret starts at a sliver of its integrity
/obj/machinery/porta_turret/rcd/Initialize(mapload)
	. = ..()
	update_integrity(5)

/// Runs on its own supply: only BROKEN and EMPED stop it, never its area's power (neither the grid's reading nor the capacitors' delay applies).
CAPABILITIES(/obj/machinery/porta_turret/rcd)
	without("turret_power") // ALLOW(keys): without() drops an inherited contributes() entry by its key, not an op
	configure(machine_basics(repair = NONE, powered = FALSE))

/obj/machinery/porta_turret/rcd/power_change()
	return

/obj/machinery/porta_turret/rcd/stat_bits_allow(datum/act/A)
	return !has_stat(BROKEN | EMPED)

/// It sees through walls.
/obj/machinery/porta_turret/rcd/scan_candidates()
	return mobs_in_xray_view(world.view, src)

/obj/machinery/porta_turret/rcd/appearance_prefix()
	if(has_stat(BROKEN))
		return "destroyed_target_prism_"
	if(popup_cover_raised(src) || popup_cover_moving(src))
		if(enabled)
			return "[lethal ? lethal_icon_color : icon_color]_target_prism_"
		return "grey_target_prism_"
	return "turret_cover_"

/obj/machinery/porta_turret/rcd/die()
	fx_sparks(src, 5, FALSE)
	destroyed(src)

#undef TURRET_PRIORITY_TARGET
#undef TURRET_SECONDARY_TARGET
#undef TURRET_NOT_TARGET
#undef TURRET_RETALIATION_TIME
#undef TURRET_EMAG_FIRERATE
#undef TURRET_SCAN_ENGAGED
#undef TURRET_SCAN_IDLE
