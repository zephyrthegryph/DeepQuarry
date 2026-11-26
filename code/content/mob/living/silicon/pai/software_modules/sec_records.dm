/datum/pai_software/sec_records
	name = "Security Records"
	ram_cost = 15
	id = "sec_records"
	toggle = 0

CAPABILITIES(/datum/pai_software/sec_records)
	interface("pAISecrecords", state = nameof(GLOB.tgui_always_state))
	ui_shape(records = list_of(row(name = schema_text(), ref = num())), general = nullable(row(name = schema_text(), id = schema_text(), brain_type = schema_text(), sex = schema_text(), species = schema_text(), age = num(), rank = schema_text(), fingerprint = schema_text(), p_stat = schema_text(), m_stat = schema_text())), security = nullable(row(criminal = schema_text(), mi_crim = schema_text(), mi_crim_d = schema_text(), ma_crim = schema_text(), ma_crim_d = schema_text(), notes = schema_text())), could_not_find = bool())
	op("select", ui_act("select", arg("select", schema_ref(/datum/data/record))), then(PROC_REF(ui_act_select)))

/datum/pai_software/sec_records/ui_data(datum/act/eval/A)
	var/mob/living/silicon/pai/user = A.actor
	var/list/data = list()

	var/list/records = list()
	for(var/datum/data/record/general in sortRecord(GLOB.data_core.general))
		var/list/record = list()
		record["name"] = general.fields["name"]
		record["ref"] = handle_of(general)
		records.Add(list(record))

	data["records"] = records

	var/datum/data/record/G = user.securityActive1
	var/datum/data/record/S = user.securityActive2
	data["general"] = pai_record_general(G)
	data["security"] = S ? list(
		"criminal" = S.fields["criminal"],
		"mi_crim" = S.fields["mi_crim"],
		"mi_crim_d" = S.fields["mi_crim_d"],
		"ma_crim" = S.fields["ma_crim"],
		"ma_crim_d" = S.fields["ma_crim_d"],
		"notes" = S.fields["notes"]) : null
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
