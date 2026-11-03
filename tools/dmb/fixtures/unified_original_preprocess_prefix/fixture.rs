//! INPUT only. The actual pinned original frontend decides whether later
//! preprocessing is demanded; no native outcome or expected rows are shared.
pub const CASES:&[(&str,&str,&str)]=&[
 ("comma_then_missing_include","/datum/prior\n    var/first, second\n#include \"never_after_fatal.dm\"\n",""),
 ("comma_then_error_directive","/datum/prior\n    var/first, second\n#error NEVER_AFTER_FATAL\n",""),
 ("parameter_then_missing_manifest_include","/proc/bad(argument=)\n    return 1\n","#include \"never_manifest_after_fatal.dm\"\n"),
 ("missing_include_before_comma","#include \"actually_demanded_missing.dm\"\n/datum/prior\n    var/first, second\n",""),
 ("complete_then_error_directive","/datum/prior\n    var/first\n#error ACTUALLY_DEMANDED\n",""),
 ("macro_before_parameter_then_error","#define VALUE 1\n/proc/good(argument=VALUE)\n    return argument\n/proc/bad(argument=)\n    return 1\n#error NEVER_AFTER_PARAMETER_FATAL\n",""),
];
