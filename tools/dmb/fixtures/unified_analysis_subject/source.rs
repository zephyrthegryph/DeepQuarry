//! Initial source bytes shared by independent original and native subjects.
pub const MODES:&[&str]=&["real","absent","noninclude","invalid_utf8"];
pub fn files(mode:&str)->Vec<(&'static str,&'static [u8])>{
 let mut rows=vec![
 ("code/__defines/subject.dm",b"#define SUBJECT_VALUE 1\n".as_slice()),
 ("code/a.dm",b"#define ORDER_VALUE 1\n/datum/first_order\n".as_slice()),
 ("code/a/a.dm",b"#undef ORDER_VALUE\n#define ORDER_VALUE 2\n/datum/second_order\n".as_slice()),
 ("code/probe.dm",b"#if DM_BUILD == 1666 && SPACEMAN_DMM\n/proc/probe()\n    return SUBJECT_VALUE\n#else\n#error incorrect original subject context\n#endif\n".as_slice()),
 ("code/z.dm",b"#if ORDER_VALUE == 2\n/datum/ordered_correct\n#else\n#error incorrect relative string include order\n#endif\n".as_slice()),
 ("code/.hidden.dm",b"#error hidden file must not enter old CODE_DM subject\n".as_slice())];
 match mode{"real"=>rows.push(("deepquarry.dme",b"#include \"code/__defines/subject.dm\"\n#include \"code/probe.dm\"\n/datum/real_manifest\n")),"absent"=>(),"noninclude"=>rows.push(("deepquarry.dme",b"/datum/ignored_manifest\n")),"invalid_utf8"=>rows.push(("deepquarry.dme",b"\xff#include \"unobserved-invalid-manifest-source.dm\"\n")),_=>panic!("unknown initial subject case")};rows
}
