/// Top-level snapshots preserve token identity and order without exposing the private roster.
/datum/system/persistence/proc/painting_records()
	return all_paintings.Copy()

/datum/system/persistence/proc/painting_record_at(index)
	return all_paintings[index]

/datum/system/persistence/proc/painting_count()
	return length(all_paintings)

/datum/system/persistence/proc/has_unpicked_paintings()
	return LAZYLEN(unpicked_paintings)

/datum/system/persistence/proc/unpicked_paintings_for(category)
	var/list/matches = list()
	for(var/list/record in unpicked_paintings)
		if(record["persistence_id"] == category)
			matches[++matches.len] = record
	return matches

/datum/system/persistence/proc/discard_unpicked_painting(list/record)
	unpicked_paintings -= list(record)

/datum/system/persistence/proc/append_painting(list/record)
	all_paintings += list(record)

/datum/system/persistence/proc/remove_painting(list/record)
	return all_paintings.Remove(list(record))

/// Preserve the live-roster walk and remove/reappend ordering, including duplicate matches.
/datum/system/persistence/proc/renew_painting(md5, category, mob/user, list/appreciators)
	for(var/list/entry in all_paintings)
		if(entry["md5"] == md5 && entry["persistence_id"] == category)
			all_paintings.Remove(list(entry))
			all_paintings.Add(list(entry))
			appreciators += user.ckey
			to_chat(user, span_notice("Showing interest in this painting renews its position in the curator database."))

/datum/system/persistence/proc/remove_paintings_with_hash(md5)
	var/list/filenames_found = list()
	for(var/list/entry in all_paintings)
		if(entry["md5"] == md5)
			filenames_found += "data/persistent/paintings/[entry["persistence_id"]]/[entry["md5"]].png"
			all_paintings -= list(entry)
	return filenames_found

/// Load validation deliberately keeps the original live-list mutation semantics.
/datum/system/persistence/proc/load_painting_records(list/records, datum/persistent/paintings/validator)
	all_paintings = records
	var/list/tokens = all_paintings
	for(var/list/token in tokens)
		token["age"]++
		if(!validator.CheckTokenSanity(token))
			tokens -= token

/datum/system/persistence/proc/prepare_painting_selection()
	unpicked_paintings = all_paintings.Copy()
