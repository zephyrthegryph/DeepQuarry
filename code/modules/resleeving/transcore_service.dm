#define SSTRANSCORE_IMPLANTS 1
#define SSTRANSCORE_BACKUPS 2

////////////////////////////////
//// Mind/body data storage system
//// for the resleeving tech
////////////////////////////////

// The transcore world service (was SStranscore): the resleeving mind/body databases, with the
// implant scan and backup staleness pass run by /datum/om/behaviour/world/transcore (3 min).
GLOBAL_DATUM_INIT(transcore_service, /datum/world_service/transcore, new)

DECLARE_REF(/datum/world_service/transcore, "databases", OWNED_VALUES, null)
DECLARE_REF(/datum/world_service/transcore, "default_db", OWNED, null)
// The per-cadence work queue: record/implant -> its database, all round-long service data.
DECLARE_REF(/datum/world_service/transcore, "current_run", STATIC, null)

/datum/world_service/transcore
	name = "Transcore"
	lane = /datum/om/behaviour/world/transcore
	// The old subsystem depended on SSmapping; boot right after it, as before. SSatoms also boots
	// it explicitly, since mapload resleeving machines register with the databases.
	boot_after = /datum/controller/subsystem/mapping

	// THINGS
	var/overdue_time = 6 MINUTES			// Has to be a multiple of the lane's 3 minute cadence, or else will just round up anyway.

	var/current_step = SSTRANSCORE_IMPLANTS

	var/cost_backups = 0
	var/cost_implants = 0

	var/list/datum/transcore_db/databases = list()	// Holds instances of each database
	var/datum/transcore_db/default_db // The default if no specific one is used

	var/list/current_run = list()

/datum/world_service/transcore/initialize()
	initialized = TRUE
	default_db = new()
	databases["default"] = default_db
	for(var/t in subtypesof(/datum/transcore_db))
		var/datum/transcore_db/db = new t()
		if(!db.key)
			WARNING("Instantiated transcore DB without a key: [t]")
			continue
		databases[db.key] = db
	log_world("World service [name] initialized: [length(databases)] databases.")

/datum/world_service/transcore/service_step(resumed)
	var/timer
	if(!resumed)
		current_step = SSTRANSCORE_IMPLANTS
	if(current_step == SSTRANSCORE_IMPLANTS)
		timer = TICK_USAGE
		var/done = process_implants(resumed)
		cost_implants = MC_AVERAGE(cost_implants, TICK_DELTA_TO_MS(TICK_USAGE - timer))
		if(!done)
			return FALSE
		resumed = FALSE
		current_step = SSTRANSCORE_BACKUPS
	timer = TICK_USAGE
	var/backups_done = process_backups(resumed)
	cost_backups = MC_AVERAGE(cost_backups, TICK_DELTA_TO_MS(TICK_USAGE - timer))
	if(!backups_done)
		return FALSE
	current_step = SSTRANSCORE_IMPLANTS
	return TRUE

/datum/world_service/transcore/proc/process_implants(resumed = 0)
	if (!resumed)
		// Create a flat list of every implant in every db with a value of the db they're in
		src.current_run.Cut()
		for(var/key in databases)
			var/datum/transcore_db/db = databases[key]
			for(var/imp_handle in db.implants)
				src.current_run[imp_handle] = db

	var/list/current_run = src.current_run
	while(length(current_run))
		var/imp_handle = current_run[length(current_run)]
		var/datum/transcore_db/db = current_run[imp_handle]
		current_run.len--
		var/obj/item/implant/backup/imp = om_resolve(imp_handle)

		//Remove if deleted, or not in a human anymore.
		if(!imp || !isorgan(imp.loc))
			db.implants -= imp_handle
			continue

		//We're in an organ, at least.
		var/obj/item/organ/external/EO = imp.loc
		var/mob/living/carbon/human/H = EO.owner
		if(!H)
			db.implants -= imp_handle
			continue

		//In a human
		BITSET(H.hud_updateflag, BACKUP_HUD)

		if(H == imp.imp_in() && H.stat < DEAD)
			if(H.mind)
				db.m_backup(H.mind,H.nif)
			else if(H.vr_link && H.vr_link.mind)
				db.m_backup(H.vr_link.mind,H.nif)

		if(TICK_CHECK)
			return FALSE
	return TRUE

/datum/world_service/transcore/proc/process_backups(resumed = 0)
	if (!resumed)
		// Create a flat list of every implant in every db with a value of the db they're in
		src.current_run.Cut()
		for(var/key in databases)
			var/datum/transcore_db/db = databases[key]
			for(var/name in db.backed_up)
				var/datum/transhuman/mind_record/mr = db.backed_up[name]
				src.current_run[mr] = db

	var/list/current_run = src.current_run
	while(length(current_run))
		var/datum/transhuman/mind_record/curr_MR = current_run[length(current_run)]
		current_run.len--

		//Invalid record
		if(!curr_MR)
			log_runtime("Tried to process a null mind_record in transcore w/o a record!")
			continue

		//Onetimes do not get processing or notifications
		if(curr_MR.one_time)
			continue

		//Timing check
		var/since_backup = world.time - curr_MR.last_update
		if(since_backup < overdue_time)
			curr_MR.dead_state = MR_NORMAL
		else
			curr_MR.dead_state = MR_DEAD

		if(TICK_CHECK)
			return FALSE
	return TRUE

/datum/world_service/transcore/stat_line()
	var/msg = "$:{"
	msg += "IM:[round(cost_implants,1)]|"
	msg += "BK:[round(cost_backups,1)]"
	msg += "} "
	msg += "#:{"
	msg += "DB:[length(databases)]|"
	if(!default_db)
		msg += "DEFAULT DB MISSING"
	else
		msg += "DFM:[length(default_db.backed_up)]|"
		msg += "DFB:[length(default_db.body_scans)]|"
		msg += "DFI:[length(default_db.implants)]"
	msg += "} "
	return msg

/datum/world_service/transcore/proc/leave_round(mob/M)
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

/datum/world_service/transcore/proc/db_by_key(key)
	if(isnull(key))
		return default_db
	if(!databases[key])
		WARNING("Tried to find invalid transcore database: [key]")
		return default_db
	return databases[key]

/datum/world_service/transcore/proc/db_by_mind_name(name)
	if(isnull(name))
		return null
	for(var/key in databases)
		var/datum/transcore_db/db = databases[key]
		if(name in db.backed_up)
			return db

// These are now just interfaces to databases
/datum/world_service/transcore/proc/m_backup(datum/mind/mind, obj/item/nif/nif, one_time = FALSE, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.m_backup(mind=mind, nif=nif, one_time=one_time)

/datum/world_service/transcore/proc/add_backup(datum/transhuman/mind_record/MR, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.add_backup(MR=MR)

/datum/world_service/transcore/proc/stop_backup(datum/transhuman/mind_record/MR, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.stop_backup(MR=MR)

/datum/world_service/transcore/proc/add_body(datum/transhuman/body_record/BR, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.add_body(BR=BR)

/datum/world_service/transcore/proc/remove_body(datum/transhuman/body_record/BR, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.remove_body(BR=BR)

/datum/world_service/transcore/proc/core_dump(obj/item/disk/transcore/disk, database_key)
	var/datum/transcore_db/db = db_by_key(database_key)
	db.core_dump(disk=disk)

/datum/transcore_db
	// ALLOW(instance_list): d: one per transcore database (a handful); re-sorted on every write
	var/list/datum/transhuman/mind_record/backed_up = list()	// All known mind records, indexed by MR.mindname/mind.name
	var/list/datum/transhuman/mind_record/has_left		// Why do we even have this?
	// ALLOW(instance_list): d: one per transcore database (a handful); re-sorted on every write
	var/list/datum/transhuman/body_record/body_scans = list()	// All known body records, indexed by BR.mydna.name
	/// All OPERATING backup implants that are being ticked, as OM handles (a deleted one is dropped on its next tick).
	var/list/implants = list() // ALLOW(instance_list): d: one per transcore database (a handful)

	var/core_dumped = FALSE
	var/key // Key for this DB

/datum/transcore_db/proc/m_backup(datum/mind/mind, obj/item/nif/nif, one_time = FALSE)
	ASSERT(mind)
	if(!mind.name || core_dumped)
		return 0

	var/datum/transhuman/mind_record/MR

	if(mind.name in backed_up)
		MR = backed_up[mind.name]
		MR.last_update = world.time
		MR.one_time = one_time

		//Pass a 0 to not change NIF status (because the elseif is checking for null)
		if(nif)
			MR.nif_path = nif.type
			MR.nif_durability = nif.durability
			var/list/nifsofts = list()
			for(var/N in nif.nifsofts)
				if(N)
					var/datum/nifsoft/nifsoft = N
					nifsofts += nifsoft.type
			MR.nif_software = nifsofts
			MR.nif_savedata = nif.save_data.Copy()
		else if(isnull(nif)) //Didn't pass anything, so no NIF
			MR.nif_path = null
			MR.nif_durability = null
			MR.nif_software = null
			MR.nif_savedata = null

	else
		MR = new(mind, mind.current, add_to_db = TRUE, one_time = one_time, database_key = src.key)

	return 1

// Send a past-due notification to the proper radio channel.
/datum/transcore_db/proc/notify(datum/transhuman/mind_record/MR)
	ASSERT(MR)
	var/datum/transcore_db/db = GLOB.transcore_service.db_by_mind_name(MR.mindname)
	var/datum/transhuman/body_record/BR = db.body_scans[MR.mindname]
	if(!BR)
		GLOB.global_announcer.autosay("[MR.mindname] is past-due for a mind backup, but lacks a corresponding body record.", "TransCore Oversight", "Medical")
		return
	GLOB.global_announcer.autosay("[MR.mindname] is past-due for a mind backup.", "TransCore Oversight", BR.synthetic ? "Science" : "Medical")

// Called from mind_record to add itself to the transcore.
/datum/transcore_db/proc/add_backup(datum/transhuman/mind_record/MR)
	ASSERT(MR)
	backed_up[MR.mindname] = MR
	backed_up = sortAssoc(backed_up)

// Remove a mind_record from the backup-checking list.  Keeps track of it in has_left // Why do we do that? ~Leshana
/datum/transcore_db/proc/stop_backup(datum/transhuman/mind_record/MR)
	ASSERT(MR)
	LAZYSET(has_left, MR.mindname, MR)
	backed_up.Remove("[MR.mindname]")
	MR.cryo_at = world.time

// Called from body_record to add itself to the transcore.
/datum/transcore_db/proc/add_body(datum/transhuman/body_record/BR)
	ASSERT(BR)
	if(body_scans[BR.mydna.name])
		qdel(body_scans[BR.mydna.name])
	body_scans[BR.mydna.name] = BR
	body_scans = sortAssoc(body_scans)

// Remove a body record from the database (Usually done when someone cryos)  // Why? ~Leshana
/datum/transcore_db/proc/remove_body(datum/transhuman/body_record/BR)
	ASSERT(BR)
	body_scans.Remove("[BR.mydna.name]")

// Moves all mind records from the databaes into the disk and shuts down all backup canary processing.
/datum/transcore_db/proc/core_dump(obj/item/disk/transcore/disk)
	ASSERT(disk)
	GLOB.global_announcer.autosay("An emergency core dump has been initiated!", "TransCore Oversight", "Command")
	GLOB.global_announcer.autosay("An emergency core dump has been initiated!", "TransCore Oversight", "Medical")

	disk.stored += backed_up
	backed_up.Cut()
	core_dumped = TRUE
	return length(disk.stored)

#undef SSTRANSCORE_BACKUPS
#undef SSTRANSCORE_IMPLANTS

/// The database owns its records: mind records (backed_up, and has_left once they cryo) and
/// body records, keyed by name. A core dump moves the mind records to the disk first.
DECLARE_REF(/datum/transcore_db, "backed_up", OWNED_VALUES, null)
DECLARE_REF(/datum/transcore_db, "has_left", OWNED_VALUES, null)
DECLARE_REF(/datum/transcore_db, "body_scans", OWNED_VALUES, null)

/// Resleeving implant scan and backup staleness (was SStranscore, 3 min, background).
/datum/om/behaviour/world/transcore
	name = "world: transcore"
	every = 3 MINUTES
	lane = LANE_BACKGROUND
	runlevels = RUNLEVEL_GAME

/datum/om/behaviour/world/transcore/service()
	return GLOB.transcore_service
