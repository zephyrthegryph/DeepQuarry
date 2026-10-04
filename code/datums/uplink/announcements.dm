/****************
* Announcements *
*****************/
/datum/uplink_item/abstract/announcements
	category = /datum/uplink_category/services
	blacklisted = 1

/datum/uplink_item/abstract/announcements/buy_prepared(obj/item/uplink/U, mob/user, extra_args)
	. = ..()
	if(.)
		log_and_message_admins("has triggered a falsified [src]", user)

/datum/uplink_item/abstract/announcements/fake_centcom
	name = "Command Update Announcement"
	desc = "Causes a falsified Command Update. Triggers immediately after supplying additional data."
	item_cost = 20

/datum/uplink_item/abstract/announcements/fake_centcom/extra_args(mob/user, list/buy_args)
	open_request(src, /datum/prompt/text/uplink_announcement, PROC_REF(announcement_title_entered), answerer = user, payment_uplink = buy_args[1], payment_operator = user, question = "Enter your announcement title.", title = "Announcement Title")
	return null

/datum/uplink_item/abstract/announcements/fake_centcom/get_goods(obj/item/uplink/U, location, mob/user, list/arguments)
	post_comm_message(arguments["title"], replacetext(arguments["message"], "\n", "<br/>"))
	GLOB.command_announcement.Announce(arguments["message"], arguments["title"])
	return 1

/datum/uplink_item/abstract/announcements/fake_crew_arrival
	name = "Crew Arrival Announcement/Records"
	desc = "Creates a fake crew arrival announcement as well as fake crew records, using your current appearance (including held items!) and worn id card. Trigger with care!"
	item_cost = 15

/datum/uplink_item/abstract/announcements/fake_crew_arrival/get_goods(obj/item/uplink/U, location, mob/user, list/arguments)
	if(!user)
		return 0

	var/obj/item/card/id/I = user.GetIdCard()
	var/datum/data/record/random_general_record
	var/datum/data/record/random_medical_record
	if(length(GLOB.data_core.general))
		random_general_record	= pick(GLOB.data_core.general)
		random_medical_record	= find_medical_record("id", random_general_record.fields["id"])

	var/datum/data/record/general = GLOB.data_core.CreateGeneralRecord(user)
	if(I)
		general.fields["age"] = I.age
		general.fields["rank"] = I.assignment
		general.fields["real_rank"] = I.assignment
		general.fields["name"] = I.registered_name
		general.fields["sex"] = I.sex
	else
		var/mob/living/carbon/human/H
		if(ishuman(user))
			H = user
			general.fields["age"] = H.age
		else
			general.fields["age"] = initial(H.age)
		var/assignment = GetAssignment(user)
		general.fields["rank"] = assignment
		general.fields["real_rank"] = assignment
		general.fields["name"] = user.real_name
		general.fields["sex"] = capitalize(user.gender)

	general.fields["species"] = user.get_species()
	var/datum/data/record/medical = GLOB.data_core.CreateMedicalRecord(general.fields["name"], general.fields["id"])
	GLOB.data_core.CreateSecurityRecord(general.fields["name"], general.fields["id"])

	if(random_general_record)
		general.fields["citizenship"]	= random_general_record.fields["citizenship"]
		general.fields["faction"] 		= random_general_record.fields["faction"]
		general.fields["fingerprint"] 	= random_general_record.fields["fingerprint"]
		general.fields["home_system"] 	= random_general_record.fields["home_system"]
		general.fields["birthplace"] 	= random_general_record.fields["birthplace"]
		general.fields["religion"] 		= random_general_record.fields["religion"]
	if(random_medical_record)
		medical.fields["b_type"]		= random_medical_record.fields["b_type"]
		medical.fields["b_dna"]			= random_medical_record.fields["b_dna"]

	if(I)
		general.fields["fingerprint"] 	= I.fingerprint_hash
		medical.fields["b_type"]	= I.blood_type
		medical.fields["b_dna"]		= I.dna_hash

	AnnounceArrivalSimple(general.fields["name"], general.fields["rank"])
	return 1

/datum/uplink_item/abstract/announcements/fake_ion_storm
	name = "Ion Storm Announcement"
	desc = "Interferes with the station's ion sensors. Triggers immediately upon investment."
	item_cost = 10

/datum/uplink_item/abstract/announcements/fake_ion_storm/get_goods(obj/item/uplink/U, location)
	ion_storm_announcement()
	return 1

/datum/uplink_item/abstract/announcements/fake_radiation
	name = "Radiation Storm Announcement"
	desc = "Interferes with the station's radiation sensors. Triggers immediately upon investment."
	item_cost = 15

/datum/uplink_item/abstract/announcements/fake_radiation/get_goods(obj/item/uplink/U, location)
	var/datum/event_meta/EM = new(EVENT_LEVEL_MUNDANE, "Fake Radiation Storm", add_to_queue = 0)
	new/datum/event/radiation_storm/syndicate(EM)
	return 1

/datum/prompt/text/uplink_announcement
	timeout = 0
	var/obj/item/uplink/payment_uplink
	var/mob/payment_operator
	var/payment_uplink_expected = FALSE
	var/payment_operator_expected = FALSE
	var/headline

CAPABILITIES(/datum/prompt/text/uplink_announcement)
	ref_one(nameof(payment_uplink), /obj/item/uplink)
	ref_one(nameof(payment_operator), /mob)

/datum/prompt/text/uplink_announcement/prepare(datum/act/A)
	. = ..()
	var/obj/item/uplink/captured_uplink = payment_uplink
	var/mob/captured_operator = payment_operator
	payment_uplink_expected = !isnull(captured_uplink)
	payment_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(payment_uplink))
	rel_clear(src, nameof(payment_operator))
	if(captured_uplink && !QDELETED(captured_uplink))
		rel_set(src, nameof(payment_uplink), captured_uplink)
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(payment_operator), captured_operator)

/datum/prompt/text/uplink_announcement/recheck_extra()
	if((payment_uplink_expected && QDELETED(payment_uplink)) || (payment_operator_expected && QDELETED(payment_operator)))
		return "gone"

/datum/uplink_item/abstract/announcements/fake_centcom/proc/announcement_title_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/result/result = safe_call(PROC_REF(announcement_title_apply), A)
	if(!result.ok)
		stack_trace("Uplink announcement title: [result.error]")
	SStgui.update_uis(src)
	return result.value

/datum/uplink_item/abstract/announcements/fake_centcom/proc/announcement_title_apply(datum/act/request/A)
	var/datum/prompt/text/uplink_announcement/ask = A.answer
	if(!ask.answer_value)
		return
	open_request(src, /datum/prompt/text/uplink_announcement, PROC_REF(announcement_message_entered), answerer = ask.payment_operator, payment_uplink = ask.payment_uplink, payment_operator = ask.payment_operator, headline = ask.answer_value, question = "Enter your announcement message.", title = "Announcement Title")

/datum/uplink_item/abstract/announcements/fake_centcom/proc/announcement_message_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/result/result = safe_call(PROC_REF(announcement_message_apply), A)
	if(!result.ok)
		stack_trace("Uplink announcement message: [result.error]")
	SStgui.update_uis(src)
	return result.value

/datum/uplink_item/abstract/announcements/fake_centcom/proc/announcement_message_apply(datum/act/request/A)
	var/datum/prompt/text/uplink_announcement/ask = A.answer
	if(!ask.answer_value)
		return
	return buy_prepared(ask.payment_uplink, ask.payment_operator, list("title" = ask.headline, "message" = ask.answer_value))
