//! The original derived fixture assertions, shared by the legacy adapter
//! and the actual native captured-source backend. No frontend exists here.
use std::collections::{BTreeMap,BTreeSet,HashSet};
use crate::{derived_reads_judge::Finding,key_policy_control::{self as kc,Control}};
/// Plain inspected fixture DATA; this never supplies workspace completion.
pub struct Outcome{pub(crate) fixed:BTreeMap<String,String>,pub(crate) generated:String,pub(crate) findings:Vec<Finding>}
#[derive(Debug)]pub enum Failure{Assertion(String),Operational(std::io::Error)}
impl From<std::io::Error> for Failure{fn from(actual:std::io::Error)->Self{Self::Operational(actual)}}
impl Outcome{
 /// Transfer only the actual escaped DATA before its reader grant drops.
 /// Every later assertion copy/detail is explicitly admitted at construction.
 pub fn admit_assertion_retention(&self,budget:&crate::captured_generator_budget::Budget)->std::io::Result<()>{
  let bound=(||{let mut bytes=std::mem::size_of::<Self>().checked_add(self.generated.capacity())?.checked_add(self.findings.capacity().checked_mul(std::mem::size_of::<Finding>())?)?;
   for(key,value)in &self.fixed{bytes=bytes.checked_add(2048)?.checked_add(key.capacity())?.checked_add(value.capacity())?;}
   for row in &self.findings{for text in [&row.rel,&row.owner,&row.proc]{bytes=bytes.checked_add(text.capacity())?;}bytes=bytes.checked_add(row.var.as_ref().map_or(0,String::capacity))?.checked_add(row.kind.as_ref().map_or(0,String::capacity))?;}Some(bytes)
  })().ok_or_else(||{budget.deny();std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native fixture retained assertion storage overflow")})?;
  budget.charge(bound).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))
 }
}
pub struct LegacyAssertions;
impl Control for LegacyAssertions{type Error=Failure;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),Failure>{Ok(())}fn reserve(&mut self,_:usize)->Result<(),Failure>{Ok(())}fn overflow(&mut self)->Failure{unreachable!("compatibility evaluates no new bound")}fn allocation_failed(&mut self)->Failure{unreachable!("compatibility retains original allocation")}}
#[cfg(feature="native-policy")]pub struct NativeAssertions<'a>{pub budget:&'a crate::captured_generator_budget::Budget,pub poll:&'a dyn Fn()->std::io::Result<()>}
#[cfg(feature="native-policy")]impl Control for NativeAssertions<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.budget.require().map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;(self.poll)().map_err(Failure::Operational)}fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.budget.charge(bytes).map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))}fn overflow(&mut self)->Failure{self.budget.deny();Failure::Operational(std::io::ErrorKind::OutOfMemory.into())}fn allocation_failed(&mut self)->Failure{self.overflow()}}
pub trait Backend{fn inspect(&mut self,texts:&[(&str,String)])->Result<Outcome,Failure>;}
fn run_analyze(backend:&mut impl Backend,texts:&[(&str,String)])->Result<(BTreeMap<String,String>,String,Vec<Finding>),Failure>{let Outcome{fixed,generated,findings}=backend.inspect(texts)?;Ok((fixed,generated,findings))}
fn model_of(backend:&mut impl Backend,texts:&[(&str,String)])->Result<((),String),Failure>{Ok(((),backend.inspect(texts)?.generated))}
fn fix_texts<C:Control<Error=Failure>>(_generated:&String,fixed:&BTreeMap<String,String>,_findings:&[Finding],c:&mut C)->Result<BTreeMap<String,String>,Failure>{let mut out=BTreeMap::new();for(key,value)in fixed{c.checkpoint()?;kc::reserve(c,||Some(2048))?;out.insert(kc::own(c,key)?,kc::own(c,value)?);}Ok(out)}
fn generated_text<C:Control<Error=Failure>>(generated:&String,_test_types:&BTreeSet<String>,c:&mut C)->Result<String,Failure>{kc::own(c,generated)}
fn fixed_inputs<'a,C:Control<Error=Failure>>(fixed:&'a BTreeMap<String,String>,c:&mut C)->Result<Vec<(&'a str,String)>,Failure>{let mut out=Vec::new();for(key,value)in fixed{kc::row(c,&mut out)?;out.push((key.as_str(),kc::own(c,value)?));}Ok(out)}
fn projected<C:Control<Error=Failure>>(findings:&[Finding],c:&mut C)->Result<Vec<(&'static str,Option<String>,String)>,Failure>{let mut out=Vec::new();for f in findings{kc::row(c,&mut out)?;out.push((f.rule,f.var.as_deref().map(|value|kc::own(c,value)).transpose()?,kc::own(c,&f.proc)?));}Ok(out)}
fn variables<C:Control<Error=Failure>>(findings:&[Finding],c:&mut C)->Result<Vec<(&'static str,Option<String>)>,Failure>{let mut out=Vec::new();for f in findings{kc::row(c,&mut out)?;out.push((f.rule,f.var.as_deref().map(|value|kc::own(c,value)).transpose()?));}Ok(out)}
fn rule_set<C:Control<Error=Failure>>(findings:&[Finding],c:&mut C)->Result<HashSet<(&'static str,Option<String>)>,Failure>{let mut out=HashSet::new();for f in findings{kc::set_room(c,&mut out)?;out.insert((f.rule,f.var.as_deref().map(|value|kc::own(c,value)).transpose()?));}Ok(out)}
fn ui_variables<C:Control<Error=Failure>>(findings:&[Finding],c:&mut C)->Result<Vec<Option<String>>,Failure>{let mut out=Vec::new();for f in findings.iter().filter(|f|f.rule=="untracked_ui_read"){kc::row(c,&mut out)?;out.push(f.var.as_deref().map(|value|kc::own(c,value)).transpose()?);}Ok(out)}
fn replaced<C:Control<Error=Failure>>(value:&str,from:&str,to:&str,c:&mut C)->Result<String,Failure>{kc::reserve(c,||value.len().checked_add(1)?.checked_mul(to.len().checked_add(1)?)?.checked_add(value.len())?.checked_add(64))?;Ok(value.replace(from,to))}
struct Joined<'a>(&'a[String]);impl std::fmt::Display for Joined<'_>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{for(i,row)in self.0.iter().enumerate(){if i!=0{f.write_str("; ")?}f.write_str(row)?;}Ok(())}}
const FIXTURE_BASE: &str = "
/obj/pointer
»var/energy = 8
»var/max_energy = 8
»var/pointing = FALSE
»var/spare = 0

TRACKED(/obj/pointer, energy)
TRACKED(/obj/pointer, pointing)

/obj/pointer/should_run()
»return energy < max_energy

/obj/pointer/draw(datum/look/look)
»..()
»if(pointing)
»»look.state(\"on\")
";

const FIXTURE_DECLARED_TAIL: &str = "
/obj/pointer/derived()
». = ..()
». += runs_while(nameof(energy), nameof(max_energy))
». += drawn_from(nameof(pointing))
";

const FIXTURE_SUBTYPE_TAIL: &str = "
/obj/pointer/big
»var/glow = FALSE

/obj/pointer/big/draw(datum/look/look)
»..()
»if(pointing && glow)
»»look.state(\"big\")

/obj/pointer/big/derived()
». = ..()
». += drawn_from(nameof(glow))
";

const FIXTURE_MISC: &str = "
/obj/thing
»var/level = 0
»var/extra = 0
»var/total = 0
»var/spare = 0
»var/obj/thing/parent
»var/list/kids

TRACKED(/obj/thing, level)
REL(/obj/thing, parent)

/obj/thing/derived()
». = ..()
». += derive(nameof(total), nameof(level))
». += drawn_from(nameof(total), nameof(spare), rel(nameof(parent), nameof(/obj/thing::level)), rel(nameof(kids), nameof(/obj/thing::mystery)))
». += ui_from(nameof(cap_state))

/obj/thing/derive_total()
»return level + extra

/obj/thing/on_state_changed(bits)
»return

/obj/thing/tgui_data(mob/user)
»var/level = 5
»// ALLOW(derived_reads): fixture keep
». = list(\"level\" = level, \"n\" = total)
». += total
";

fn tabs<C:Control<Error=Failure>>(s:&str,c:&mut C)->Result<String,Failure>{kc::reserve(c,||s.len().checked_add(64))?;Ok(s.replace('\u{00bb}',"\t"))}
fn undeclared(found:&[Finding])->impl Iterator<Item=&Finding>{found.iter().filter(|f|f.rule=="undeclared_read")}
pub fn run<C:Control<Error=Failure>>(backend:&mut impl Backend,control:&mut C) -> Result<String, Failure> {
    let mut bad: Vec<String> = Vec::new();
    macro_rules! admitted_format{($c:expr,$($args:tt)*)=>{kc::format($c,format_args!($($args)*))?}}
    macro_rules! check{($c:expr,$name:expr,$ok:expr,$detail:expr $(,)?)=>{{let ok=$ok;let detail=$detail;if !ok{kc::row($c,&mut bad)?;bad.push(kc::format($c,format_args!("{} {}",$name,detail))?);}}}}
    let base = tabs(FIXTURE_BASE,control)?;
    let tail=tabs(FIXTURE_DECLARED_TAIL,control)?;let declared=kc::format(control,format_args!("{}{}",base,tail))?;
    let tail=tabs(FIXTURE_SUBTYPE_TAIL,control)?;let subtype=kc::format(control,format_args!("{}{}",declared,tail))?;
    // 1
    let (_, _, found) = run_analyze(backend,&[("code/a.dm", kc::own(control,&base)?)])?;
    let got: Vec<_> = projected(&found,control)?;
    check!(control,
        "missing declaration",
        got.iter().any(|(rule,var,proc)|*rule=="undeclared_read"&&var.as_deref()==Some("energy")&&proc=="should_run") && got.iter().any(|(rule,var,proc)|*rule=="undeclared_read"&&var.as_deref()==Some("pointing")&&proc=="draw"),
        admitted_format!(control,"{:?}", got),
    );
    check!(control,
        "only the read vars",
        found.iter().all(|f| matches!(f.var.as_deref(), Some("energy" | "pointing" | "max_energy"))),
        admitted_format!(control,"{:?}", got),
    );
    // 2
    let (_, _, found) = run_analyze(backend,&[("code/a.dm", kc::own(control,&declared)?)])?;
    check!(control,"declared is clean", undeclared(&found).next().is_none(), admitted_format!(control,"{:?}", found));
    let (_, _, found) = run_analyze(backend,&[("code/a.dm", kc::own(control,&subtype)?)])?;
    check!(control,"inherited declarations", undeclared(&found).next().is_none(), admitted_format!(control,"{:?}", found));
    // 3
    let text = replaced(&subtype,"\t. += drawn_from(nameof(glow))\n","",control)?;
    let (tree, model, found) = run_analyze(backend,&[("code/a.dm", kc::own(control,&text)?)])?;
    let got: Vec<_> = variables(&found,control)?;
    check!(control,"subtype missing", got.iter().any(|(rule,var)|*rule=="undeclared_read"&&var.as_deref()==Some("glow")), admitted_format!(control,"{:?}", got));
    // 4
    let fixed = fix_texts(&model,&tree,&found,control)?;
    check!(control,"fix edits the derived block", fixed.get("code/a.dm").map(|t| t.contains("drawn_from(nameof(glow))")).unwrap_or(false), admitted_format!(control,"{:?}", fixed));
    let fixed_in: Vec<(&str, String)> = fixed_inputs(&fixed,control)?;
    let (t2, m2, again) = run_analyze(backend,&fixed_in)?;
    check!(control,"fixed text is clean", !fixed.is_empty() && undeclared(&again).next().is_none(), admitted_format!(control,"{:?}", again));
    check!(control,"fix is stable", fix_texts(&m2,&t2,&again,control)?.is_empty(), String::new());
    // 5
    let (tree, model, found) = run_analyze(backend,&[("code/a.dm", kc::own(control,&base)?)])?;
    let fixed = fix_texts(&model,&tree,&found,control)?;
    check!(control,"fix creates the block", fixed.get("code/a.dm").map(|t| t.contains("/obj/pointer/derived()")).unwrap_or(false), admitted_format!(control,"{:?}", fixed));
    let fixed_in: Vec<(&str, String)> = fixed_inputs(&fixed,control)?;
    let (_, _, again) = run_analyze(backend,&fixed_in)?;
    check!(control,"created block is clean", undeclared(&again).next().is_none(), admitted_format!(control,"{:?}", again));
    // 6
    let (_, _, found) = run_analyze(backend,&[("code/b.dm", tabs(FIXTURE_MISC,control)?)])?;
    let rules: HashSet<(&str, Option<String>)> = rule_set(&found,control)?;
    let has = |r: &str, v: Option<&str>| rules.iter().any(|(rr, vv)| *rr == r && vv.as_deref() == v);
    check!(control,"hop through a plain var", has("hop_not_relation", Some("kids")), admitted_format!(control,"{:?}", rules));
    check!(control,"relation hop is fine", !has("hop_not_relation", Some("parent")), admitted_format!(control,"{:?}", rules));
    check!(control,"untracked declared var", has("declared_untracked", Some("spare")), admitted_format!(control,"{:?}", rules));
    check!(control,"untracked remote var", has("declared_untracked", Some("/obj/thing::mystery")), admitted_format!(control,"{:?}", rules));
    check!(control,
        "tracked, derived and exempt reads are fine",
        !has("declared_untracked", Some("total")) && !has("declared_untracked", Some("cap_state")) && !has("declared_untracked", Some("level")),
        admitted_format!(control,"{:?}", rules),
    );
    check!(control,"exact type overriding on_state_changed", has("exact_on_state_changed", None), admitted_format!(control,"{:?}", rules));
    check!(control,
        "derive body read past its reads",
        has("undeclared_read", Some("extra")) && found.iter().any(|f| f.rule == "undeclared_read" && f.proc == "derive_total"),
        admitted_format!(control,"{:?}", rules),
    );
    // 7
    check!(control,"locals and ALLOW", !found.iter().any(|f| f.rule == "undeclared_read" && f.proc == "tgui_data"), admitted_format!(control,"{:?}", found));
    // 8
    let (_, _, found) = run_analyze(backend,&[("code/a.dm", kc::own(control,&base)?)])?;
    check!(control,"legacy type reports", found.iter().any(|f| f.rule == "undeclared_read"), String::new());
    // 9
    let (_, model) = model_of(backend,&[("code/a.dm", kc::own(control,&declared)?)])?;
    let text = generated_text(&model,&BTreeSet::new(),control)?;
    check!(control,
        "generated reads",
        text.contains("/obj/pointer/generated_reads()")
            && text.contains("runs_while(nameof(energy), nameof(max_energy))")
            && text.contains("drawn_from(nameof(pointing))"),
        kc::own(control,&text)?,
    );
    let (_, model2) = model_of(backend,&[("code/a.dm", kc::own(control,&declared)?)])?;
    check!(control,"generated is stable", generated_text(&model2,&BTreeSet::new(),control)? == text, String::new());
    // 10: a draw reads what the procs it calls read, transitively; a subtype's override is a read of the subtype; recursion ends
    let helper_fixture = tabs("
/obj/lamp
	var/lit = FALSE
	var/spare = 0
/obj/lamp/draw(datum/look/look)
	..()
	draw_state(look)
/obj/lamp/proc/draw_state(datum/look/look)
	look.state(state_name())
	draw_state(look)
/obj/lamp/proc/state_name()
	return lit ? \"on\" : \"off\"
/obj/lamp/big
	var/extra = 0
/obj/lamp/big/state_name()
	return extra ? \"x\" : \"y\"
",control)?;
    let (_, hmodel) = model_of(backend,&[("code/h.dm", helper_fixture)])?;
    let htext = generated_text(&hmodel,&BTreeSet::new(),control)?;
    let lamp = htext.split("/obj/lamp/big/generated_reads()").next().unwrap_or("");
    let big = htext.split("/obj/lamp/big/generated_reads()").nth(1).unwrap_or("");
    check!(control,
        "a draw follows the procs it calls",
        lamp.contains("drawn_from(nameof(lit))") && !htext.contains("nameof(spare)"),
        kc::own(control,&htext)?,
    );
    check!(control,"an override on a subtype is that subtype's read", big.contains("drawn_from(nameof(extra))"), kc::own(control,&htext)?);
    // 11: a window host's ui_data() reads must be tracked
    let ui_fixture = tabs("
/obj/panel
»var/screen = 1
»var/label = \"x\"
»var/obj/thing/target
»var/note = \"\"

TRACKED(/obj/panel, screen)
REL(/obj/panel, target)

/obj/panel/ui_data(datum/act/eval/A)
»var/note = 3
»return list(\"screen\" = screen, \"label\" = label, \"t\" = target, \"n\" = note)
",control)?;
    let (_, _, found) = run_analyze(backend,&[("code/a.dm", ui_fixture)])?;
    let ui_got: Vec<_> = ui_variables(&found,control)?;
    check!(control,"ui_data untracked read is flagged", ui_got.len()==1&&ui_got[0].as_deref()==Some("label"), admitted_format!(control,"{:?}", ui_got));
    // 10
    let fixture = kc::own(control,"/obj/pump/reactions()\n\t. = ..()\n\t. += every(1 SECONDS, PROC_REF(step), members = /datum/capability/pumped)\n\t. += on_notice(/datum/notice/x, PROC_REF(h))\n")?;
    let (_, model) = model_of(backend,&[("code/a.dm", fixture)])?;
    let boot = generated_text(&model,&BTreeSet::new(),control)?;
    check!(control,"boot types", boot.contains("/obj/pump = RXB_EVERY | RXB_NOTICE,") && boot.contains("/datum/capability/pumped,"), boot);
    if bad.is_empty() {
        Ok(kc::own(control,"derived_reads_lint selftest passed")?)
    } else {
        Err(Failure::Assertion(kc::format(control,format_args!("{}",Joined(&bad)))?))
    }
}

#[cfg(test)]mod source_marker_controls{
 #[test]fn shared_derived_fixture_markers_remain_real_unicode_indentation_not_replacement_bytes(){let mut work=super::LegacyAssertions;let converted=super::tabs("\u{00bb}return\n\u{00bb}\u{00bb}return\n",&mut work).unwrap();assert_eq!(converted,"\treturn\n\t\treturn\n");let base=super::tabs(super::FIXTURE_BASE,&mut work).unwrap();assert!(!base.contains('\u{00bb}'));assert!(base.contains("\treturn energy < max_energy"));}
}


#[cfg(test)]mod operational_conversion_controls{
 use super::*;
 #[test]fn derived_failure_io_conversion_preserves_actual_raw_os_error_and_cancellation(){
  let Failure::Operational(actual)=Failure::from(std::io::Error::from_raw_os_error(1450))else{panic!("IO cannot become an assertion")};assert_eq!(actual.raw_os_error(),Some(1450));
  let Failure::Operational(actual)=Failure::from(std::io::Error::new(std::io::ErrorKind::Interrupted,"actual cancellation"))else{panic!("cancellation cannot become an assertion")};assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);assert_eq!(actual.to_string(),"actual cancellation");
 }
}
