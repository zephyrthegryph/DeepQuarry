/datum/data/pda/app/status_display
	name = "Status Display"
	icon = "list-alt"
	template = "pda_status_display"
	category = "Utilities"

	var/message1	// used for status_displays
	var/message2

/datum/data/pda/app/status_display/update_ui(mob/user, list/data)
	data["records"] = list(
		"message1" = message1 ? message1 : "(none)",
		"message2" = message2 ? message2 : "(none)")

CAPABILITIES(/datum/data/pda/app/status_display)
	op("Status", ui_act("Status", arg("alert"), arg("statdisp", schema_text(4096))), asks(/datum/prompt/text, fields = list("question" = "Line 1", "title" = "Enter Message Text", "default" = computed(PROC_REF(status_line1_default)), "timeout" = 0), step = "k26", when = PROC_REF(status_sets_line1)), asks(/datum/prompt/text, fields = list("question" = "Line 2", "title" = "Enter Message Text", "default" = computed(PROC_REF(status_line2_default)), "timeout" = 0), step = "k28", when = PROC_REF(status_sets_line2)), then(PROC_REF(ui_act_status)))

/datum/data/pda/app/status_display/proc/ui_act_status(datum/act/op/A, alert, statdisp)
	switch(statdisp)
		if("message")
			post_status("message", message1, message2)
		if("alert")
			post_status("alert", alert)
		if("setmsg1")
			var/_answer_k26 = A.step_value("k26")
			if(isnull(_answer_k26))
				return
			message1 = _answer_k26
		if("setmsg2")
			var/_answer_k28 = A.step_value("k28")
			if(isnull(_answer_k28))
				return
			message2 = _answer_k28
		else
			post_status(statdisp)
	return TRUE

/datum/data/pda/app/status_display/proc/status_sets_line1(datum/act/op/A)
	return A.args["statdisp"] == "setmsg1"

/datum/data/pda/app/status_display/proc/status_sets_line2(datum/act/op/A)
	return A.args["statdisp"] == "setmsg2"

/datum/data/pda/app/status_display/proc/status_line1_default(datum/act/op/A)
	return message1

/datum/data/pda/app/status_display/proc/status_line2_default(datum/act/op/A)
	return message2

/datum/data/pda/app/status_display/proc/post_status(command, data1, data2)
	var/datum/radio_frequency/frequency = SSradio.return_frequency(1435)
	if(!frequency)
		return

	var/datum/signal/status_signal = new
	rel_set(status_signal, nameof(status_signal.source), src)
	status_signal.transmission_method = 1
	status_signal.data["command"] = command

	switch(command)
		if("message")
			status_signal.data["msg1"] = data1
			status_signal.data["msg2"] = data2
			var/mob/user = pda().forensic_data?.get_lastprint()
			if(isliving(pda().loc))
				user = pda().loc
			log_admin("STATUS: [user] set status screen with [pda()]. Message: [data1] [data2]")
			message_admins("STATUS: [user] set status screen with [pda()]. Message: [data1] [data2]")

		if("alert")
			status_signal.data["picture_state"] = data1

	frequency.post_signal(src, status_signal)

/datum/data/pda/app/signaller
	name = "Signaler System"
	icon = "rss"
	template = "pda_signaller"
	category = "Utilities"

/datum/data/pda/app/signaller/update_ui(mob/user, list/data)
	if(pda().cartridge && istype(pda().cartridge.radio, /obj/item/radio/integrated/signal))
		var/obj/item/radio/integrated/signal/R = pda().cartridge.radio
		data["frequency"] = R.frequency
		data["minFrequency"] = RADIO_LOW_FREQ
		data["maxFrequency"] = RADIO_HIGH_FREQ
		data["code"] = R.code

/// The cartridge's signaller radio, if it has one.
/datum/data/pda/app/signaller/proc/signal_radio()
	if(pda().cartridge && istype(pda().cartridge.radio, /obj/item/radio/integrated/signal))
		return pda().cartridge.radio
	return null

CAPABILITIES(/datum/data/pda/app/signaller)
	op("signal", ui_act("signal"), then(PROC_REF(ui_act_signal)))
	op("freq", ui_act("freq", arg("freq", num())), then(PROC_REF(ui_act_freq)))
	op("code", ui_act("code", arg("code", int(1, 100))), then(PROC_REF(ui_act_code)))
	op("reset", ui_act("reset", arg("reset", schema_text(16))), then(PROC_REF(ui_act_reset)))
/datum/data/pda/app/signaller/proc/ui_act_signal(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/radio/integrated/signal/R = signal_radio()
	R?.send_signal("ACTIVATE", user)

/datum/data/pda/app/signaller/proc/ui_act_freq(datum/act/op/A, freq)
	var/obj/item/radio/integrated/signal/R = signal_radio()
	if(!R)
		return
	var/frequency = unformat_frequency(freq)
	frequency = sanitize_frequency(frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ)
	R.set_frequency(frequency)
	return TRUE

/datum/data/pda/app/signaller/proc/ui_act_code(datum/act/op/A, code)
	var/obj/item/radio/integrated/signal/R = signal_radio()
	if(!R || isnull(code))
		return
	R.code = code
	return TRUE

/datum/data/pda/app/signaller/proc/ui_act_reset(datum/act/op/A, reset)
	var/obj/item/radio/integrated/signal/R = signal_radio()
	if(!R)
		return
	if(reset == "freq")
		R.set_frequency(initial(R.frequency))
	else
		R.code = initial(R.code)
	return TRUE

/datum/data/pda/app/power
	name = "Power Monitor"
	icon = "exclamation-triangle"
	template = "pda_power"
	category = "Engineering"

	var/datum/tgui_module/power_monitor/power_monitor

CAPABILITIES(/datum/data/pda/app/power)
	interface(null, forwards = nameof(power_monitor)) // every other action is the embedded power monitor's
	without("ui_open")
	op("Back", ui_act(), then(PROC_REF(ui_act_back)))
	owns_one(nameof(power_monitor), /datum/tgui_module/power_monitor)

/datum/data/pda/app/power/New()
	rel_set(src, nameof(power_monitor), new /datum/tgui_module/power_monitor(src))
	. = ..()


/datum/data/pda/app/power/update_ui(mob/user, list/data)
	data.Add(power_monitor.tgui_data(user))

/datum/data/pda/app/power/proc/ui_act_back(datum/act/op/A)
	power_monitor.active_sensor = null
	return OP_OK

/datum/data/pda/app/crew_records
	var/tmp/datum/data/record/general_records

/datum/data/pda/app/crew_records/update_ui(mob/user, list/data)
	var/list/records[0]

	if(general_records() && (general_records() in GLOB.data_core.general))
		data["records"] = records
		records["general"] = general_records().fields
		return records
	else
		for(var/datum/data/record/R as anything in sortRecord(GLOB.data_core.general))
			if(R)
				records += list(list(name = R.fields["name"], "ref" = "\ref[R]"))
		data["recordsList"] = records
		data["records"] = null
		return null

CAPABILITIES(/datum/data/pda/app/crew_records)
	op("Back", ui_act(), then(PROC_REF(ui_act_back)))
	op("Records", ui_act("Records", arg("target", schema_ref(/datum/data/record))), then(PROC_REF(ui_act_records)))

/datum/data/pda/app/crew_records/proc/ui_act_records(datum/act/op/A, target)
	if(isnull(target))
		return FALSE
	var/datum/data/record/R = target
	if(R && (R in GLOB.data_core.general))
		load_records(R)
	return TRUE

/datum/data/pda/app/crew_records/proc/ui_act_back(datum/act/op/A)
	rel_clear(src, nameof(/datum/data/pda/app/crew_records::general_records))
	has_back = 0
	return OP_OK

/datum/data/pda/app/crew_records/proc/load_records(datum/data/record/R)
	rel_set(src, nameof(general_records), R)
	has_back = 1

/datum/data/pda/app/crew_records/medical
	name = "Medical Records"
	icon = "heartbeat"
	template = "pda_medical"
	category = "Medical"

	var/tmp/datum/data/record/medical_records

/datum/data/pda/app/crew_records/medical/update_ui(mob/user, list/data)
	var/list/records = ..()
	if(!records)
		return

	if(medical_records() && (medical_records() in GLOB.data_core.medical))
		records["medical"] = medical_records().fields

	return records

/datum/data/pda/app/crew_records/medical/load_records(datum/data/record/R)
	..(R)
	for(var/datum/data/record/E as anything in GLOB.data_core.medical)
		if(E && (E.fields["name"] == R.fields["name"] || E.fields["id"] == R.fields["id"]))
			rel_set(src, nameof(medical_records), E)
			break

/datum/data/pda/app/crew_records/security
	name = "Security Records"
	icon = "tags"
	template = "pda_security"
	category = "Security"

	var/tmp/datum/data/record/security_records

/datum/data/pda/app/crew_records/security/update_ui(mob/user, list/data)
	var/list/records = ..()
	if(!records)
		return

	if(security_records() && (security_records() in GLOB.data_core.security))
		records["security"] = security_records().fields

	return records

/datum/data/pda/app/crew_records/security/load_records(datum/data/record/R)
	..(R)
	for(var/datum/data/record/E as anything in GLOB.data_core.security)
		if(E && (E.fields["name"] == R.fields["name"] || E.fields["id"] == R.fields["id"]))
			rel_set(src, nameof(security_records), E)
			break

/datum/data/pda/app/supply
	name = "Supply Records"
	icon = "file-word-o"
	template = "pda_supply"
	category = "Quartermaster"

/datum/data/pda/app/supply/update_ui(mob/user, list/data)
	var/supplyData[0]
	var/datum/shuttle/autodock/ferry/supply/shuttle = SSsupply.shuttle
	if (shuttle)
		supplyData["shuttle_moving"] = shuttle.has_arrive_time()
		supplyData["shuttle_eta"] = shuttle.eta_minutes()
		supplyData["shuttle_loc"] = shuttle.at_station() ? "Station" : "Dock"
	var/supplyOrderCount = 0
	var/supplyOrderData[0]
	for(var/datum/supply_order/SO as anything in supply_shoppinglist())

		supplyOrderCount++
		supplyOrderData[++supplyOrderData.len] = list("Number" = SO.ordernum, "Name" = html_encode(SO.supply_pack_of().name), "ApprovedBy" = SO.approved_by, "Comment" = html_encode(SO.comment))

	supplyData["approved"] = supplyOrderData
	supplyData["approved_count"] = supplyOrderCount

	var/requestCount = 0
	var/requestData[0]
	for(var/datum/supply_order/SO as anything in supply_order_history())
		if(SO.status != SUP_ORDER_REQUESTED)
			continue

		requestCount++
		requestData[++requestData.len] = list("Number" = SO.ordernum, "Name" = html_encode(SO.supply_pack_of().name), "OrderedBy" = SO.ordered_by, "Comment" = html_encode(SO.comment))

	supplyData["requests"] = requestData
	supplyData["requests_count"] = requestCount

	data["supply"] = supplyData

/datum/data/pda/app/janitor
	name = "Custodial Locator"
	icon = "trash-alt-o"
	template = "pda_janitor"
	category = "Utilities"

/datum/data/pda/app/janitor/update_ui(mob/user, list/data)
	var/JaniData[0]
	var/turf/cl = get_turf(pda())

	if(cl)
		JaniData["user_loc"] = list("x" = cl.x, "y" = cl.y)
	else
		JaniData["user_loc"] = list("x" = 0, "y" = 0)

	var/MopData[0]
	for(var/obj/item/mop/M in REGISTRY_MEMBERS(REGISTRY_MOPS))//GLOB.janitorial_equipment)
		var/turf/ml = get_turf(M)
		if(ml)
			if(ml.z != cl.z)
				continue
			var/direction = get_dir(pda(), M)
			MopData[++MopData.len] = list ("x" = ml.x, "y" = ml.y, "dir" = uppertext(dir2text(direction)), "status" = M.reagents.total_volume ? "Wet" : "Dry")

	var/BucketData[0]
	for(var/obj/structure/mopbucket/B in REGISTRY_MEMBERS(REGISTRY_MOP_BUCKETS))//GLOB.janitorial_equipment)
		var/turf/bl = get_turf(B)
		if(bl)
			if(bl.z != cl.z)
				continue
			var/direction = get_dir(pda(),B)
			BucketData[++BucketData.len] = list ("x" = bl.x, "y" = bl.y, "dir" = uppertext(dir2text(direction)), "volume" = B.reagents.total_volume, "max_volume" = B.reagents.maximum_volume)

	var/CbotData[0]
	for(var/mob/living/bot/cleanbot/B in REGISTRY_MEMBERS(REGISTRY_MOBS))
		var/turf/bl = get_turf(B)
		if(bl)
			if(bl.z != cl.z)
				continue
			var/direction = get_dir(pda(),B)
			CbotData[++CbotData.len] = list("x" = bl.x, "y" = bl.y, "dir" = uppertext(dir2text(direction)), "status" = B.on ? "Online" : "Offline")

	var/CartData[0]
	for(var/obj/structure/janitorialcart/B in REGISTRY_MEMBERS(REGISTRY_JANITORIAL_CARTS))//GLOB.janitorial_equipment)
		var/turf/bl = get_turf(B)
		if(bl)
			if(bl.z != cl.z)
				continue
			var/direction = get_dir(pda(),B)
			CartData[++CartData.len] = list("x" = bl.x, "y" = bl.y, "dir" = uppertext(dir2text(direction)), "volume" = B.mybucket?.reagents.total_volume || 0, "max_volume" = B.mybucket?.reagents.maximum_volume || 0)

	JaniData["mops"] = MopData.len ? MopData : null
	JaniData["buckets"] = BucketData.len ? BucketData : null
	JaniData["cleanbots"] = CbotData.len ? CbotData : null
	JaniData["carts"] = CartData.len ? CartData : null
	data["janitor"] = JaniData

/// The general_records this refers to (a relation view: null once that is deleted).
/datum/data/pda/app/crew_records/proc/general_records() as /datum/data/record
	return general_records

/// The medical_records this refers to (a relation view: null once that is deleted).
/datum/data/pda/app/crew_records/medical/proc/medical_records() as /datum/data/record
	return medical_records

/// The security_records this refers to (a relation view: null once that is deleted).
/datum/data/pda/app/crew_records/security/proc/security_records() as /datum/data/record
	return security_records
