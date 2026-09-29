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
	var/activated = 0
	var/duration = 0
	var/interval = 0
	EXPIRY_DECLARE(time_end)
	/// om_after() timer that ends the emission at time_end, or 0.
	var/tmp/emission_timer = 0
	EXPIRY_DECLARE(last_activation)
	EXPIRY_DECLARE(last_process)
	var/tmp/obj/item/anobattery/inserted_battery
	var/tmp/turf/archived_loc
	var/energy_consumed_on_touch = 100
	var/tmp/mob/last_user_touched

/obj/item/anodevice/equipped(mob/user, slot)
	rel_set(src, "last_user_touched", user)
	..()

DECLARE_INTERACTIONS(/obj/item/anodevice, \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_USE("Open", PROC_REF(interaction_open)), \
)

/// Old attackby.
/obj/item/anodevice/proc/interaction_item(mob/user, obj/I, datum/interaction/interaction)
	if(istype(I, /obj/item/anobattery))
		if(!inserted_battery())
			to_chat(user, span_blue("You insert the battery."))
			user.drop_item()
			I.forceMove(src)
			rel_set(src, "inserted_battery", I)
			UpdateSprite()
	else
		return FALSE
	return INTERACTION_HANDLED_PASS


/// Old attack_self: open the interface.
/obj/item/anodevice/proc/interaction_open(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

DECLARE_UI_STATE(/obj/item/anodevice, GLOB.tgui_inventory_state)

DECLARE_UI(/obj/item/anodevice, "XenoarchHandheldPowerUtilizer")

UI_DATA(/obj/item/anodevice, "merge:ui_data_obj_item_anodevice{inserted_battery:unknown,anomaly:text,charge:num,capacity:num,timeleft:num,activated:num,duration:num,interval:num}")

/// The computed part of /obj/item/anodevice's window data (declared on its UI_DATA row).
/obj/item/anodevice/proc/ui_data_obj_item_anodevice(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

UI_ACT(/obj/item/anodevice, "changeduration", ui_act_changeduration, UI_ARG_NUM("duration", 0, 300))
UI_ACT_PROC(/obj/item/anodevice, ui_act_changeduration)
	duration = params["duration"]
	if(activated)
		arm_emission_timer()
	return TRUE

UI_ACT(/obj/item/anodevice, "changeinterval", ui_act_changeinterval, UI_ARG_NUM("interval", 0, 100))
UI_ACT_PROC(/obj/item/anodevice, ui_act_changeinterval)
	interval = params["interval"]
	return TRUE

UI_ACT(/obj/item/anodevice, "startup", ui_act_startup)
UI_ACT_PROC(/obj/item/anodevice, ui_act_startup)
	if(inserted_battery() && inserted_battery().battery_effect && (inserted_battery().stored_charge > 0))
		activated = TRUE
		om_task_periodic(src, PERIODIC_SLOW)
		visible_message(span_blue("[icon2html(src,viewers(src))] [src] whirrs."), span_blue("[icon2html(src,viewers(src))]You hear something whirr."))
		if(!inserted_battery().battery_effect.activated)
			inserted_battery().battery_effect.ToggleActivate(1)
		arm_emission_timer()
		EXPIRY_STAMP(src, last_process, CLOCK_WORLD)
	else
		to_chat(ui.user, span_warning("[src] is unable to start due to no anomolous power source inserted/remaining."))
	return TRUE

UI_ACT(/obj/item/anodevice, "shutdown", ui_act_shutdown)
UI_ACT_PROC(/obj/item/anodevice, ui_act_shutdown)
	activated = FALSE
	return TRUE

UI_ACT(/obj/item/anodevice, "ejectbattery", ui_act_ejectbattery)
UI_ACT_PROC(/obj/item/anodevice, ui_act_ejectbattery)
	if(inserted_battery())
		inserted_battery().forceMove(get_turf(src))
		rel_clear(src, "inserted_battery")
		UpdateSprite()
	shutdown_emission()
	return TRUE

/// Runs its battery effect every 2 s while activated (its "startup" starts it); off, it sleeps.
/obj/item/anodevice/periodic_step()
	if(!activated)
		return PROCESS_KILL
	if(activated)
		if(inserted_battery() && inserted_battery().battery_effect && (inserted_battery().stored_charge > 0) )
			//make sure the effect is active
			if(!inserted_battery().battery_effect.activated)
				inserted_battery().battery_effect.ToggleActivate(1)

			//update the effect loc
			var/turf/T = get_turf(src)
			if(T != archived_loc())
				rel_set(src, "archived_loc", T)
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
	if(emission_timer)
		om_cancel_timer(src, emission_timer)
	emission_timer = om_after(src, duration + 1, PROC_REF(emission_timer_fired))

/// om_after() callback: the set duration has run out.
/obj/item/anodevice/proc/emission_timer_fired()
	emission_timer = 0
	if(!activated)
		return
	src.loc.visible_message(span_blue("[icon2html(src,viewers(src))] [src] chimes."), span_blue("[icon2html(src,viewers(src))] You hear something chime."))
	shutdown_emission()

/obj/item/anodevice/proc/shutdown_emission()
	if(emission_timer)
		om_cancel_timer(src, emission_timer)
		emission_timer = 0
	if(activated)
		activated = 0
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
