/obj/item/organ/internal/heart/machine/anomalock
	name = "voltaic combat cyberheart"
	desc = "A cutting-edge cyberheart. Voltaic technology allows the heart to keep the body upright in dire circumstances, alongside redirecting anomalous flux energy to fully shield the user from shocks and electro-magnetic pulses. Requires a Flux core as a power source."
	icon_state = "anomalock_heart"
	organ_tag = O_HEART

	COOLDOWN_DECLARE(survival_cooldown)
	///Cooldown for the activation of the organ
	var/survival_cooldown_time = 10 MINUTES
	///The lightning effect on our mob when the implant is active
	var/mutable_appearance/lightning_overlay
	///how long the lightning lasts
	var/lightning_timer

	///The core item the organ runs off.
	var/obj/item/assembly/signaler/anomaly/core
	///Accepted types of anomaly cores.
	var/required_anomaly = /obj/item/assembly/signaler/anomaly/flux
	///If this one starts with a core in.
	var/prebuilt = FALSE
	///If the core is removable once socketed.
	var/core_removable = TRUE

REF_OWNED(/obj/item/organ/internal/heart/machine/anomalock, list("core", "lightning_overlay"))

/obj/item/organ/internal/heart/machine/anomalock/handle_organ_mod_special(removed)
	if(!core)
		return

	if(!removed)
		add_lightning_overlay(30 SECONDS)
		playsound(owner, 'sound/machines/defib_zap.ogg', 50, TRUE, -1)
		owner.emp_protection_flags |= EMP_PROTECT_SELF|EMP_PROTECT_CONTENTS
		om_hook(owner, /datum/om/event/trait_gained, src, PROC_REF(on_owner_trait_gained))
		om_hook(owner, /datum/om/event/atom_emp_act, src, PROC_REF(on_emp_act))

	if(removed)
		clear_lightning_overlay(owner)
		om_unhook(owner, /datum/om/event/trait_gained, src)
		om_unhook(owner, /datum/om/event/atom_emp_act, src)
		owner.emp_protection_flags &= ~(EMP_PROTECT_SELF|EMP_PROTECT_CONTENTS)
		tesla_zap(owner, 10, 2500, current_jumps = 5)
		expire(0)

	..(removed)

/obj/item/organ/internal/heart/machine/anomalock/proc/add_lightning_overlay(time_to_last = 10 SECONDS)
	if(lightning_overlay)
		lightning_timer = om_after_replace(src, time_to_last, PROC_REF(clear_lightning_overlay), owner)
		return
	lightning_overlay = mutable_appearance(icon = 'icons/effects/effects.dmi', icon_state = "lightning")
	owner.add_overlay(lightning_overlay)
	lightning_timer = om_after_replace(src, time_to_last, PROC_REF(clear_lightning_overlay), owner)

/obj/item/organ/internal/heart/machine/anomalock/proc/clear_lightning_overlay(mob/organ_owner)
	organ_owner?.cut_overlay(lightning_overlay)
	if(lightning_timer)
		om_cancel_timer(src, lightning_timer)
	lightning_overlay = null

/// Event wrapper: the owner gained a trait; only critical condition triggers survival mode.
/obj/item/organ/internal/heart/machine/anomalock/proc/on_owner_trait_gained(mob/living/carbon/source, datum/om/event/trait_gained/event)
	EVENT_HANDLER
	if(event.trait != TRAIT_CRITICAL_CONDITION)
		return
	activate_survival(source)

/obj/item/organ/internal/heart/machine/anomalock/proc/activate_survival(mob/living/carbon/organ_owner)
	if(!COOLDOWN_FINISHED(src, survival_cooldown))
		return FALSE

	organ_owner.apply_body_effect(/datum/body_effect/voltaic_overdrive, 30 SECONDS)
	add_lightning_overlay(30 SECONDS)
	COOLDOWN_START(src, survival_cooldown, survival_cooldown_time)
	om_after(src, COOLDOWN_TIMELEFT(src, survival_cooldown), PROC_REF(notify_cooldown), organ_owner)
	return TRUE

/obj/item/organ/internal/heart/machine/anomalock/proc/notify_cooldown(mob/living/carbon/organ_owner)
	balloon_alert(organ_owner, "your heart strengthtens")
	playsound(owner, 'sound/machines/defib_zap.ogg', 40)

/obj/item/organ/internal/heart/machine/anomalock/proc/on_emp_act(datum/source, datum/om/event/atom_emp_act/event)
	EVENT_HANDLER
	add_lightning_overlay(10 SECONDS)

EXTEND_INTERACTIONS(/obj/item/organ/internal/heart/machine/anomalock, INTERACT_ITEM(null, PROC_REF(anomalock_interaction_item)))

/// Old attackby.
/obj/item/organ/internal/heart/machine/anomalock/proc/anomalock_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, required_anomaly))
		if(core)
			balloon_alert(user, "core already in!")
			return INTERACTION_HANDLED_PASS
		om_task_timed(user, 3 SECONDS, src, src, PROC_REF(install_core), list(user, W))
		return TRUE

	if(W.has_tool_quality(IS_SCREWDRIVER))
		if(!core)
			balloon_alert(user, "no core!")
			return INTERACTION_HANDLED_PASS
		if(!core_removable)
			balloon_alert(user, "can't remove core!")
			return INTERACTION_HANDLED_PASS
		balloon_alert(user, "removing core...")
		om_task_start(/datum/om/task/timed/anomalock_remove_core, user, src, receiver = src)
		return TRUE

	return FALSE

/obj/item/organ/internal/heart/machine/anomalock/proc/install_core(mob/user, obj/item/W)
	if(core || W.loc != user)
		return
	user.unEquip(W, TRUE, src)
	core = W
	balloon_alert(user, "core_installed")
	playsound(src, 'sound/machines/click.ogg')
	update_icon()

/datum/om/task/timed/anomalock_remove_core
	duration = 3 SECONDS
	complete_proc = /obj/item/organ/internal/heart/machine/anomalock/proc/remove_core
	cancel_proc = /obj/item/organ/internal/heart/machine/anomalock/proc/remove_core_interrupted

/obj/item/organ/internal/heart/machine/anomalock/proc/remove_core_interrupted(datum/om/task/timed/anomalock_remove_core/task)
	balloon_alert(task.actor, "interrupted!")

/obj/item/organ/internal/heart/machine/anomalock/proc/remove_core(datum/om/task/timed/anomalock_remove_core/task)
	var/mob/user = task.actor
	if(!core)
		return
	balloon_alert(user, "core removed")
	core.forceMove(drop_location())
	if(Adjacent(user) && !issilicon(user))
		user.put_in_hands(core)
	core = null
	update_icon()

/obj/item/organ/internal/heart/machine/anomalock/prebuilt/Initialize(mapload, internal)
	. = ..()
	core = new /obj/item/assembly/signaler/anomaly/flux(src)
	update_icon()

/obj/item/organ/internal/heart/machine/anomalock/update_icon()
	. = ..()
	icon_state = initial(icon_state) + (core ? "-core" : "")

/datum/body_effect/voltaic_overdrive
	stacks = MODIFIER_STACK_FORBID
	name = "voltaic_overdrive"
	client_color = "#e9f76b"
	factors = alist(BF_PAIN_IMMUNITY = 1)
	tick_interval = 2 SECONDS

/datum/body_effect/voltaic_overdrive/on_tick(mob/living/L)
	var/mob/living/holder = L
	if(!holder.is_critical())
		return

	holder.mend(TREAT_TISSUE_REPAIR, 5)
	holder.mend(TREAT_BURN_CARE, 5)
	holder.mend(TREAT_PLATING_REPAIR, 5)
	holder.mend(TREAT_WIRING_REPAIR, 5)
	holder.mend(TREAT_OXYGENATION, 5)
	holder.mend(TREAT_ANTITOXIN, 5)
	holder.mend(TREAT_ANALGESIC, 5)
	holder.status_adjust(EFFECT_WEAKENED, -5)
	holder.status_adjust(EFFECT_SLEEPING, -5)
	holder.status_adjust(EFFECT_STUNNED, -5)
	holder.status_set(EFFECT_BLURRY, 0)

/datum/body_effect/voltaic_overdrive/on_start(mob/living/L)
	. = ..()
	REMOVE_TRAIT(L, TRAIT_CRITICAL_CONDITION, STAT_TRAIT)
	L.reagents.add_reagent(REAGENT_ID_MYELAMINE, 5)
	to_chat(L, span_userdanger("You feel a burst of energy! It's do or die!"))

/datum/body_effect/voltaic_overdrive/on_end(mob/living/L, expired)
	. = ..()
	L.balloon_alert(L, "your heart weakens")
