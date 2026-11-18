//! Original Sys callback fixtures through the existing native checked kernels.
//! Neutral fixture DATA, never an authored source/model/completion grant.
use crate::{derived_selftest_policy::Failure,key_policy_control::{self as kc,Control},tree::SourceFile};
#[derive(Clone,Copy,Debug)]pub enum Kind{Constructor,Look,ManualLog,StringNames}
impl Kind{pub fn name(self)->&'static str{match self{Self::Constructor=>crate::allow_registry_fields::sys_dx_constructor_shadow::SCOPE_MODULE_NAME,Self::Look=>crate::allow_registry_fields::sys_dx_look_side_effects::SCOPE_MODULE_NAME,Self::ManualLog=>crate::allow_registry_fields::sys_dx_manual_fingerprint_log::SCOPE_MODULE_NAME,Self::StringNames=>crate::allow_registry_fields::sys_dx_string_names::SCOPE_MODULE_NAME}}}
use crate::selftest_source_policy::{source,Views};
fn sorted<C:Control<Error=Failure>>(values:impl Iterator<Item=usize>,c:&mut C)->Result<Vec<usize>,Failure>{let mut out=Vec::new();for value in values{kc::row(c,&mut out)?;out.push(value)}kc::sort_data(&mut out,&mut|a,b|{c.checkpoint()?;Ok::<_,Failure>(a.cmp(b))})?;Ok(out)}
fn ensure<C:Control<Error=Failure>>(okay:bool,args:std::fmt::Arguments<'_>,c:&mut C)->Result<(),Failure>{c.checkpoint()?;if okay{Ok(())}else{Err(Failure::Assertion(kc::format(c,args)?))}}
fn at(text:&str,snippet:&str)->usize{text.split('\n').position(|line|line.contains(snippet)).map_or(0,|n|n+1)}
pub fn run<C:Control<Error=Failure>,T:Control<Error=Failure>>(kind:Kind,c:&mut C,temp:&mut T)->Result<String,Failure>{match kind{Kind::Constructor=>constructor(c,temp),Kind::Look=>appearance(c,temp),Kind::ManualLog=>manual(c,temp),Kind::StringNames=>string_names(c,temp)}}
fn constructor<C:Control<Error=Failure>,T:Control<Error=Failure>>(c:&mut C,temp:&mut T)->Result<String,Failure>{
 use crate::sys_constructor_shadow_policy as policy;
 let preset=kc::format(c,format_args!("{}s.dm",policy::PRESET_FILES))?;let library=kc::format(c,format_args!("{}library/apc.dm",policy::CAPS_DIR))?;
 let mut files=Vec::new();for(rel,text)in[("x.dm",CONSTRUCTOR_FIXTURE),(preset.as_str(),PRESETS_FIXTURE),(library.as_str(),LIBRARY_FIXTURE)]{kc::row(c,&mut files)?;files.push(source(rel,text,c)?);}
 {let mut checked=Views{inner:c,files:&files};let mut scratch=Views{inner:temp,files:&files};let c=&mut checked;let temp=&mut scratch;
 let mut facts=Vec::new();for file in &files{kc::row(c,&mut facts)?;facts.push(policy::file_facts(file,c,temp)?);}
 let context=policy::context(facts.iter().flatten(),std::iter::empty::<&String>(),c)?;
 let mut got=Vec::new();for(file,facts)in files.iter().zip(&facts){let(rows,_)=policy::judge(facts,&context,c)?;if file.rel=="x.dm"{for(_,line)in rows{kc::row(c,&mut got)?;got.push(line)}}}
 let got=sorted(got.into_iter(),c)?;let want=sorted(["airlock/proc/cap_lock()","airlock/cap_has(bits)","console/proc/wall_console()","apc/proc/power_channels()"].iter().map(|snippet|at(CONSTRUCTOR_FIXTURE,snippet)),c)?;
 ensure(got==want,format_args!("dx_constructor_shadow selftest: got {:?}, want {:?}",got,want),c)?;
 }
 let mut files=Vec::new();for(rel,text)in[("code/engine/parts/part.dm","/proc/cooldown(t)\n\treturn t\n"),("code/x.dm",PART_SOURCE)]{kc::row(c,&mut files)?;files.push(source(rel,text,c)?);}
 {let mut checked=Views{inner:c,files:&files};let mut scratch=Views{inner:temp,files:&files};let c=&mut checked;let temp=&mut scratch;
 let mut facts=Vec::new();let mut caps=Vec::new();for file in &files{
  kc::row(c,&mut facts)?;facts.push(policy::file_facts(file,c,temp)?);
  let marker=file.marker();let mut offset=0usize;for line in marker.split_inclusive('\n'){temp.checkpoint()?;if let Some(row)=crate::raw_marker_policy::statement_marker(&marker,offset,line,&["CAPABILITY_TYPE","CAPABILITY_DEF"]){let args=crate::raw_marker_policy::split_args_using(&marker[row.open+1..row.close],temp)?;if let Some(cap)=policy::cap_type(row.name,&args,c)?{kc::row(c,&mut caps)?;caps.push(cap)}}offset=offset.checked_add(line.len()).ok_or_else(||c.overflow())?;}
 }
 let context=policy::context(facts.iter().flatten(),&caps,c)?;let mut got=Vec::new();for facts in &facts{let(_,rows)=policy::judge(facts,&context,c)?;for(_,line)in rows{kc::row(c,&mut got)?;got.push(line)}}
 ensure(got==[2,8],format_args!("part_constructor_shadow selftest: got {:?}, want [2, 8]",got),c)?; }kc::own(c,"dx_constructor_shadow")
}
fn appearance<C:Control<Error=Failure>,T:Control<Error=Failure>>(c:&mut C,temp:&mut T)->Result<String,Failure>{
 let file=source("code/fixture.dm",LOOK_FIXTURE,c)?;let mut checked=Views{inner:c,files:std::slice::from_ref(&file)};let mut scratch=Views{inner:temp,files:std::slice::from_ref(&file)};let c=&mut checked;let temp=&mut scratch;let names=crate::sys_look_effects_policy::names_in_file_using(&file,c,temp)?;let names=crate::sys_look_effects_policy::merge([&names],c)?;let rows=crate::sys_look_effects_policy::judge_using(&file,&names,c,temp)?;let got=sorted(rows.into_iter().map(|(_,line)|line),c)?;
 let want=sorted(["\t\tplaysound(src, 'sound/weld.ogg', 50)","\tlast_state = \"on\"","\ton = TRUE"].iter().map(|snippet|LOOK_FIXTURE.split('\n').position(|line|line==*snippet).map_or(0,|n|n+1)),c)?;
 ensure(got==want,format_args!("dx_look_side_effects selftest: got {:?}, want {:?}",got,want),c)?;kc::own(c,"true")
}
fn manual<C:Control<Error=Failure>,T:Control<Error=Failure>>(c:&mut C,temp:&mut T)->Result<String,Failure>{
 let file=source("x.dm",MANUAL_FIXTURE,c)?;let mut checked=Views{inner:c,files:std::slice::from_ref(&file)};let mut scratch=Views{inner:temp,files:std::slice::from_ref(&file)};let c=&mut checked;let temp=&mut scratch;let facts=crate::manual_log_policy::facts_of_using(&file,c,temp)?;let rows=crate::manual_log_policy::assemble(&[(file.rel.as_str(),&facts)],c)?;let got=sorted(rows.into_iter().map(|(_,_,line)|line),c)?;
 let want=sorted(["\tadd_fingerprint(user)","log_game(\"[user] toggled","message_admins(","log_admin(\"unbolted\")"].iter().map(|snippet|at(MANUAL_FIXTURE,snippet)),c)?;
 ensure(got==want,format_args!("dx_manual_fingerprint_log selftest: got {:?}, want {:?}",got,want),c)?;kc::own(c,"dx_manual_fingerprint_log")
}
fn string_names<C:Control<Error=Failure>,T:Control<Error=Failure>>(c:&mut C,temp:&mut T)->Result<String,Failure>{
 kc::reserve(temp,||STRING_FIXTURE.iter().try_fold(STRING_FIXTURE.len(),|n,line|n.checked_add(line.len()))?.checked_mul(4)?.checked_add(128))?;let text=STRING_FIXTURE.join("\n");let file=source("x.dm",&text,c)?;
 {let mut checked=Views{inner:c,files:std::slice::from_ref(&file)};let mut scratch=Views{inner:temp,files:std::slice::from_ref(&file)};let c=&mut checked;let temp=&mut scratch;
 let accessors=crate::sys_string_names_policy::fallback_using(c)?;let pattern=crate::sys_string_names_policy::call_pattern_using(&accessors,c)?;let mut rows=Vec::new();crate::sys_string_names_policy::scan_lines_using(&file,&accessors,&pattern,&mut rows,c,temp)?;let mut got=Vec::new();for(_,line)in rows{kc::row(c,&mut got)?;got.push(line)}ensure(got==[1,3,4,9,10],format_args!("dx_string_names selftest: got {:?}",got),c)?;
 }
 let file=source("a.dm",ACCESSOR_FIXTURE,c)?;let mut checked=Views{inner:c,files:std::slice::from_ref(&file)};let mut scratch=Views{inner:temp,files:std::slice::from_ref(&file)};let c=&mut checked;let temp=&mut scratch;let got=crate::sys_string_names_policy::file_accessors(&file,c,temp)?;let okay=got.len()==2&&got.get("own_widget").is_some_and(|v|v.as_slice()==[1])&&got.get("om_set").is_some_and(|v|v.as_slice()==[1]);ensure(okay,format_args!("dx_string_names selftest: accessors {:?}",got),c)?;kc::own(c,"dx_string_names")
}

const CONSTRUCTOR_FIXTURE: &str = include_str!("../fixtures/sys__dx_constructor_shadow/code/modules/x/selftest.dm");
const PRESETS_FIXTURE: &str = "
/proc/wall_console(board)
\treturn list()
";
const LIBRARY_FIXTURE: &str = "
/proc/power_channels(list/channels)
\treturn list(new /datum/capability/power_channels)
/proc/wires_of(atom/A)
\treturn cap_of(A, /datum/capability/wires)
/proc/cap_of(atom/A, key)
\treturn null
";


const LOOK_FIXTURE: &str = "
/obj/machinery/vent/appearance_overlays()
\tvar/list/parts = list()
\tparts += \"on\"
\ticon_state = \"vent\"
\tif(welded)
\t\tplaysound(src, 'sound/weld.ogg', 50)
\tlast_state = \"on\"
\treturn parts

/obj/machinery/quiet/appearance_overlays()
\tvar/list/parts = list()
\tparts += \"idle\"
\treturn parts

DECLARE_APPEARANCE_PROC(/obj/machinery/custom, TYPE_PROC_REF(/obj/machinery/custom, custom_look), list())

/obj/machinery/custom/proc/custom_look()
\ticon_state = \"custom\"
\ton = TRUE
\treturn list()
";


const MANUAL_FIXTURE: &str = include_str!("../fixtures/sys__dx_manual_fingerprint_log/code/modules/x/selftest.dm");


const PART_SOURCE:&str="CAPABILITY_TYPE(widget, CAP_WIDGET, /datum/e0_cap/widget, key = NONE)\n/datum/e0_cap/widget/proc/cooldown()\n\treturn 1\n/datum/capability/other/proc/cooldown()\n\treturn 2\n/obj/item/telecube/proc/cooldown()\n\treturn 3\n/datum/e0_cap/widget/sub/proc/cooldown()\n\treturn 4\n";
const STRING_FIXTURE:&[&str]=&[
        r#"own_set(src, "beaker", I)"#,
        "own_set(src, nameof(beaker), I)",
        r#"timed_set(get_holder(x, "a"), "emp", TRUE)"#,
        r#"rel_add(src, "[slot]_link", T)"#,
        "om_set(E, name, value)",
        "/proc/own_set(datum/holder, var_name, datum/value)",
        r#"// own_set(src, "x", I)"#,
        r#"to_chat(user, "own_set(src, \"x\", I)")"#,
        r#"time_left(src, "cooldown")"#,
        r#"own_transfer(src, nameof(a), dest, "b")"#,
        r#"own_transfer(src, nameof(a), dest, nameof(b), member = "x")"#,
    ];
const ACCESSOR_FIXTURE:&str="/proc/own_widget(datum/holder, var_name, datum/value)\n\treturn\n/proc/own_key(datum/D)\n\treturn\n/obj/proc/own_set(var_name)\n\treturn\n/proc/om_set(datum/E, name, value)\n\treturn";

#[cfg(all(test,feature="native-policy"))]mod controls{
 use super::*;use crate::{captured_generator_budget::Budget,derived_selftest_policy::NativeAssertions};
 #[test]fn actual_native_sys_callbacks_execute_all_four_original_fixtures_through_shared_kernels(){for(kind,want)in[(Kind::Constructor,"dx_constructor_shadow"),(Kind::Look,"true"),(Kind::ManualLog,"dx_manual_fingerprint_log"),(Kind::StringNames,"dx_string_names")]{let budget=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();assert_eq!(run(kind,&mut NativeAssertions{budget:&budget,poll:&||Ok(())},&mut NativeAssertions{budget:&budget,poll:&||Ok(())}).unwrap(),want);}}
 #[test]fn actual_native_sys_callbacks_preserve_first_io_quota_then_recover(){for kind in[Kind::Constructor,Kind::Look,Kind::ManualLog,Kind::StringNames]{let budget=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();let stop=||Err(std::io::Error::from_raw_os_error(1450));assert!(matches!(run(kind,&mut NativeAssertions{budget:&budget,poll:&stop},&mut NativeAssertions{budget:&budget,poll:&stop}),Err(Failure::Operational(actual))if actual.raw_os_error()==Some(1450)));let budget=Budget::new(1024).unwrap();assert!(matches!(run(kind,&mut NativeAssertions{budget:&budget,poll:&||Ok(())},&mut NativeAssertions{budget:&budget,poll:&||Ok(())}),Err(Failure::Operational(actual))if actual.kind()==std::io::ErrorKind::OutOfMemory));let budget=Budget::new(crate::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES).unwrap();assert!(run(kind,&mut NativeAssertions{budget:&budget,poll:&||Ok(())},&mut NativeAssertions{budget:&budget,poll:&||Ok(())}).is_ok());}}
}
