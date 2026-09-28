/obj/item/anomaly_neutralizer
	name = "anomaly neutralizer"
	desc = "A one-use device capable of instantly neutralizing anomalous or otherworldly entities."
	icon = 'icons/obj/devices/tool.dmi'
	icon_state = "neutralyzer"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT
	item_flags = NOBLUDGEON

/// Owned: lets us delete anomalies we hit (was the effect_remover component).
/obj/item/anomaly_neutralizer/var/datum/effect_remover/effect_remover
DECLARE_REF(/obj/item/anomaly_neutralizer, "effect_remover", OWNED, null)

/obj/item/anomaly_neutralizer/Initialize(mapload)
	. = ..()

	effect_remover = new /datum/effect_remover(src, \
		success_feedback = "You neutralize %THEEFFECT with %THEWEAPON, frying its circuitry in the process.", \
		on_clear_callback = CALLBACK(src, PROC_REF(on_anomaly_neutralized)), \
		effects_we_clear = list(/obj/effect/anomaly))

/obj/item/anomaly_neutralizer/proc/on_anomaly_neutralized(obj/effect/anomaly/target, mob/living/user)
	target.anomalyNeutralize()
	on_use(target, user)

/obj/item/anomaly_neutralizer/proc/on_use(obj/effect/target, mob/living/user)
	var/datum/effect/effect/system/spark_spread/sparks = new /datum/effect/effect/system/spark_spread
	sparks.set_up(3, 1, src)
	sparks.start()
	consume(src, user)

/obj/item/anomaly_releaser
	icon = 'icons/obj/devices/syndie_gadget.dmi'
	icon_state = "anomaly_releaser"
	name = "advanced anomaly releaser"
	desc = "Single-use injector that releases and stabilizes anomalies by injecting an unknown substance."
	throwforce = 0
	w_class = ITEMSIZE_SMALL
	throw_speed = 3
	throw_range = 5

	///icon state after being used up
	var/used_icon_state = "anomaly_releaser_used"
	///are we used? if used we can't be used again
	var/used = FALSE
	///Can we be used infinitely?
	var/infinite = FALSE
	//If the created anomaly leaves a core behind
	var/has_core = TRUE
	//If this will anchor the anomaly in place
	var/will_anchor = TRUE
	// If it will apply stats to it
	var/gives_stats = TRUE

/obj/item/anomaly_releaser/science
	icon = 'icons/obj/devices/tool.dmi'
	icon_state = "sci_releaser"
	name = "scientific anomaly releaser"
	used_icon_state = "sci_releaser_used"
	has_core = FALSE

// The one for antags and evil-doers
/obj/item/anomaly_releaser/antag
	has_core = TRUE
	will_anchor = TRUE
	gives_stats = FALSE // Evil and fucked up...
	desc = "Single-use injector that releases and stabilizes anomalies by injecting an unknown substance. This one seems odd."

/obj/item/anomaly_scanner
	name = "anomaly scanner"
	desc = "A hand-held anomaly scanner, able to distinguish the particles that might affect a stable anomaly."
	description_info = "Click on an emitter to change into an anomalous emitter.<br>\
	Click on an anomaly harvester to link the scanned anomaly to it.<br>\
	Danger type adds severity. Unstable changes state. Containment stabilizes at the cost of health. Transformation adds modifiers."
	icon = 'icons/obj/device.dmi'
	icon_state = "anom_scanner"
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL
	throw_speed = 5
	throw_range = 10
	MATERIAL_BULK(MAT_STEEL, 200)

	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

	var/buffered_anomaly = null

DECLARE_INTERACTIONS(/obj/item/anomaly_scanner, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/anomaly_scanner/proc/interaction_self(mob/living/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

/obj/item/anomaly_scanner/tgui_static_data(mob/user)
	. = ..()
	if(isrobot(loc))
		var/mob/living/silicon/robot/robot_owner = loc
		.["theme"] = robot_owner.get_ui_theme()

/obj/item/anomaly_scanner/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AnomalyScanner", name)
		ui.open()

/obj/item/anomaly_scanner/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/obj/effect/anomaly/anom = om_resolve(buffered_anomaly)

	if(!istype(anom))
		return data

	var/datum/anomaly_stats/stats = anom.stats

	data["anomaly_name"] = anom.name
	data["severity"] = stats.severity
	data["stability"] = stats.stability
	data["point_output"] = stats.points
	data["danger_type"] = stats.danger_type
	data["unstable_type"] = stats.unstable_type
	data["containment_type"] = stats.containment_type
	data["transformation_type"] = stats.transformation_type
	if(stats.modifier)
		data["modifier"] = stats.modifier.get_description()
	data["countdown"] = stats.get_activation_countdown()

	return data

/obj/item/gun/energy/anomaly
	name = "anomalous particle gun"
	desc = "A handheld particle emitter, used to safely release a specific particle frequency."
	icon_state = "taserblue"
	fire_delay = 4
	projectile_type = /obj/item/projectile/energy/anomaly
	fire_sound = 'sound/weapons/taser2.ogg'
	recoil_mode = 0
	accuracy = 30

	var/particle = ANOMALY_PARTICLE_SIGMA

/obj/item/gun/energy/anomaly/mounted
	name = "mounted particle gun"
	self_recharge = 1
	use_external_power = 1

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()): pick a particle, then the gun's own self-use.
/obj/item/gun/energy/anomaly/gun_self(mob/user, obj/item/held, datum/interaction/interaction, callback)
	var/chosen_particle = rerun_ask(user, "k147", PROC_REF(gun_self), args, /datum/om/prompt/choice, message = "Select particle type", title = "Particle Selection", choices = ANOMALY_PARTICLE_ALL)
	if(isnull(chosen_particle))
		return TRUE
	if(!chosen_particle)
		return FALSE

	particle = chosen_particle
	balloon_alert_visible("changed to [chosen_particle]")
	return ..()

/obj/item/gun/energy/anomaly/consume_next_projectile()
	var/obj/item/cell/battery = power_supply

	if(use_external_power)
		battery = get_external_power_supply()

	if(!battery || !battery.checked_use(charge_cost))
		return null
	var/mob/living/M = loc
	if(istype(M))
		M.hud_used.update_ammo_hud(M, src)
	var/obj/item/projectile/energy/anomaly/projectile = new
	if(particle)
		projectile.particle_type = particle
	return projectile

/obj/item/storage/box/anomaly
	name = "anomaly harvesting kit"
	desc = "A box, stuffed with the needed tools to start harvesting an anomaly."
	icon_state = "alien"
	starts_with = list(
		/obj/item/anomaly_releaser,
		/obj/item/anomaly_scanner,
		/obj/item/assembly/signaler/anomaly/choice,
		/obj/item/clothing/gloves/black
	)

/obj/item/assembly/signaler/anomaly/choice
	name = "latent anomaly core"
	desc = "A supposedly inert anomaly core. It hums softly if held close."
	icon = 'icons/obj/assemblies/new_assemblies.dmi'
	icon_state = "inert"
	worth = 0
	var/options = 3
	var/list/choices
	var/picked = FALSE
	anomaly_type = /obj/effect/anomaly/flux // Default

/// Old attack_self (the assembly self-use chain: /obj/item/assembly/proc/interaction_self()).
/obj/item/assembly/signaler/anomaly/choice/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	. = ..()
	if(.)
		return TRUE

	if(picked)
		return TRUE

	if(isnull(choices))
		choices = list()
		var/list/core_types = subtypesof(/obj/effect/anomaly)

		for(var/i = 0, i < options, i++)
			var/type = pick_n_take(core_types)
			var/obj/effect/anomaly/anom = new type
			choices[capitalize(anom.name)] = type
			qdel(anom) // only the type is kept; don't leak the sample object

	var/choice = rerun_ask(user, "k211", PROC_REF(interaction_self), args, /datum/om/prompt/choice, message = "Choose an anomaly core.", title = "Anomaly Core Selection", choices = choices)
	if(isnull(choice))
		return TRUE

	if(choice && !picked)
		anomaly_type = choices[choice]
		picked = TRUE

