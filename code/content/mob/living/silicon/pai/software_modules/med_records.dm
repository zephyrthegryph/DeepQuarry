/datum/pai_software/med_records
	name = "Medical Records"
	ram_cost = 15
	id = "med_records"
	toggle = 0

CAPABILITIES(/datum/pai_software/med_records)
	interface("pAIMedrecords", state = nameof(GLOB.tgui_always_state))
	ui_shape(records = list_of(row(name = schema_text(), ref = num())), general = nullable(row(name = schema_text(), id = schema_text(), brain_type = schema_text(), sex = schema_text(), species = schema_text(), age = num(), rank = schema_text(), fingerprint = schema_text(), p_stat = schema_text(), m_stat = schema_text())), medical = nullable(row(b_type = schema_text(), mi_dis = schema_text(), mi_dis_d = schema_text(), ma_dis = schema_text(), ma_dis_d = schema_text(), alg = schema_text(), alg_d = schema_text(), cdi = schema_text(), cdi_d = schema_text(), notes = schema_text())), could_not_find = bool())
	op("select", ui_act("select", arg("select", schema_ref(/datum/data/record))), then(PROC_REF(ui_act_select)))

/// The general record fields the pAI record windows show, or null for no record.
/proc/pai_record_general(datum/data/record/G)
	if(!G)
		return null
	return list(
		"name" = G.fields["name"],
		"id" = G.fields["id"],
		"brain_type" = G.fields["brain_type"],
		"sex" = G.fields["sex"],
		"species" = G.fields["species"],
		"age" = G.fields["age"],
		"rank" = G.fields["rank"],
		"fingerprint" = G.fields["fingerprint"],
		"p_stat" = G.fields["p_stat"],
		"m_stat" = G.fields["m_stat"])

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
	data["general"] = pai_record_general(G)
	data["medical"] = M ? list(
		"b_type" = M.fields["b_type"],
		"mi_dis" = M.fields["mi_dis"],
		"mi_dis_d" = M.fields["mi_dis_d"],
		"ma_dis" = M.fields["ma_dis"],
		"ma_dis_d" = M.fields["ma_dis_d"],
		"alg" = M.fields["alg"],
		"alg_d" = M.fields["alg_d"],
		"cdi" = M.fields["cdi"],
		"cdi_d" = M.fields["cdi_d"],
		"notes" = M.fields["notes"]) : null
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
