/**
 * Snapshot files: a recorded snapshot kept as one text file per type, outside the DM.
 *
 * A snapshot test (the i7 interaction snapshots, the conversion pins in dq_conversion_pins.dm) records a few
 * text rows per type. The rows live in `code/modules/unit_tests/snapshots/<snapshot>/<type>.txt`, where
 * <type> is the type path without its leading slash and with `/` written as `.`
 * (`/obj/machinery/atm` is `obj.machinery.atm.txt`), one row per line. So:
 *
 *   - two branches that touch different types never edit the same file (the old inline `expected = list(...)`
 *     conflicted on nearly every parallel conversion);
 *   - the files are read at run time, not compiled: a snapshot-only change reuses the cached .dmb;
 *   - the set of types is the set of files: adding a type is adding its file (an empty file is a type
 *     not recorded yet, which the next run records instead of failing; tools/dq_pin.sh makes them).
 *
 * Blessing: `bash tools/dq_focused_test.sh --bless <test>` (world param snapshot-bless=1) writes each type's
 * current rows over its file instead of failing; review the diff and commit it. Without it, a mismatch fails
 * with every differing row, and the current rows are written to data/test-snapshots/<snapshot>/ for a look.
 * Guide: doc/rewrite/snapshot_pins.md.
 */

#define DQ_SNAPSHOT_ROOT "code/modules/unit_tests/snapshots/"

/// The file that holds `type`'s rows under `dir` (a directory path ending in /).
/proc/dq_snapshot_type_file(dir, type)
	return "[dir][replacetext(copytext("[type]", 2), "/", ".")].txt"

/// Whether this run writes snapshots instead of checking them (`--bless`).
/proc/dq_snapshot_blessing()
	return world.params?["snapshot-bless"] == "1"

/// The rows of one snapshot file (blank lines dropped, CRLF tolerated).
/proc/dq_snapshot_file_rows(file_name)
	. = list()
	var/text = file2text(file_name)
	if(!text)
		return
	for(var/line in splittext(text, "\n"))
		line = replacetext(line, ascii2text(13), "")
		if(length(line))
			. += line

/**
 * Every type recorded under `dir`: an assoc list type => its rows, in type order. A file whose name is
 * not a type (renamed or deleted since) is listed in `bad` and left out.
 */
/proc/dq_snapshot_read_dir(dir, list/bad)
	. = list()
	var/list/names = flist(dir)
	sortTim(names, GLOBAL_PROC_REF(cmp_text_asc))
	for(var/name in names)
		if(copytext(name, -4) != ".txt")
			continue
		var/path = text2path("/[replacetext(copytext(name, 1, -4), ".", "/")]")
		if(!path)
			bad?.Add(name)
			continue
		.[path] = dq_snapshot_file_rows("[dir][name]")

/// Writes `type`'s rows over its file under `dir`.
/proc/dq_snapshot_write(dir, type, list/rows)
	var/file_name = dq_snapshot_type_file(dir, type)
	fdel(file_name)
	text2file(length(rows) ? "[jointext(rows, "\n")]\n" : "", file_name)

/**
 * Compares the rows a snapshot test produced with the recorded ones: null when they match (or when this run
 * blesses, after writing them), else the failure text listing every differing row. `dir` is the snapshot
 * directory, `name` its short name (for data/test-snapshots/<name>/).
 */
/proc/dq_snapshot_compare(dir, name, list/actual_by_type, list/expected_by_type, list/bad_files)
	if(dq_snapshot_blessing())
		for(var/type in actual_by_type)
			dq_snapshot_write(dir, type, actual_by_type[type])
		log_test("snapshot [name]: blessed [length(actual_by_type)] type file(s) under [dir]")
		return null
	var/list/mismatches = list()
	for(var/file_name in bad_files)
		mismatches += "[dir][file_name] names no type (renamed or deleted?): delete or rename the file"
	for(var/type in actual_by_type)
		var/list/actual = actual_by_type[type]
		var/list/expected = expected_by_type[type] || list()
		// An empty file is a type not recorded yet (tools/dq_pin.sh makes one): record it, don't fail.
		if(!length(expected) && length(actual))
			dq_snapshot_write(dir, type, actual)
			log_test("snapshot [name]: recorded [type] ([length(actual)] rows) into [dq_snapshot_type_file(dir, type)]")
			continue
		var/differs = FALSE
		for(var/line in actual)
			if(!(line in expected))
				mismatches += "new or changed snapshot: [line]"
				differs = TRUE
		for(var/line in expected)
			if(!(line in actual))
				mismatches += "missing snapshot: [line]"
				differs = TRUE
		// The current rows of a differing type go to data/test-snapshots/<name>/; a type that matches now drops any file an earlier
		// run left there, so the directory never shows rows that no longer differ.
		if(differs)
			dq_snapshot_write("data/test-snapshots/[name]/", type, actual)
		else
			fdel(dq_snapshot_type_file("data/test-snapshots/[name]/", type))
	if(!length(mismatches))
		return null
	var/report = "[length(mismatches)] snapshot rows differ (current rows in data/test-snapshots/[name]/; `bash tools/dq_focused_test.sh --bless <test>` rewrites [dir]):"
	for(var/row in mismatches)
		report += "\n[row]"
	return report
