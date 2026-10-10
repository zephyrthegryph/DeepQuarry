#define SSTRANSCORE_IMPLANTS 1
#define SSTRANSCORE_BACKUPS 2

////////////////////////////////
//// Mind/body data storage system
//// for the resleeving tech
////////////////////////////////

// The transcore system (was SStranscore): the resleeving mind/body databases, with the implant scan and backup
// staleness pass run every 3 minutes. The API is in transcore_api.dm.

// The per-cadence work queue: record/implant -> its database, all round-long system data.

SYSTEM_DEF(transcore)
	name = "Transcore"
	periodic_runlevels = RUNLEVEL_GAME
	/// TRUE while a pass that ran out of budget waits to resume.
	VAR_PRIVATE/resuming = FALSE
	// The old subsystem depended on SSmapping; boot right after it, as before. SSatoms depends on it,
	// since mapload resleeving machines register with the databases.
	needs = list(/datum/system/mapping)

	// THINGS
	var/overdue_time = 6 MINUTES			// Has to be a multiple of the lane's 3 minute cadence, or else will just round up anyway.

	var/current_step = SSTRANSCORE_IMPLANTS

	var/cost_backups = 0
	var/cost_implants = 0

	var/list/datum/transcore_db/databases = list()	// Holds instances of each database
	var/datum/transcore_db/default_db // The default if no specific one is used

	/// The resumable work queue of the current step: implants, then mind records (a relation list,
	/// so an entry deleted mid-run drops out).
	var/list/current_run

/datum/system/transcore/reactions()
	. = ..()
	. += every(3 MINUTES, PROC_REF(scan_step), when = PROC_REF(work_ready), lane = LANE_BACKGROUND)

/datum/system/transcore/initialize()
	initialized = TRUE
	default_db = new()
	databases["default"] = default_db
	for(var/t in subtypesof(/datum/transcore_db))
		var/datum/transcore_db/db = new t()
		if(!db.key)
			WARNING("Instantiated transcore DB without a key: [t]")
			continue
		databases[db.key] = db
	log_world("System [name] initialized: [length(databases)] databases.")

/datum/system/transcore/proc/scan_step(dt)
	var/resumed = resuming
	resuming = FALSE
	var/timer
	if(!resumed)
		current_step = SSTRANSCORE_IMPLANTS
	if(current_step == SSTRANSCORE_IMPLANTS)
		timer = TICK_USAGE
		var/done = process_implants(resumed)
		cost_implants = KERNEL_AVERAGE(cost_implants, TICK_DELTA_TO_MS(TICK_USAGE - timer))
		if(!done)
			resuming = TRUE
			return STEP_YIELD
		resumed = FALSE
		current_step = SSTRANSCORE_BACKUPS
	timer = TICK_USAGE
	var/backups_done = process_backups(resumed)
	cost_backups = KERNEL_AVERAGE(cost_backups, TICK_DELTA_TO_MS(TICK_USAGE - timer))
	if(!backups_done)
		resuming = TRUE
		return STEP_YIELD
	current_step = SSTRANSCORE_IMPLANTS
	return STEP_DONE

/datum/system/transcore/proc/process_implants(resumed = 0)
	if (!resumed)
		// Create a flat list of every implant in every db with a value of the db they're in
		rel_clear(src, nameof(current_run))
		for(var/key in databases)
			var/datum/transcore_db/db = databases[key]
			for(var/obj/item/implant/backup/imp as anything in db.implants)
				rel_add(src, nameof(current_run), imp)

	while(length(current_run))
		var/obj/item/implant/backup/imp = current_run[length(current_run)]
		rel_remove(src, nameof(current_run), imp)
		var/datum/transcore_db/db = imp.our_db()

		//Remove if not in a human anymore (a deleted implant already left both lists).
		if(!isorgan(imp.loc))
			rel_remove(db, nameof(db.implants), imp)
			continue

		//We're in an organ, at least.
		var/obj/item/organ/external/EO = imp.loc
		var/mob/living/carbon/human/H = EO.owner
		if(!H)
			rel_remove(db, nameof(db.implants), imp)
			continue

		//In a human
		H.flag_hud_update(BACKUP_HUD)

		if(H == imp.imp_in() && H.stat < DEAD)
			if(H.mind)
				db.m_backup(H.mind,H.nif)
			else if(H.vr_link && H.vr_link.mind)
				db.m_backup(H.vr_link.mind,H.nif)

		if(KERNEL_OVER_BUDGET)
			return FALSE
	return TRUE

/datum/system/transcore/proc/process_backups(resumed = 0)
	if (!resumed)
		// Create a flat list of every implant in every db with a value of the db they're in
		rel_clear(src, nameof(current_run))
		for(var/key in databases)
			var/datum/transcore_db/db = databases[key]
			for(var/name in db.backed_up)
				rel_add(src, nameof(current_run), db.backed_up[name])

	while(length(current_run))
		var/datum/transhuman/mind_record/curr_MR = current_run[length(current_run)]
		rel_remove(src, nameof(current_run), curr_MR)

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

		if(KERNEL_OVER_BUDGET)
			return FALSE
	return TRUE

/datum/system/transcore/stat_entry(msg)
	msg += "$:{"
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

/datum/transcore_db
	// ALLOW(instance_list): d: one per transcore database (a handful); re-sorted on every write
	var/list/datum/transhuman/mind_record/backed_up = list()	// All known mind records, indexed by MR.mindname/mind.name
	var/list/datum/transhuman/mind_record/has_left		// Why do we even have this?
	// ALLOW(instance_list): d: one per transcore database (a handful); re-sorted on every write
	var/list/datum/transhuman/body_record/body_scans = list()	// All known body records, indexed by BR.mydna.name
	/// All OPERATING backup implants that are being ticked (a relation list: a deleted one drops out).
	var/list/implants

	var/core_dumped = FALSE
	var/key // Key for this DB

CAPABILITIES(/datum/transcore_db)
	ref_many(nameof(implants))
	owns_many(nameof(backed_up), /datum/transhuman/mind_record)
	owns_many(nameof(body_scans), /datum/transhuman/body_record)

/datum/transcore_db/proc/m_backup(datum/mind/mind, obj/item/nif/nif, one_time = FALSE)
	ASSERT(mind)
	if(!mind.name || core_dumped)
		return 0

	var/datum/transhuman/mind_record/MR

	if(mind.name in backed_up)
		MR = backed_up[mind.name]
		EXPIRY_STAMP(MR, last_update, CLOCK_WORLD)
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
	var/datum/transcore_db/db = SStranscore.db_by_mind_name(MR.mindname)
	var/datum/transhuman/body_record/BR = LAZYACCESS(db.body_scans, MR.mindname)
	if(!BR)
		GLOB.global_announcer.autosay("[MR.mindname] is past-due for a mind backup, but lacks a corresponding body record.", "TransCore Oversight", "Medical")
		return
	GLOB.global_announcer.autosay("[MR.mindname] is past-due for a mind backup.", "TransCore Oversight", BR.synthetic ? "Science" : "Medical")

// Called from mind_record to add itself to the transcore.
/datum/transcore_db/proc/add_backup(datum/transhuman/mind_record/MR)
	ASSERT(MR)
	rel_add(src, nameof(backed_up), MR, MR.mindname)
	backed_up = sortAssoc(backed_up) // ALLOW(ownership): the same records re-ordered by name; membership and stamps do not change

// Remove a mind_record from the backup-checking list.  Keeps track of it in has_left // Why do we do that? ~Leshana
/datum/transcore_db/proc/stop_backup(datum/transhuman/mind_record/MR)
	ASSERT(MR)
	rel_move(src, nameof(backed_up), src, nameof(has_left), "[MR.mindname]", "[MR.mindname]")
	EXPIRY_STAMP(MR, cryo_at, CLOCK_WORLD)

// Called from body_record to add itself to the transcore.
/datum/transcore_db/proc/add_body(datum/transhuman/body_record/BR)
	ASSERT(BR)
	rel_add(src, nameof(body_scans), BR, BR.mydna.name) // deletes a record it replaces
	body_scans = sortAssoc(body_scans) // ALLOW(ownership): the same records re-ordered by name; membership and stamps do not change

// Remove a body record from the database (Usually done when someone cryos)  // Why? ~Leshana
/datum/transcore_db/proc/remove_body(datum/transhuman/body_record/BR)
	ASSERT(BR)
	rel_add(src, nameof(body_scans), null, "[BR.mydna.name]")

// Moves all mind records from the databaes into the disk and shuts down all backup canary processing.
/datum/transcore_db/proc/core_dump(obj/item/disk/transcore/disk)
	ASSERT(disk)
	GLOB.global_announcer.autosay("An emergency core dump has been initiated!", "TransCore Oversight", "Command")
	GLOB.global_announcer.autosay("An emergency core dump has been initiated!", "TransCore Oversight", "Medical")

	for(var/name in backed_up.Copy())
		rel_move(src, nameof(backed_up), disk, nameof(disk.stored), name, name) // the disk owns the dumped records
	core_dumped = TRUE
	return length(disk.stored)

#undef SSTRANSCORE_BACKUPS
#undef SSTRANSCORE_IMPLANTS

/// The database owns its records: mind records (backed_up, and has_left once they cryo) and
/// body records, keyed by name. A core dump moves the mind records to the disk first.

CAPABILITIES(/datum/system/transcore)
	ref_many(nameof(current_run))
