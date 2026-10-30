// STAT(/obj/edge, line_comment_must_not_generate, ALL)
/* outer /* STAT(/obj/edge, nested_comment_must_not_generate, ALL) */ */
var/text = "STAT(/obj/edge, string_must_not_generate, ALL)"
"STAT(/obj/edge, standalone_quote_must_not_generate, ALL)"
STAT(/obj/edge, continued, SUM, base = list(1, \
    2), reads = list("x, // y", "/*z*/"))
STAT(/obj/edge, quoted, MAX, base = "STAT(/obj/no, not_real, ALL) // /* */") // tail comment
