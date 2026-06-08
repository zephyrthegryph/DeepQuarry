// A datum that holds information about a specific department.
// It is held inside, and managed by, the SSjob subsystem automatically,
// just define a department, and put that department's name in one or more job datums' departments list.

/datum/department
	var/name = "NOPE"		// Name used in UIs, and the index for the department assoc list in SSjob.
	var/short_name = "NO"	// Shorter name, used for things like external Topic() responses.
	var/color = "#000000"	// Color to use in UIs to represent this department.
	var/list/jobs = list()	// Assoc list. Key is the job title, and the value is a reference to the job datum. Populated by SSjob subsystem.
	var/list/primary_jobs = list() // Same as above, but only jobs with their 'primary' department are put here. Primary being the first department in their list.
	var/sorting_order = 0	// Used to sort departments, e.g. Command always being on top.
	var/visible = TRUE		// If false, it should not show up on things like the manifest or ID computer.
	var/assignable = TRUE	// Similar for above, but only for ID computers and such. Used for silicon department.
	var/centcom_only = FALSE

	/// Accesses held by every member of this department.
	/// These are automatically merged into the result of /datum/job/proc/get_access() for any job
	/// that lists this department, so adding a new shared access requires only one edit here.
	/// Must be a strict subset of every member job's full access list so that current behaviour
	/// is preserved — the union of job.access and department.default_access equals job.access.
	var/list/default_access = list()

	/// The full set of access flags associated with this department's facilities.
	/// Not all jobs receive all of these; the list exists so designers can see the
	/// complete department access space and choose appropriate subsets per job.
	var/list/specialized_access = list()

/datum/department/command
	name = DEPARTMENT_COMMAND
	short_name = "Heads"
	color = "#3333FF"
	sorting_order = 10
	// Command jobs differ too greatly to share a universal default_access subset;
	// the captain overrides get_access() entirely, and the HoP/Secretary lists diverge.
	specialized_access = list(
		ACCESS_HEADS, ACCESS_CAPTAIN, ACCESS_ALL_PERSONAL_LOCKERS,
		ACCESS_HEADS_VAULT, ACCESS_CHANGE_IDS, ACCESS_AI_UPLOAD,
		ACCESS_TELEPORTER, ACCESS_TCOMSAT, ACCESS_KEYCARD_AUTH,
		ACCESS_RC_ANNOUNCE, ACCESS_HOP,
	)

/datum/department/security
	name = DEPARTMENT_SECURITY
	short_name = "Sec"
	color = "#8E0000"
	sorting_order = 6
	// All security jobs carry these six accesses regardless of rank.
	default_access = list(
		ACCESS_SECURITY, ACCESS_SEC_DOORS,
		ACCESS_BRIG,
		ACCESS_MAINT_TUNNELS, ACCESS_EXTERNAL_AIRLOCKS, ACCESS_EVA,
	)
	specialized_access = list(
		ACCESS_SECURITY, ACCESS_SEC_DOORS,
		ACCESS_BRIG, ACCESS_ARMORY, ACCESS_FORENSICS_LOCKERS,
		ACCESS_MORGUE,
		ACCESS_MAINT_TUNNELS, ACCESS_EXTERNAL_AIRLOCKS, ACCESS_EVA,
		ACCESS_HOS,
	)

/datum/department/engineering
	name = DEPARTMENT_ENGINEERING
	short_name = "Eng"
	color = "#B27300"
	sorting_order = 5
	// All engineering jobs carry these seven accesses regardless of specialisation.
	default_access = list(
		ACCESS_EVA,
		ACCESS_ENGINE, ACCESS_ENGINE_EQUIP, ACCESS_TECH_STORAGE,
		ACCESS_MAINT_TUNNELS, ACCESS_EXTERNAL_AIRLOCKS, ACCESS_CONSTRUCTION,
	)
	specialized_access = list(
		ACCESS_EVA,
		ACCESS_ENGINE, ACCESS_ENGINE_EQUIP, ACCESS_TECH_STORAGE,
		ACCESS_MAINT_TUNNELS, ACCESS_EXTERNAL_AIRLOCKS,
		ACCESS_CONSTRUCTION, ACCESS_ATMOSPHERICS, ACCESS_EMERGENCY_STORAGE,
		ACCESS_CE,
	)

/datum/department/medical
	name = DEPARTMENT_MEDICAL
	short_name = "Med"
	color = "#006600"
	sorting_order = 4
	// All medical jobs carry these two accesses at minimum.
	default_access = list(
		ACCESS_MEDICAL, ACCESS_MORGUE,
	)
	specialized_access = list(
		ACCESS_MEDICAL, ACCESS_MORGUE, ACCESS_MEDICAL_EQUIP,
		ACCESS_SURGERY, ACCESS_CHEMISTRY, ACCESS_GENETICS, ACCESS_VIROLOGY,
		ACCESS_PSYCHIATRIST,
		ACCESS_EVA, ACCESS_MAINT_TUNNELS, ACCESS_EXTERNAL_AIRLOCKS,
		ACCESS_CMO,
	)

/datum/department/research
	name = DEPARTMENT_RESEARCH
	short_name = "Sci"
	color = "#A65BA6"
	sorting_order = 3
	// All research jobs carry these four accesses.
	default_access = list(
		ACCESS_RESEARCH, ACCESS_ROBOTICS, ACCESS_TOX, ACCESS_TOX_STORAGE,
	)
	specialized_access = list(
		ACCESS_RESEARCH, ACCESS_ROBOTICS, ACCESS_TOX, ACCESS_TOX_STORAGE,
		ACCESS_XENOBIOLOGY, ACCESS_XENOARCH, ACCESS_XENOBOTANY,
		ACCESS_GENETICS, ACCESS_MORGUE, ACCESS_TECH_STORAGE, ACCESS_HYDROPONICS,
		ACCESS_NETWORK, ACCESS_RD,
	)

/datum/department/cargo
	name = DEPARTMENT_CARGO
	short_name = "Car"
	color = "#BB9040"
	sorting_order = 2
	// All cargo jobs share access to the core supply chain.
	default_access = list(
		ACCESS_MAINT_TUNNELS, ACCESS_MAILSORTING,
		ACCESS_CARGO, ACCESS_CARGO_BOT,
		ACCESS_MINING, ACCESS_MINING_STATION,
	)
	specialized_access = list(
		ACCESS_MAINT_TUNNELS, ACCESS_MAILSORTING,
		ACCESS_CARGO, ACCESS_CARGO_BOT,
		ACCESS_MINING, ACCESS_MINING_OFFICE, ACCESS_MINING_STATION,
		ACCESS_QM, ACCESS_RC_ANNOUNCE,
	)

/datum/department/civilian
	name = DEPARTMENT_CIVILIAN
	short_name = "Civ"
	color = "#A32800"
	sorting_order = 1
	// Civilian jobs are too varied to share a universal default_access.
	// The specialized list documents the full set of civilian-area accesses
	// so designers can see what is available when defining a new civilian job.
	specialized_access = list(
		ACCESS_BAR, ACCESS_KITCHEN, ACCESS_HYDROPONICS,
		ACCESS_JANITOR, ACCESS_MAINT_TUNNELS,
		ACCESS_LIBRARY, ACCESS_LAWYER,
		ACCESS_CHAPEL_OFFICE, ACCESS_CREMATORIUM, ACCESS_MORGUE,
		ACCESS_ENTERTAINMENT,
	)

// Mostly for if someone wanted to rewrite manifest code to be map-agnostic.
/datum/department/misc
	name = "Miscellaneous"
	short_name = "Misc"
	color = "#666666"
	sorting_order = -5
	assignable = FALSE

/datum/department/synthetic
	name = DEPARTMENT_SYNTHETIC
	short_name = "Bot"
	color = "#222222"
	sorting_order = -1
	assignable = FALSE

// This one isn't very useful since no real centcom jobs exist yet.
// Instead the jobs like ERT are hardcoded in.
/datum/department/centcom
	name = "Central Command"
	short_name = "Centcom"
	color = "#A52A2A"
	sorting_order = 20 // Above Command.
	centcom_only = TRUE


// === merged from department_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/department/noncrew
	name = DEPARTMENT_NONCREW
	short_name = "N/A"
	sorting_order = -99
	visible = FALSE
	assignable = FALSE
