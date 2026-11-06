/datum/pai_software/med_records
	name = "Medical Records"
	ram_cost = 15
	id = "med_records"
	toggle = 0

CAPABILITIES(/datum/pai_software/med_records)
	interface("pAIMedrecords", state = nameof(GLOB.tgui_always_state))
	op("select", ui_act("select", arg("select", schema_ref(/datum/data/record))), then(PROC_REF(ui_act_select)))

/datum/pai_software/med_records/ui_data(datum/act/eval/A)
	var/mob/living/silicon/pai/user = A.actor
	var/list/data = list()

	var/list/records = list()
	for(var/datum/data/record/general in sortRecord(GLOB.data_core.general))
		var/list/record = list()
		record["name"] = general.fields["name"]
		record["ref"] = handle_of(general)
		records.Add(list(record))

	data["records"] = records

	var/datum/data/record/G = user.medicalActive1
	var/datum/data/record/M = user.medicalActive2
	data["general"] = G ? G.fields : null
	data["medical"] = M ? M.fields : null
	data["could_not_find"] = user.medical_cannotfind

	return data

/datum/pai_software/med_records/proc/ui_act_select(datum/act/op/A, select)
	var/mob/user = A.actor
	var/mob/living/silicon/pai/P = user
	var/datum/data/record/record = select
	if(record)
		var/datum/data/record/R = record
		var/datum/data/record/M = null
		if (!( GLOB.data_core.general.Find(R) ))
			P.set_medical_cannotfind(1)
		else
			P.set_medical_cannotfind(0)
			for(var/datum/data/record/E in GLOB.data_core.medical)
				if ((E.fields["name"] == R.fields["name"] || E.fields["id"] == R.fields["id"]))
					M = E
			rel_set(P, nameof(/mob/living/silicon/pai::medicalActive1), R)
			rel_set(P, nameof(/mob/living/silicon/pai::medicalActive2), M)
	else
		P.set_medical_cannotfind(1)
	return 1
