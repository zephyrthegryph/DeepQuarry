/// /datum/material must have one definition per proc: a second definition in another file
/// silently overrides the first by include order, which is how the property readers once
/// split across two trees. Scans the source for `/datum/material/proc/<name>(` definitions.
/datum/unit_test/dq_material_proc_single_definition
	var/list/definitions = list()

/datum/unit_test/dq_material_proc_single_definition/Run()
	scan_dir("code/")
	TEST_ASSERT(length(definitions), "the scan found /datum/material procs (source tree readable from the test working directory)")
	for(var/proc_name in definitions)
		var/list/files = definitions[proc_name]
		TEST_ASSERT_EQUAL(length(files), 1, "/datum/material/proc/[proc_name] is defined in [length(files)] files: [english_list(files)]")

/datum/unit_test/dq_material_proc_single_definition/proc/scan_dir(dir)
	for(var/entry in flist(dir))
		if(copytext(entry, -1) == "/")
			scan_dir("[dir][entry]")
		else if(copytext(entry, -3) == ".dm")
			scan_file("[dir][entry]")

/datum/unit_test/dq_material_proc_single_definition/proc/scan_file(path)
	var/text = file2text(path)
	if(!text || !findtext(text, "/datum/material/proc/"))
		return
	for(var/line in splittext(text, "\n"))
		if(copytext(line, 1, 22) != "/datum/material/proc/")
			continue
		var/name_end = findtext(line, "(", 22)
		if(!name_end)
			continue
		var/proc_name = copytext(line, 22, name_end)
		if(!definitions[proc_name])
			definitions[proc_name] = list()
		definitions[proc_name] |= path
