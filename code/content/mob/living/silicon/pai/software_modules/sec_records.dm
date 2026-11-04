/datum/pai_software/sec_records
	name = "Security Records"
	ram_cost = 15
	id = "sec_records"
	toggle = 0

CAPABILITIES(/datum/pai_software/sec_records)
	interface("pAISecrecords", state = nameof(GLOB.tgui_always_state))
	op("select", ui_act("select", arg("select", schema_ref(/datum/data/record))), then(PROC_REF(ui_act_select)))

/datum/pai_software/sec_records/ui_data(datum/act/eval/A)
	var/mob/living/silicon/pai/user = A.actor
	var/list/data = list()

	var/list/records = list()
	for(var/datum/data/record/general in sortRecord(GLOB.data_core.general))
		var/list/record = list()
		record["name"] = general.fields["name"]
		record["ref"] = ref_token(general)
		records.Add(list(record))

	data["records"] = records

	var/datum/data/record/G = user.securityActive1
	var/datum/data/record/S = user.securityActive2
	data["general"] = G ? G.fields : null
	data["security"] = S ? S.fields : null
	data["could_not_find"] = user.security_cannotfind

	return data

/datum/pai_software/sec_records/proc/ui_act_select(datum/act/op/A, select)
	var/mob/user = A.actor
	var/mob/living/silicon/pai/P = user
	var/datum/data/record/record = select
	if(record)
		var/datum/data/record/R = record
		var/datum/data/record/S = null
		if (!( GLOB.data_core.general.Find(R) ))
			rel_clear(P, nameof(/mob/living/silicon/pai::securityActive1))
			rel_clear(P, nameof(/mob/living/silicon/pai::securityActive2))
			P.set_security_cannotfind(1)
		else
			P.set_security_cannotfind(0)
			for(var/datum/data/record/E in GLOB.data_core.security)
				if ((E.fields["name"] == R.fields["name"] || E.fields["id"] == R.fields["id"]))
					S = E
			rel_set(P, nameof(/mob/living/silicon/pai::securityActive1), R)
			rel_set(P, nameof(/mob/living/silicon/pai::securityActive2), S)
	else
		rel_clear(P, nameof(/mob/living/silicon/pai::securityActive1))
		rel_clear(P, nameof(/mob/living/silicon/pai::securityActive2))
		P.set_security_cannotfind(1)
	return TRUE
