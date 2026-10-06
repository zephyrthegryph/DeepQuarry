/world/New()
    ..()
    var/datum/a/A = new
    var/datum/b/B = new
    phase0_preprocess_observe("a_file_suffix", copytext(replacetext(A.file_value, "\\", "/"), -9), "a/body.dm")
    phase0_preprocess_observe("a_line", A.line_value, 2)
    phase0_preprocess_observe("b_file_suffix", copytext(replacetext(B.file_value, "\\", "/"), -9), "b/body.dm")
    phase0_preprocess_observe("b_line", B.line_value, 2)
    phase0_preprocess_finish()
