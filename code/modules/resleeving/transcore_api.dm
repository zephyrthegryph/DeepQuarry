// The transcore system's API (code/modules/resleeving/transcore_service.dm declares the system).
//
//   SStranscore.leave_round(mob)                       a mob left the round: its backup and body scan are dropped
//   SStranscore.db_by_key(key)                         a database by key (null: the default one)
//   SStranscore.db_by_mind_name(name)                  the database holding a mind's backup, or null
//   SStranscore.m_backup(mind, nif, one_time, key)     back a mind up
//   SStranscore.add_backup / stop_backup(record, key)  file or retire a mind record
//   SStranscore.add_body / remove_body(record, key)    file or retire a body record
//   SStranscore.core_dump(disk, key)                   an emergency core dump onto a disk
//
// `databases` is read as a var by the registry and changeling code.

/datum/system/transcore/proc/leave_round(mob/M)
	if(!istype(M))
		WARNING("Non-mob asked to be removed from transcore: [M] [M?.type]")
		return
	if(!M.mind)
		WARNING("No mind mob asked to be removed from transcore: [M] [M?.type]")
		return

	for(var/key in databases)
		var/datum/transcore_db/db = databases[key]
		if(M.mind.name in db.backed_up)
			var/datum/transhuman/mind_record/MR = db.backed_up[M.mind.name]
			db.stop_backup(MR)
		if(M.mind.name in db.body_scans) //This uses mind names to avoid people cryo'ing a printed body to delete body scans.
			var/datum/transhuman/body_record/BR = db.body_scans[M.mind.name]
			db.remove_body(BR)

/datum/system/transcore/proc/db_by_key(key)
	if(isnull(key))
		return default_db
	if(!databases[key])
		WARNING("Tried to find invalid transcore database: [key]")
		return default_db
	return databases[key]

/datum/system/transcore/proc/db_by_mind_name(name)
	if(isnull(name))
		return null
	for(var/key in databases)
		var/datum/transcore_db/db = databases[key]
		if(name in db.backed_up)
			return db

// These are now just interfaces to databases
/datum/system/transcore/proc/m_backup(datum/mind/mind, obj/item/nif/nif, one_time = FALSE, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.m_backup(mind=mind, nif=nif, one_time=one_time)

/datum/system/transcore/proc/add_backup(datum/transhuman/mind_record/MR, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.add_backup(MR=MR)

/datum/system/transcore/proc/stop_backup(datum/transhuman/mind_record/MR, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.stop_backup(MR=MR)

/datum/system/transcore/proc/add_body(datum/transhuman/body_record/BR, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.add_body(BR=BR)

/datum/system/transcore/proc/remove_body(datum/transhuman/body_record/BR, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.remove_body(BR=BR)

/datum/system/transcore/proc/core_dump(obj/item/disk/transcore/disk, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.core_dump(disk=disk)
