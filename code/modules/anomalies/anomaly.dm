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

CAPABILITIES(/obj/item/anomaly_neutralizer)
	owns_one(nameof(effect_remover), /datum/effect_remover)

/obj/item/anomaly_neutralizer/Initialize(mapload)
	. = ..()

	rel_set(src, nameof(effect_remover), new /datum/effect_remover(src, \
		success_feedback = "You neutralize %THEEFFECT with %THEWEAPON, frying its circuitry in the process.", \
		on_clear_callback = om_callable(src, PROC_REF(on_anomaly_neutralized)), \
		effects_we_clear = list(/obj/effect/anomaly)))

/obj/item/anomaly_neutralizer/proc/on_anomaly_neutralized(obj/effect/anomaly/target, mob/living/user)
	target.anomalyNeutralize()
	on_use(target, user)

/obj/item/anomaly_neutralizer/proc/on_use(obj/effect/target, mob/living/user)
	fx_sparks(src, 3)
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

/obj/item/anomaly_scanner/get_mechanics_info(list/additional_information)
	return ..(list("Danger type adds severity. Unstable changes state. Containment stabilizes at the cost of health. Transformation adds modifiers.") + additional_information)

/obj/item/anomaly_scanner
	name = "anomaly scanner"
	desc = "A hand-held anomaly scanner, able to distinguish the particles that might affect a stable anomaly."
	icon = 'icons/obj/device.dmi'
	icon_state = "anom_scanner"
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL
	throw_speed = 5
	throw_range = 10
	MATERIAL_BULK(MAT_STEEL, 200)

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

	/// Relation view: the last anomaly scanned (set by the anomaly's scan, _anomalies.dm).
	var/obj/effect/anomaly/buffered_anomaly

CAPABILITIES(/obj/item/anomaly_scanner)
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	interface("AnomalyScanner")
	without("ui_open")
	ui_shape(anomaly_name = schema_text(), severity = num(), stability = num(), point_output = any, danger_type = any, unstable_type = any, containment_type = any, transformation_type = any, modifier = any, countdown = any)

/// Old attack_self.
/obj/item/anomaly_scanner/proc/interaction_self(datum/act/op/A)
	var/mob/living/user = A.actor
	tgui_interact(user)
	return TRUE

/obj/item/anomaly_scanner/tgui_static_data(mob/user)
	. = ..()
	if(isrobot(loc))
		var/mob/living/silicon/robot/robot_owner = loc
		.["theme"] = robot_owner.get_ui_theme()

/// /obj/item/anomaly_scanner's window data.
/obj/item/anomaly_scanner/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/obj/effect/anomaly/anom = buffered_anomaly

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
	fire_sound = SFX_WEAPONS_TASER2
	recoil_mode = 0
	accuracy = 30

	var/particle = ANOMALY_PARTICLE_SIGMA

/obj/item/gun/energy/anomaly/mounted
	name = "mounted particle gun"
	self_recharge = 1
	use_external_power = 1

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()): pick a particle, then the gun's own self-use.
/obj/item/gun/energy/anomaly/gun_self(mob/user, obj/item/held, datum/interaction/interaction, callback, chosen_particle)
	if(isnull(chosen_particle))
		var/original_client_ckey
		if(istype(user, /client))
			var/client/C = user
			original_client_ckey = C.ckey
			user = C.mob
		if(!ismob(user) || QDELETED(user))
			return TRUE
		open_request(src, /datum/prompt/choice/research_anomaly, PROC_REF(particle_selected), answerer = user, choices = ANOMALY_PARTICLE_ALL, question = "Select particle type", title = "Particle Selection", captured_item = held, captured_interaction = interaction, item_expected = !isnull(held), interaction_expected = !isnull(interaction), original_client_ckey = original_client_ckey, callback_value = isdatum(callback) ? null : callback, captured_callback = isdatum(callback) ? callback : null, callback_expected = isdatum(callback))
		return TRUE
	if(!chosen_particle)
		return FALSE

	particle = chosen_particle
	balloon_alert_visible("changed to [chosen_particle]")
	return ..(user, held, interaction, callback)

/obj/item/gun/energy/anomaly/proc/particle_selected(datum/act/request/A)
	var/datum/prompt/choice/research_anomaly/request = A.request
	if(!A.answer || request.captures_gone())
		return
	resume_particle_selection(A)
	SStgui.update_uis(src)

/obj/item/gun/energy/anomaly/proc/resume_particle_selection(datum/act/request/A)
	var/datum/prompt/choice/research_anomaly/request = A.request
	var/mob/user = request.user_value()
	var/callback = request.callback_expected ? request.captured_callback : request.callback_value
	gun_self(user, request.captured_item, request.captured_interaction, callback, A.answer.value)

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
/obj/item/assembly/signaler/anomaly/choice/interaction_self(mob/user, obj/item/held, datum/interaction/interaction, selected_core)
	. = ..(user, held, interaction)
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
			spent(anom, user) // only the type is kept; don't leak the sample object

	if(isnull(selected_core))
		var/original_client_ckey
		if(istype(user, /client))
			var/client/C = user
			original_client_ckey = C.ckey
			user = C.mob
		if(!ismob(user) || QDELETED(user))
			return TRUE
		open_request(src, /datum/prompt/choice/research_anomaly, PROC_REF(core_selected), answerer = user, choices = choices, question = "Choose an anomaly core.", title = "Anomaly Core Selection", captured_item = held, captured_interaction = interaction, item_expected = !isnull(held), interaction_expected = !isnull(interaction), original_client_ckey = original_client_ckey)
		return TRUE
	var/choice = selected_core

	if(choice && !picked)
		anomaly_type = choices[choice]
		picked = TRUE


/obj/item/assembly/signaler/anomaly/choice/proc/core_selected(datum/act/request/A)
	var/datum/prompt/choice/research_anomaly/request = A.request
	if(!A.answer || request.captures_gone())
		return
	resume_core_selection(A)
	SStgui.update_uis(src)

/obj/item/assembly/signaler/anomaly/choice/proc/resume_core_selection(datum/act/request/A)
	var/datum/prompt/choice/research_anomaly/request = A.request
	interaction_self(request.user_value(), request.captured_item, request.captured_interaction, A.answer.value)

/datum/prompt/choice/research_anomaly
	timeout = 0
	var/obj/item/captured_item
	var/datum/interaction/captured_interaction
	var/datum/captured_callback
	var/item_expected = FALSE
	var/interaction_expected = FALSE
	var/callback_expected = FALSE
	var/callback_value
	var/original_client_ckey

CAPABILITIES(/datum/prompt/choice/research_anomaly)
	ref_one(nameof(captured_item), /obj/item)
	ref_one(nameof(captured_interaction), /datum/interaction)
	ref_one(nameof(captured_callback), /datum)

/datum/prompt/choice/research_anomaly/prepare(datum/act/A)
	. = ..()
	var/obj/item/item = captured_item
	var/datum/interaction/interaction = captured_interaction
	var/datum/callback = captured_callback
	rel_clear(src, nameof(captured_item))
	rel_clear(src, nameof(captured_interaction))
	rel_clear(src, nameof(captured_callback))
	rel_set(src, nameof(captured_item), item)
	rel_set(src, nameof(captured_interaction), interaction)
	rel_set(src, nameof(captured_callback), callback)

/datum/prompt/choice/research_anomaly/proc/user_value()
	return original_client_ckey ? GLOB.directory[original_client_ckey] : answerer

/datum/prompt/choice/research_anomaly/proc/captures_gone()
	return QDELETED(answerer) || (item_expected && QDELETED(captured_item)) || (interaction_expected && QDELETED(captured_interaction)) || (callback_expected && QDELETED(captured_callback)) || (original_client_ckey && !GLOB.directory[original_client_ckey])

/datum/prompt/choice/research_anomaly/recheck_extra()
	. = ..()
	if(.)
		return
	if(captures_gone())
		return "gone"
	return null
