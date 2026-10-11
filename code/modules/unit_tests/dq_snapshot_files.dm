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
 *
 * Factored op pins (tools/dq_pin_factor.py): the rows every type inherits are written once, in a base file
 * `snapshots/op_bases/<base type>.txt`, one block per group (`actor|held item`). A type file then reads
 *   `@obj.item human|none`   the base block of that group, followed by its delta:
 *   `-menu: Pick up`         a block row this type does not have (`<group> menu: Pick up`),
 *   `+2 menu: Use`           a row it adds, at index 2 (0-based) of the group;
 * any other line is a literal row. dq_snapshot_file_rows() expands it back to exactly the recorded rows, so
 * comparison is unchanged. A bless writes plain rows; dq_focused_test.sh re-factors them after the run.
 */

#define DQ_SNAPSHOT_ROOT "code/modules/unit_tests/snapshots/"

/// The file that holds `type`'s rows under `dir` (a directory path ending in /).
/proc/dq_snapshot_type_file(dir, type)
	return "[dir][replacetext(copytext("[type]", 2), "/", ".")].txt"

/// Whether this run writes snapshots instead of checking them (`--bless`).
/proc/dq_snapshot_blessing()
	return world.params?["snapshot-bless"] == "1"

#define DQ_SNAPSHOT_BASES "code/modules/unit_tests/snapshots/op_bases/"

/// The lines of one snapshot file as written (blank lines dropped, CRLF tolerated).
/proc/dq_snapshot_plain_rows(file_name)
	. = list()
	var/text = file2text(file_name)
	if(!text)
		return
	for(var/line in splittext(text, "\n"))
		line = replacetext(line, ascii2text(13), "")
		if(length(line))
			. += line

/// The rows of one snapshot file, a factored op pin expanded against its base blocks.
/proc/dq_snapshot_file_rows(file_name)
	. = dq_snapshot_plain_rows(file_name)
	for(var/line in .)
		if(copytext(line, 1, 2) == "@")
			return dq_snapshot_expand(., file_name)

/// The op-pin group of a row: the text before its first space when that holds a `|` (`human|/obj/item/tool/crowbar`), else null.
/proc/dq_snapshot_row_group(row)
	var/space = findtext(row, " ")
	if(space <= 1)
		return null
	var/key = copytext(row, 1, space)
	return findtext(key, "|") ? key : null

/// The rows of `base`'s block for group `key` (snapshots/op_bases/<base>.txt, read once per run), or null.
/proc/dq_snapshot_base_block(base, key)
	var/static/list/blocks_by_base = list()
	var/list/blocks = blocks_by_base[base]
	if(!blocks)
		blocks = list()
		for(var/row in dq_snapshot_plain_rows("[DQ_SNAPSHOT_BASES][base].txt"))
			var/group = dq_snapshot_row_group(row)
			if(!group)
				continue
			var/list/block = blocks[group]
			if(!block)
				block = list()
				blocks[group] = block
			block += row
		blocks_by_base[base] = blocks
	return blocks[key]

/// Expands a factored op pin (see the header): `@base group` lines with their `-row` / `+index row` deltas.
/proc/dq_snapshot_expand(list/lines, file_name)
	. = list()
	var/list/group_rows
	var/group
	var/count = length(lines)
	for(var/i in 1 to count + 1)
		var/line = i <= count ? lines[i] : null
		var/first = line ? copytext(line, 1, 2) : null
		if(group_rows && (first == "-" || first == "+"))
			if(first == "-")
				group_rows -= "[group] [copytext(line, 2)]"
			else
				var/plus_space = findtext(line, " ")
				var/index = text2num(copytext(line, 2, plus_space)) + 1
				var/row = "[group] [copytext(line, plus_space + 1)]"
				if(index > length(group_rows))
					group_rows += row
				else
					group_rows.Insert(index, row)
			continue
		if(group_rows)
			. += group_rows
			group_rows = null
		if(isnull(line))
			break
		if(first != "@")
			. += line
			continue
		var/space = findtext(line, " ")
		group = copytext(line, space + 1)
		var/list/block = dq_snapshot_base_block(copytext(line, 2, space), group)
		if(!block)
			// A row no capture produces, so the comparison fails and names the reference.
			. += "unresolved snapshot base in [file_name]: [line] (python3 tools/dq_pin_factor.py)"
			continue
		group_rows = block.Copy()

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
	// Each differing row once, with the types it differs for: a change to an inherited row reads as one line, not one per type.
	var/list/mismatches = list()
	for(var/file_name in bad_files)
		mismatches["[dir][file_name] names no type (renamed or deleted?): delete or rename the file"] = list()
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
				dq_snapshot_note_mismatch(mismatches, "new or changed snapshot: [line]", type)
				differs = TRUE
		for(var/line in expected)
			if(!(line in actual))
				dq_snapshot_note_mismatch(mismatches, "missing snapshot: [line]", type)
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
		var/list/types = mismatches[row]
		switch(length(types))
			if(0)
				report += "\n[row]"
			if(1)
				report += "\n[row] ([types[1]])"
			else
				report += "\n[row] ([length(types)] types: [jointext(types.Copy(1, min(length(types), 3) + 1), ", ")][length(types) > 3 ? ", ..." : ""])"
	return report

/// Records that `row` differs for `type` (each distinct row is reported once, with its types).
/proc/dq_snapshot_note_mismatch(list/mismatches, row, type)
	var/list/types = mismatches[row]
	if(!types)
		types = list()
		mismatches[row] = types
	types += type
