# Injects `dq_apply_material_synergies(src) // DQAdd` at the end of every
# /obj/machinery/X/RefreshParts() override. If the function ends with a
# trailing `return` (possibly with a value), the injection happens
# immediately before that return. Otherwise it's appended as the last
# line of the function body.
#
# Function body is detected by a tab-indented continuation; the function
# ends when we hit a non-indented non-blank line or EOF.

BEGIN { in_func = 0; idx = 0 }

# Start of a RefreshParts override.
/^\/obj\/machinery\/.*\/RefreshParts\(\)[ \t]*$/ {
    if (in_func) { flush() }
    print
    in_func = 1
    idx = 0
    delete buf
    next
}

# End-of-function: non-tab, non-blank line resets state.
in_func && /^[^\t\n]/ && !/^[ \t]*$/ {
    flush()
    in_func = 0
    idx = 0
    delete buf
    print
    next
}

# Inside the function body — collect lines for post-processing.
in_func {
    buf[idx++] = $0
    next
}

# Outside any override — pass through.
{ print }

END {
    if (in_func) { flush() }
}

# Scan the buffer for the last non-blank line. If it's a `return`
# statement (with or without a value), insert the synergy call before
# it. Otherwise append at the end.
function flush(    i, last, line, inserted) {
    last = -1
    for (i = idx - 1; i >= 0; i--) {
        if (buf[i] !~ /^[ \t]*$/) {
            last = i
            break
        }
    }
    inserted = 0
    for (i = 0; i < idx; i++) {
        if (i == last && buf[i] ~ /^[ \t]+return([ \t]+|[ \t]*$)/) {
            print "\tdq_apply_material_synergies(src) // DQAdd"
            inserted = 1
        }
        print buf[i]
    }
    if (!inserted) {
        # Append at the end of the function body.
        print "\tdq_apply_material_synergies(src) // DQAdd"
    }
}
