//! Original tracked fixture assertions over the same checked native kernel.
//! Plain fixture DATA; no semantic/source/Root completion grant is issued.
use std::collections::BTreeSet;
use crate::{tree::SourceFile,tracked_policy::*,derived_selftest_policy::Failure,key_policy_control::{self as kc,Control}};
use crate::selftest_source_policy::{source,Views};
pub fn run<C:Control<Error=Failure>,T:Control<Error=Failure>>(c:&mut C,temp:&mut T)->Result<String,Failure>{
 let mut files=Vec::new();for(rel,text)in SELFTEST{kc::row(c,&mut files)?;files.push(source(rel,text,c)?);}
 let mut checked=Views{inner:c,files:&files};let mut scratch=Views{inner:temp,files:&files};let c=&mut checked;let temp=&mut scratch;
 let mut tracked=Tracked::new();for f in &files{tracked_from_text_using(f,&mut tracked,false,c,temp)?;}
 let Some(pats)=build_pats_using(&tracked,c)?else{return Err(Failure::Assertion(kc::own(c,"no tracked vars in the fixtures")?))};
 captures_admission(c,Some(&pats),None)?;
 let mut got=Vec::new();let mut setters=0usize;
 for f in &files{
  let mut allowed=BTreeSet::new();for number in 1..=f.raw().num_lines(){temp.checkpoint()?;if crate::allow::kept_using(f,number,"tracked",temp)?.is_some(){kc::reserve(c,||Some(256))?;allowed.insert(number);}}
  let(hits,s)=scan_one_using(&tracked,&pats,&Tracked::new(),None,f,&BTreeSet::new(),c,&mut|line|Ok(allowed.contains(&line)))?;
  setters=setters.checked_add(s.len()).ok_or_else(||c.overflow())?;
  for h in hits{kc::row(c,&mut got)?;got.push((kc::own(c,&f.rel)?,h.line,kc::own(c,h.msg.split(' ').next().unwrap_or(""))?));}
 }
 let mut want=Vec::new();for(rel,line,var)in SELFTEST_EXPECT{kc::row(c,&mut want)?;want.push((kc::own(c,rel)?,*line,kc::own(c,var)?));}
 if got==want&&setters==2{kc::format(c,format_args!("({} fixtures)",want.len()))}else{Err(Failure::Assertion(kc::format(c,format_args!("expected {:?}, got {:?}, setters {}",want,got,setters))?))}
}
/// The Python's `SELFTEST` fixtures (code/a.dm, code/b.dm; the texts start with a newline).
pub(crate) const SELFTEST: &[(&str, &str)] = &[
    (
        "code/a.dm",
        r#"
/obj/machinery/pump
	var/target_pressure = 100
	var/other = 1
TRACKED(/obj/machinery/pump, target_pressure)

/obj/machinery/pump/bigger
	target_pressure = 200

/obj/machinery/pump/proc/bad_direct()
	target_pressure = 5
	src.target_pressure += 1
	target_pressure++
	--target_pressure

/obj/machinery/pump/proc/good_read()
	if(target_pressure == 5)
		other = target_pressure
	set_target_pressure(7)

/obj/machinery/pump/proc/shadowed()
	var/target_pressure = 3
	target_pressure -= 1

/obj/machinery/pump/proc/allowed_write()
	target_pressure = 1 // ALLOW(tracked): fixture keep

/obj/machinery/pump/bigger/proc/subtype_write()
	target_pressure = 9

/obj/machinery/pump/bigger/set_target_pressure(value)
	target_pressure = value * 2
	return TRUE

/obj/other_thing/proc/unrelated()
	target_pressure = 4

/proc/external(obj/machinery/pump/P, obj/other_thing/Q)
	P.target_pressure = 3
	Q.target_pressure = 3
	var/obj/machinery/pump/bigger/B = P
	B.target_pressure -= 2
	unknown.target_pressure = 1
	// P.target_pressure = 8 in a comment
	var/s = "P.target_pressure = 8"

/obj/machinery/valve
	var/open = FALSE
SETTER(/obj/machinery/valve, open)

/obj/machinery/valve/proc/set_open(value)
	open = value
	update_pipes()

/obj/machinery/valve/proc/bad_open()
	open = TRUE

/proc/external_valve(obj/machinery/valve/V)
	V.open = FALSE
	if(V.open == TRUE)
		return
"#,
    ),
    (
        "code/b.dm",
        r#"
/obj/gadget
	var/total = 0

/obj/gadget/derived()
	. = ..()
	. += derive(nameof(total), nameof(level))

/obj/gadget/proc/oops()
	total = 5
"#,
    ),
];

pub(crate) const SELFTEST_EXPECT: &[(&str, usize, &str)] = &[
    ("code/a.dm", 11, "target_pressure"),
    ("code/a.dm", 12, "target_pressure"),
    ("code/a.dm", 13, "target_pressure"),
    ("code/a.dm", 14, "target_pressure"),
    ("code/a.dm", 29, "target_pressure"),
    ("code/a.dm", 39, "P.target_pressure"),
    ("code/a.dm", 42, "B.target_pressure"),
    ("code/a.dm", 56, "open"),
    ("code/a.dm", 59, "V.open"),
    ("code/b.dm", 10, "total"),
];


#[cfg(all(test,feature="native-policy"))]mod controls{
 use super::*;use crate::{captured_generator_budget::Budget,derived_selftest_policy::NativeAssertions};
 #[test]fn actual_native_tracked_fixture_uses_original_assertions_and_checked_raw_kernel(){let budget=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let actual=run(&mut NativeAssertions{budget:&budget,poll:&||Ok(())},&mut NativeAssertions{budget:&budget,poll:&||Ok(())}).unwrap();assert_eq!(actual,"(10 fixtures)");}
 #[test]fn actual_native_tracked_fixture_preserves_first_io_and_quota_then_recovers(){let budget=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let fail=||Err(std::io::Error::from_raw_os_error(1450));assert!(matches!(run(&mut NativeAssertions{budget:&budget,poll:&fail},&mut NativeAssertions{budget:&budget,poll:&fail}),Err(Failure::Operational(actual))if actual.raw_os_error()==Some(1450)));let tight=Budget::new(1024).unwrap();assert!(matches!(run(&mut NativeAssertions{budget:&tight,poll:&||Ok(())},&mut NativeAssertions{budget:&tight,poll:&||Ok(())}),Err(Failure::Operational(actual))if actual.kind()==std::io::ErrorKind::OutOfMemory));let healthy=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();assert!(run(&mut NativeAssertions{budget:&healthy,poll:&||Ok(())},&mut NativeAssertions{budget:&healthy,poll:&||Ok(())}).is_ok());}
}
