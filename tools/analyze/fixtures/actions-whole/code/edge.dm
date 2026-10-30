// ACTION(line_comment_must_not_generate, num/value)
/* outer /* ACTION(nested_comment_must_not_generate, num/value) */ */
var/text = "ACTION(string_must_not_generate, num/value)"
"ACTION(standalone_quote_must_not_generate, num/value)"
ACTION(edge_continued, num/value, \
    FIXED)
ACTION(edge_quoted, text/value, notice = /datum/notice/edge_alias /* inline comment */)
