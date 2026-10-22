#!/usr/bin/env bash
# Prints the effective tier of every /datum/unit_test type declared in the given .dm files, one "type<TAB>EXHAUSTIVE|NORMAL" per line
# (type without the /datum/unit_test/ prefix). A type's tier is the nearest `tier =` on itself or an ancestor path; a type with none
# is NORMAL, and a subtype that sets `tier = TEST_TIER_NORMAL` (a /representative) is NORMAL under an exhaustive parent.
# Used by tools/dq_focused_test.sh to refuse an exhaustive sweep without --allow-exhaustive.
#
#   bash tools/dq_test_tiers.sh file.dm [...]
exec awk '
	function top(line) { return line ~ /^[^ \t\/#]/ || (line ~ /^\// ) }
	/^\/datum\/unit_test\// {
		name = $0
		if (name ~ /\/tier[ \t]*=[ \t]*TEST_TIER_[A-Z0-9]+/) {
			v = name; sub(/.*=[ \t]*/, "", v); sub(/[ \t\r].*/, "", v)
			n = name; sub(/^\/datum\/unit_test\//, "", n); sub(/\/tier[ \t]*=.*/, "", n)
			tier[n] = v; seen[n] = 1; next
		}
		sub(/^\/datum\/unit_test\//, "", name); sub(/[ \t\r]+$/, "", name)
		if (name ~ /\/proc\//) next
		sub(/\/(Run|run_[A-Za-z0-9_]+)\(.*$/, "", name)
		sub(/\(.*$/, "", name); sub(/[ \t]*\/\/.*$/, "", name); sub(/[ \t]+$/, "", name)
		if (name == "") next
		cur = name; seen[name] = 1; next
	}
	/^[^ \t\r\/#]/ || /^\/[^\/*]/ { cur = ""; next }
	/^[ \t]+tier[ \t]*=[ \t]*TEST_TIER_[A-Z0-9]+/ {
		if (cur != "") { v = $0; sub(/.*=[ \t]*/, "", v); sub(/[ \t\r\/].*/, "", v); tier[cur] = v }
		next
	}
	END {
		for (t in seen) {
			p = t; eff = "NORMAL"
			while (p != "") {
				if (p in tier) { eff = (tier[p] == "TEST_TIER_EXHAUSTIVE") ? "EXHAUSTIVE" : "NORMAL"; break }
				if (index(p, "/") == 0) break
				sub(/\/[^\/]*$/, "", p)
			}
			print t "\t" eff
		}
	}' "$@" | sort
