
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

	///The core item the organ runs off.
	var/obj/item/assembly/signaler/anomaly/core
	///Accepted types of anomaly cores.
	var/required_anomaly = /obj/item/assembly/signaler/anomaly/flux
	///If this one starts with a core in.
	var/prebuilt = FALSE
	///If the core is removable once socketed.
	var/core_removable = TRUE

CAPABILITIES(/obj/item/organ/internal/heart/machine/anomalock)
	owns_one(nameof(core), /obj/item/assembly/signaler/anomaly)
	op("install_core", item(/obj/item/assembly/signaler/anomaly), label("Install core"), when(req(PROC_REF(core_fits))), needs(req(PROC_REF(core_missing), because = MSG(anomalock/core_in))), wait(3 SECONDS), then(PROC_REF(install_core)))
	op("remove_core", tool(TOOL_SCREWDRIVER), label("Remove core"), needs(req(PROC_REF(core_present), because = MSG(anomalock/no_core)), req(PROC_REF(core_loose), because = MSG(anomalock/core_fixed))), begins(MSG(anomalock/removing)), wait(3 SECONDS), on_interrupt(PROC_REF(remove_core_interrupted)), then(PROC_REF(remove_core)))

MSG_DEF_SELF(anomalock/core_in, "core already in!")
MSG_DEF_SELF(anomalock/no_core, "no core!")
MSG_DEF_SELF(anomalock/core_fixed, "can't remove core!")
MSG_DEF_SELF(anomalock/removing, "removing core...")


/obj/item/organ/internal/heart/machine/anomalock/handle_organ_mod_special(removed)
	// a prebuilt heart runs this at creation, before it has an owner
	if(!core || !owner)
		return

	if(!removed)
		add_lightning_overlay(30 SECONDS)
		play_sfx(owner, SFX_MACHINES_DEFIB_ZAP)
		owner.emp_protection_flags |= EMP_PROTECT_SELF|EMP_PROTECT_CONTENTS
		observe(owner, /datum/notice/trait_gained, src, then(PROC_REF(on_owner_trait_gained)))
		observe(owner, /datum/notice/atom_emp_act, src, then(PROC_REF(on_emp_act)))

	if(removed)
		clear_lightning_overlay(owner)
		unobserve(owner, /datum/notice/trait_gained, src)
		unobserve(owner, /datum/notice/atom_emp_act, src)
		owner.emp_protection_flags &= ~(EMP_PROTECT_SELF|EMP_PROTECT_CONTENTS)
		tesla_zap(owner, 10, 2500, current_jumps = 5)
		expire(0)

	..(removed)

/obj/item/organ/internal/heart/machine/anomalock/proc/add_lightning_overlay(time_to_last = 10 SECONDS)
	if(lightning_overlay)
		after(src, time_to_last, PROC_REF(clear_lightning_overlay), key = "lightning_timer", with = list(owner), keeps_dead = TRUE)
		return
	lightning_overlay = mutable_appearance(icon = 'icons/effects/effects.dmi', icon_state = "lightning")
	owner.add_overlay(lightning_overlay)
	after(src, time_to_last, PROC_REF(clear_lightning_overlay), key = "lightning_timer", with = list(owner), keeps_dead = TRUE)

/obj/item/organ/internal/heart/machine/anomalock/proc/clear_lightning_overlay(mob/organ_owner)
	organ_owner?.cut_overlay(lightning_overlay)
	if(after_pending(src, "lightning_timer"))
		cancel_after(src, "lightning_timer")
	lightning_overlay = null

/// Event wrapper: the owner gained a trait; only critical condition triggers survival mode.
/obj/item/organ/internal/heart/machine/anomalock/proc/on_owner_trait_gained(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/carbon/source = A.target
	var/datum/notice/trait_gained/event = A
	if(event.trait != TRAIT_CRITICAL_CONDITION)
		return
	activate_survival(source)

/obj/item/organ/internal/heart/machine/anomalock/proc/activate_survival(mob/living/carbon/organ_owner)
	if(!COOLDOWN_FINISHED(src, survival_cooldown))
		return FALSE

	organ_owner.apply_body_effect(/datum/body_effect/voltaic_overdrive, 30 SECONDS)
	add_lightning_overlay(30 SECONDS)
	COOLDOWN_START(src, survival_cooldown, survival_cooldown_time)
	after(src, COOLDOWN_TIMELEFT(src, survival_cooldown), PROC_REF(notify_cooldown), with = list(organ_owner))
	return TRUE

/obj/item/organ/internal/heart/machine/anomalock/proc/notify_cooldown(mob/living/carbon/organ_owner)
	balloon_alert(organ_owner, "your heart strengthtens")
	play_sfx(owner, SFX_MACHINES_DEFIB_ZAP, 0.8, vary = FALSE, extrarange = 0)

/obj/item/organ/internal/heart/machine/anomalock/proc/on_emp_act(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	add_lightning_overlay(10 SECONDS)

/// The held core is the kind this heart runs on.
/obj/item/organ/internal/heart/machine/anomalock/proc/core_fits(datum/act/op/A)
	return istype(A.held, required_anomaly)

/obj/item/organ/internal/heart/machine/anomalock/proc/core_missing(datum/act/op/A)
	return !core

/obj/item/organ/internal/heart/machine/anomalock/proc/core_present(datum/act/op/A)
	return !!core

/obj/item/organ/internal/heart/machine/anomalock/proc/core_loose(datum/act/op/A)
	return core_removable

/obj/item/organ/internal/heart/machine/anomalock/proc/install_core(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(core || W.loc != user)
		return
	if(!move_into(src, nameof(src.core), W, user))
		return
	balloon_alert(user, "core_installed")
	play_sfx(src, SFX_MACHINES_CLICK, volume = 0, vary = FALSE)

/obj/item/organ/internal/heart/machine/anomalock/proc/remove_core_interrupted(datum/act/op/A)
	balloon_alert(A.actor, "interrupted!")

/obj/item/organ/internal/heart/machine/anomalock/proc/remove_core(datum/act/op/A)
	var/mob/user = A.actor
	if(!core)
		return
	balloon_alert(user, "core removed")
	var/obj/item/removed_core = rel_take(src, nameof(core)) // unowned before it goes to the hands
	removed_core.forceMove(drop_location())
	if(Adjacent(user) && !(A.authority & AUTH_REMOTE_ACCESS))
		user.put_in_hands(removed_core)

CAPABILITIES(/obj/item/organ/internal/heart/machine/anomalock/prebuilt)
	owns_one(nameof(core), starts = /obj/item/assembly/signaler/anomaly/flux)

/// The look (the draw sweep: from its template).
/obj/item/organ/internal/heart/machine/anomalock/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][core ? "-core" : ""]")

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
	holder.status_adjust(STAT_WEAKENED, -5)
	holder.status_adjust(STAT_SLEEPING, -5)
	holder.status_adjust(STAT_STUNNED, -5)
	holder.status_set(STAT_BLURRY, 0)

/datum/body_effect/voltaic_overdrive/on_start(mob/living/L)
	. = ..()
	remove_trait(L, TRAIT_CRITICAL_CONDITION, STAT_TRAIT)
	L.reagents.add_reagent(REAGENT_ID_MYELAMINE, 5)
	to_chat(L, span_userdanger("You feel a burst of energy! It's do or die!"))

/datum/body_effect/voltaic_overdrive/on_end(mob/living/L, expired)
	. = ..()
	L.balloon_alert(L, "your heart weakens")
