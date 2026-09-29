/obj/machinery/door/airlock/alarmlock

	name = "Glass Alarm Airlock"
	icon = 'icons/obj/doors/Doorglass.dmi'
	opacity = 0
	glass = 1

	var/datum/radio_frequency/air_connection
	var/air_frequency = ALERT_FREQ
	autoclose = 0

/obj/machinery/door/airlock/alarmlock/Initialize(mapload)
	. = ..()
	GLOB.radio_service.remove_object(src, air_frequency)
	rel_set(src, "air_connection", GLOB.radio_service.add_object(src, air_frequency, RADIO_TO_AIRALARM))
	open()

/obj/machinery/door/airlock/alarmlock/receive_signal(datum/signal/signal)
	..()
	if(stat & (NOPOWER|BROKEN))
		return

	var/alarm_area = signal.data["zone"]
	var/alert = signal.data["alert"]

	var/area/our_area = get_area(src)

	if(alarm_area == our_area.name)
		switch(alert)
			if("severe")
				autoclose = 1
				close()
			if("minor", "clear")
				autoclose = 0
				open()

/// LC-refs: air connection -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/door/airlock/alarmlock/proc/air_connection() as /datum/radio_frequency
	return air_connection
