/// NOTE:
/// If you are adding an artifact, I would highly recommend thinking of HOW it can be utilized by the harvester first and foremost.
/// If you need assistance in getting it to work with the harvester, I suggest looking at animate_anomaly.dm (for a full incorporation) and electric_field (for a partial incoporation)

/obj/item/anobattery
	name = "Anomaly power battery"
	desc = "A device that is able to harness the power of anomalies!"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "anobattery0"
	var/datum/artifact_effect/battery_effect
	var/capacity = 500
	var/stored_charge = 0

CAPABILITIES(/obj/item/anobattery)
	owns_one(nameof(battery_effect), /datum/artifact_effect)

/obj/item/anobattery/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "It currently has a charge of [stored_charge] out of [capacity]"

/obj/item/anobattery/moderate
	name = "moderate anomaly battery"
	capacity = 1000

/obj/item/anobattery/advanced
	name = "advanced anomaly battery"
	capacity = 3000

/obj/item/anobattery/exotic
	name = "exotic anomaly battery"
	capacity = 10000

/obj/item/anobattery/adminbus //Adminspawn only. Do not make this accessible or I will gnaw you.
	name = "godly anomaly battery"
	capacity = 100000000

/*
/obj/item/anobattery/Initialize(mapload)
	battery_effect = new()
*/

/obj/item/anobattery/proc/UpdateSprite()
	var/p = (stored_charge/capacity)*100
	p = min(p, 100)
	icon_state = "anobattery[round(p,25)]"

/obj/item/anobattery/proc/use_power(amount)
	stored_charge = max(0, stored_charge - amount)

/obj/item/anodevice
	name = "Anomaly power utilizer"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "anodev"
	var/duration = 0
	var/interval = 0
	EXPIRY_DECLARE(time_end)
	/// after() timer that ends the emission at time_end, or 0.
	EXPIRY_DECLARE(last_activation)
	EXPIRY_DECLARE(last_process)
	var/tmp/obj/item/anobattery/inserted_battery
	var/tmp/turf/archived_loc
	var/energy_consumed_on_touch = 100
	var/tmp/mob/last_user_touched

/obj/item/anodevice/equipped(mob/user, slot)
	rel_set(src, nameof(last_user_touched), user)
	..()

/obj/item/anodevice/var/activated = FALSE
TRACKED(/obj/item/anodevice, activated)
CAPABILITIES(/obj/item/anodevice)
	/// Runs its battery effect while activated.
	every(2 SECONDS, then(PROC_REF(anodevice_step)), when = nameof(activated))
	interface("XenoarchHandheldPowerUtilizer", state = nameof(GLOB.tgui_inventory_state))
	without("ui_open")
	op("changeduration", ui_act("changeduration", arg("duration", num(0, 300))), then(PROC_REF(ui_act_changeduration)))
	op("changeinterval", ui_act("changeinterval", arg("interval", num(0, 100))), then(PROC_REF(ui_act_changeinterval)))
	op("startup", ui_act("startup"), then(PROC_REF(ui_act_startup)))
	op("shutdown", ui_act("shutdown"), then(PROC_REF(ui_act_shutdown)))
	op("ejectbattery", ui_act("ejectbattery"), then(PROC_REF(ui_act_ejectbattery)))

DECLARE_INTERACTIONS(/obj/item/anodevice, \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_USE("Open", PROC_REF(interaction_open)), \
)

/// Old attackby.
/obj/item/anodevice/proc/interaction_item(mob/user, obj/I, datum/interaction/interaction)
	if(istype(I, /obj/item/anobattery))
		if(!inserted_battery())
			if(!own_bring_in(src, nameof(inserted_battery), I, null, user, TRUE, null, FALSE))
				return INTERACTION_HANDLED_PASS
			to_chat(user, span_blue("You insert the battery."))
			rel_set(src, nameof(inserted_battery), I)
			UpdateSprite()
	else
		return FALSE
	return INTERACTION_HANDLED_PASS


/// Old attack_self: open the interface.
/obj/item/anodevice/proc/interaction_open(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

/// /obj/item/anodevice's window data.
/obj/item/anodevice/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["inserted_battery"] = inserted_battery()
	data["anomaly"] = null
	data["charge"] = null
	data["capacity"] = null
	data["timeleft"] = null
	data["activated"] = null
	data["duration"] = null
	data["interval"] = null
	if(inserted_battery())
		data["anomaly"] = inserted_battery()?.battery_effect?.artifact_id
		data["charge"] = inserted_battery().stored_charge
		data["capacity"] = inserted_battery().capacity
		data["timeleft"] = round(max((time_end - last_process) / 10, 0))
		data["activated"] = activated
		data["duration"] = duration / 10
		data["interval"] = interval / 10

	return data

/obj/item/anodevice/proc/ui_act_changeduration(datum/act/op/A, duration_arg)
	duration = duration_arg
	if(activated)
		arm_emission_timer()
	return TRUE

/obj/item/anodevice/proc/ui_act_changeinterval(datum/act/op/A, interval_arg)
	interval = interval_arg
	return TRUE

/obj/item/anodevice/proc/ui_act_startup(datum/act/op/A)
	var/mob/user = A.actor
	if(inserted_battery() && inserted_battery().battery_effect && (inserted_battery().stored_charge > 0))
		set_activated(TRUE)
		visible_message(span_blue("[icon2html(src,viewers(src))] [src] whirrs."), span_blue("[icon2html(src,viewers(src))]You hear something whirr."))
		if(!inserted_battery().battery_effect.activated)
			inserted_battery().battery_effect.ToggleActivate(1)
		arm_emission_timer()
		EXPIRY_STAMP(src, last_process, CLOCK_WORLD)
	else
		to_chat(user, span_warning("[src] is unable to start due to no anomolous power source inserted/remaining."))
	return TRUE

/obj/item/anodevice/proc/ui_act_shutdown(datum/act/op/A)
	set_activated(FALSE)
	return TRUE

/obj/item/anodevice/proc/ui_act_ejectbattery(datum/act/op/A)
	if(inserted_battery())
		inserted_battery().forceMove(get_turf(src))
		rel_clear(src, nameof(/obj/item/anodevice::inserted_battery))
		UpdateSprite()
	shutdown_emission()
	return TRUE

/// Runs its battery effect every 2 s; declared: while activated (its "startup" sets it).
/obj/item/anodevice/proc/anodevice_step(datum/act/timer/A)
	if(activated)
		if(inserted_battery() && inserted_battery().battery_effect && (inserted_battery().stored_charge > 0) )
			//make sure the effect is active
			if(!inserted_battery().battery_effect.activated)
				inserted_battery().battery_effect.ToggleActivate(1)

			//update the effect loc
			var/turf/T = get_turf(src)
			if(T != archived_loc())
				rel_set(src, nameof(archived_loc), T)
				inserted_battery().battery_effect.UpdateMove()

			//if someone is holding the device, do the effect on them
			var/mob/holder
			if(ismob(src.loc))
				holder = src.loc

			//handle charge
			if(ELAPSED(src, last_activation, CLOCK_WORLD) > interval)
				if(inserted_battery().battery_effect.effect == EFFECT_TOUCH)
					if(interval > 0)
						//apply the touch effect to the holder
						if(holder)
							to_chat(holder, "the [icon2html(src,holder.client)] [src] held by [holder] shudders in your grasp.")
						else
							src.loc.visible_message("the [icon2html(src,viewers(src))] [src] shudders.")

						//consume power
						inserted_battery().use_power(energy_consumed_on_touch)
					else
						//consume power equal to time passed
						inserted_battery().use_power(world.time - last_process)

					inserted_battery().battery_effect.DoEffectTouch(last_user_touched()) //Yes. This means if you give it something REALLY bad, it'll keep hitting you as if you're touching it. Be responsible with eldritch magic.

				else if(inserted_battery().battery_effect.effect == EFFECT_PULSE)
					inserted_battery().battery_effect.chargelevel = inserted_battery().battery_effect.chargelevelmax

					//consume power relative to the time the artifact takes to charge and the effect range
					inserted_battery().use_power((inserted_battery().battery_effect.effectrange * inserted_battery().battery_effect.chargelevelmax) / 2)

				else
					//consume power equal to time passed
					inserted_battery().use_power(world.time - last_process)

				EXPIRY_STAMP(src, last_activation, CLOCK_WORLD)

			//process the effect
			inserted_battery().battery_effect.periodic_step()

			//work out if we need to shutdown
			if(inserted_battery().stored_charge <= 0)
				src.loc.visible_message(span_blue("[icon2html(src,viewers(src))] [src] buzzes."), span_blue("[icon2html(src,viewers(src))] You hear something buzz."))
				shutdown_emission()
		else
			src.visible_message(span_blue("[icon2html(src,viewers(src))] [src] buzzes."), span_blue("[icon2html(src,viewers(src))] You hear something buzz."))
			shutdown_emission()
		EXPIRY_STAMP(src, last_process, CLOCK_WORLD)

/// (Re)starts the emission's run: it ends `duration` from now (emission_timer_fired()).
/obj/item/anodevice/proc/arm_emission_timer()
	EXPIRY_SET(src, time_end, duration, CLOCK_WORLD)
	after(src, duration + 0.1 SECONDS, PROC_REF(emission_timer_fired), key = "emission") // replaces a pending one

/// The keyed timer: the set duration has run out.
/obj/item/anodevice/proc/emission_timer_fired()
	if(!activated)
		return
	src.loc.visible_message(span_blue("[icon2html(src,viewers(src))] [src] chimes."), span_blue("[icon2html(src,viewers(src))] You hear something chime."))
	shutdown_emission()

/obj/item/anodevice/proc/shutdown_emission()
	cancel_after(src, "emission")
	if(activated)
		set_activated(0)
		if(inserted_battery()?.battery_effect?.activated)
			inserted_battery().battery_effect.ToggleActivate(1)

/obj/item/anodevice/proc/UpdateSprite()
	if(!inserted_battery())
		icon_state = "anodev"
		return
	var/p = (inserted_battery().stored_charge/inserted_battery().capacity)*100
	p = min(p, 100)
	icon_state = "anodev[round(p,25)]"

/obj/item/anodevice/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)

	if(activated && inserted_battery()?.battery_effect?.effect == EFFECT_TOUCH && !isnull(inserted_battery()))
		inserted_battery()?.battery_effect?.DoEffectTouch(M)
		inserted_battery().use_power(energy_consumed_on_touch)
		act_message(user, M, others = span_blue("%U% taps %T% with [src], and it shudders on contact."))
	else
		act_message(user, M, others = span_blue("%U% taps %T% with [src], but nothing happens."))

	//admin logging
	M.lastattacker = user

	if(inserted_battery()?.battery_effect)
		add_attack_logs(user,M,"Anobattery tap ([inserted_battery()?.battery_effect?.name])")
	return ITEM_INTERACT_SUCCESS


/// Accessor for the inserted_battery var.
/obj/item/anodevice/proc/inserted_battery() as /obj/item/anobattery
	return inserted_battery

/// Accessor for the archived_loc var.
/obj/item/anodevice/proc/archived_loc() as /turf
	return archived_loc

/// Accessor for the last_user_touched var.
/obj/item/anodevice/proc/last_user_touched() as /mob
	return last_user_touched
