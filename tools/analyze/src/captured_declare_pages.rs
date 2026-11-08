//! Source-neutral Declare output from exhausted callback-local original loans.
//! Only the host may attach current workspace and domain completion witnesses.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,reactive_raw_policy_pages::RawPolicyPages,sparse_slots_policy::Output};
use std::{collections::{BTreeSet,HashMap},io,path::Path,sync::Arc};
use crate::key_policy_control::Control as _;
fn oom(budget:&Budget,message:impl Into<String>)->Failure{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
struct Scratch{budget:Arc<Budget>,complete:bool}
impl Drop for Scratch{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
struct Control<'a>{budget:&'a Arc<Budget>,poll:&'a dyn Fn()->io::Result<()>}
impl crate::key_policy_control::Control for Control<'_>{
 type Error=Failure;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Failure>{self.budget.require().map_err(|message|oom(self.budget,message))?;(self.poll)()?;self.budget.require().map_err(|message|oom(self.budget,message))}
 fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.budget.charge(bytes).map_err(|message|oom(self.budget,message))}
 fn overflow(&mut self)->Failure{oom(self.budget,"Declare policy allocation overflow")}
 fn allocation_failed(&mut self)->Failure{oom(self.budget,"Declare policy allocation refused")}
}
fn finish<T>(result:Result<T,Failure>,control:&mut Control<'_>)->Result<T,Failure>{
 if matches!(&result,Err(Failure::Operational(_))){return result}
 control.checkpoint()?;result
}
/// No raw text or per-file semantic object escapes. The constructor summary
/// consists only of exact original /proc/ spellings and moves into the generator.
/// Caller owns the as-of source/domain proof, not this source-neutral result.
pub fn generate_from_pages(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Output,Failure>{
 collect(pages,order,root,poll,Relations::Unavailable).map(|(output, _)| output)
}

/// The resident full workspace lends the same current original declaration
/// archive as its CODE pages. No independent acquisition or body is requested.
pub fn generate_from_typed_pages(
    inputs: &dm_analysis::policy_inputs::PolicyInputs,
    workspace_root: &Path,
    pages: &dyn RawPolicyPages,
    order: &HashMap<String, usize>,
    root: &Arc<Budget>,
    poll: &dyn Fn() -> io::Result<()>,
) -> Result<Output, Failure> {
    collect(pages, order, root, poll, Relations::Typed { inputs, workspace_root })
        .map(|(output, _)| output)
}

/// One exactly funded named file during a closed probe. The String always
/// dies before its root Budget reservation, including an early failure.
struct CapturedNamedFile<'a> {
    text: String,
    _window: crate::captured_generator_budget::ReservedWindow,
    // Drop the allocation before refunding either admission domain.
    _parent: Option<dm_syntax::ProvisionalNativeGrant<'a>>,
}
impl CapturedNamedFile<'_> {
    fn as_str(&self) -> &str { &self.text }
}
/// One admission and one allocation for the exact current named bytes.
/// Both passes use the existing renderer. The returned owner cannot
/// refund the backing while a caller still borrows the staged text.
fn capture_exact_named_file<'a>(
    output: &Output,
    name: &str,
    filename: &str,
    budget: &Arc<Budget>,
    parent: Option<&'a dm_syntax::SharedNativeReservation>,
) -> io::Result<CapturedNamedFile<'a>> {
    use std::{alloc::Layout, fmt, ptr::NonNull};
    struct Count(usize);
    impl fmt::Write for Count {
        fn write_str(&mut self, text: &str) -> fmt::Result {
            self.0 = self.0.checked_add(text.len()).ok_or(fmt::Error)?;
            Ok(())
        }
    }
    struct Fixed(String);
    impl fmt::Write for Fixed {
        fn write_str(&mut self, text: &str) -> fmt::Result {
            if text.len() > self.0.capacity() - self.0.len() { return Err(fmt::Error); }
            self.0.push_str(text);
            Ok(())
        }
    }
    let denied = || io::Error::from(io::ErrorKind::OutOfMemory);
    let mut width = Count(0);
    output.write_named_file_text(name, filename, &mut width).map_err(|_| denied())?;
    let layout = Layout::array::<u8>(width.0).map_err(|_| denied())?;
    // The common renderer always emits its preamble.
    if layout.size() == 0 { return Err(io::ErrorKind::InvalidData.into()); }
    let window = crate::captured_generator_budget::Budget::reserve_window(budget, layout.size())
        .map_err(|message| io::Error::new(io::ErrorKind::OutOfMemory, message))?;
    if window.capacity() != layout.size() { return Err(denied()); }
    let parent_grant = parent.map(|parent| parent.provisional(layout.size())).transpose()
        .map_err(|message| io::Error::new(io::ErrorKind::OutOfMemory, message))?;
    // SAFETY: admitted nonzero Layout for an ordinary Global Vec<u8>.
    // The unique Vec starts empty, and every following byte is UTF-8.
    let data = NonNull::new(unsafe { std::alloc::alloc(layout) }).ok_or_else(denied)?;
    let bytes = unsafe { Vec::from_raw_parts(data.as_ptr(), 0, layout.size()) };
    let mut out = Fixed(String::from_utf8(bytes).expect("empty UTF8 backing"));
    output.write_named_file_text(name, filename, &mut out).map_err(|_| io::ErrorKind::InvalidData)?;
    if out.0.len() != layout.size() { return Err(io::ErrorKind::InvalidData.into()); }
    Ok(CapturedNamedFile { text: out.0, _window: window, _parent: parent_grant })
}

/// Generator-owned bytes and insertion boundary. There is deliberately no
/// conversion to a named output artifact until both typed probes agree.
pub struct DeclareTemplate {
    empty: Output,
    slot: crate::declare_policy::RelationTypeSlot,
}
impl DeclareTemplate {
    pub fn prove(
        self,
        root: &Arc<Budget>,
        parent: Option<&dm_syntax::SharedNativeReservation>,
        poll: &dyn Fn() -> io::Result<()>,
        mut probe: impl FnMut(&str, &[crate::declare_policy::RelationTypeCandidate]) -> Result<Vec<Option<String>>, Failure>,
    ) -> Result<Output, Failure> {
        let Self { empty, slot } = self;
        let file = |output: &Output| {
            capture_exact_named_file(output, "declare", "declare.dm", root, parent)
                .map_err(Failure::Operational)
        };
        let mut control = Control { budget: root, poll };
        control.checkpoint()?;
        let draft = file(&empty)?;
        let first = probe(draft.as_str(), &slot.candidates)?;
        control.checkpoint()?;
        if first.len() != slot.candidates.len() {
            return Err("Declare staged typed answer roster differs".into());
        }
        drop(draft);
        // If no rows are emitted, fill returns exactly the bytes already
        // probed. Otherwise retire the draft before probing complete bytes.
        let changed = first.iter().flatten().any(|ty| crate::declare_policy::relation_type_is_emitted(ty));
        let complete = slot.fill(&mut control, empty, &first, root)?;
        if changed {
            let final_text = file(&complete)?;
            let final_answers = probe(final_text.as_str(), &slot.candidates)?;
            control.checkpoint()?;
            if first != final_answers {
                return Err("Declare staged relation types do not reproduce against the completed output".into());
            }
        }
        control.checkpoint()?;
        Ok(complete)
    }
}
pub use crate::declare_policy::RelationTypeCandidate;

/// Type-only projection over the existing restricted Original-dialect
/// declaration question owner. It does not ask for a source or body.
pub fn probe_relation_types(
    questions: &dm_tree::frontend::GenerationDeclareTypeQuestions,
    candidates: &[RelationTypeCandidate],
    budget: &Arc<Budget>,
    poll: &dyn Fn() -> io::Result<()>,
) -> Result<Vec<Option<String>>, Failure> {
    use crate::key_policy_control as kc;
    let mut control = Control { budget, poll };
    let tree = questions.tree();
    let profile = tree.checker_builtin_profile().ok_or("Declare overlay original profile absent")?;
    let proof = tree.validated_checker_profile(profile)
        .map_err(|error| Failure::Unsupported(format!("Declare overlay original profile: {error:?}")))?;
    let mut answers = Vec::new();
    for candidate in candidates {
        control.checkpoint()?;
        kc::row(&mut control, &mut answers)?;
        if !tree.checker_source_type_presence_validated(profile, &candidate.owner, &proof)
            .map_err(|error| Failure::Unsupported(format!("Declare overlay owner: {error:?}")))?
        {
            answers.push(None);
            continue;
        }
        let fact = dm_analysis::checker_variable_facts::variable_original_validated(
            tree, &proof, profile,
            dm_ir::SymbolId::of(&candidate.owner), dm_ir::SymbolId::of(&candidate.var),
        )?;
        let Some(fact) = fact else { answers.push(None); continue };
        let answer = if let Some(formal) = fact.formal {
            let width = [fact.metadata.declared_type(), fact.metadata.list_element_type(),
                fact.metadata.array.as_ref().and_then(|array| array.element_type)]
                .into_iter().flatten().try_fold(0usize, |n, id| n.checked_add(tree.symbols().text(id)?.len()));
            kc::reserve(&mut control, || width?.checked_mul(64)?.checked_add(4096))?;
            let ordinal = questions.member_first_original_occurrence(formal)?
                .ok_or("Declare overlay authored formal occurrence unavailable")?;
            let property = questions.variable_properties_original_at(formal, ordinal, profile, &proof)?;
            Some(kc::own(&mut control, property.declared_hint().unwrap_or(""))?)
        } else {
            let declared = fact.metadata.declared_type().and_then(|id| tree.symbols().text(id)).unwrap_or("");
            let element = fact.metadata.list_element_type().and_then(|id| tree.symbols().text(id));
            Some(match element {
                Some(element) if declared == "/list" => kc::format(&mut control, format_args!("/list{element}"))?,
                Some(_) => return Err("Declare overlay builtin list-element owner inconsistent".into()),
                None => kc::own(&mut control, declared)?,
            })
        };
        answers.push(answer);
    }
    control.checkpoint()?;
    Ok(answers)
}

/// Same marker and constructor traversal as the source-only path, selected
/// only by an explicit private bootstrap caller.
pub fn collect_template(
    pages: &dyn RawPolicyPages,
    order: &HashMap<String, usize>,
    root: &Arc<Budget>,
    poll: &dyn Fn() -> io::Result<()>,
) -> Result<DeclareTemplate, Failure> {
    let (empty, slot) = collect(pages, order, root, poll, Relations::Template)?;
    Ok(DeclareTemplate { empty, slot: slot.expect("stage emits a relation slot") })
}
enum Relations<'a> {
    Unavailable,
    Typed { inputs: &'a dm_analysis::policy_inputs::PolicyInputs, workspace_root: &'a Path },
    Template,
}
fn collect(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,relations:Relations<'_>)->Result<(Output,Option<crate::declare_policy::RelationTypeSlot>),Failure>{
 use crate::key_policy_control::{self as kc,Control as _};
 let mut entry=Control{budget:root,poll};entry.checkpoint()?;
 let mut scratch=Scratch{budget:Budget::scoped_temporaries(root).map_err(|message|oom(root,message))?,complete:false};
 let mut control=Control{budget:&scratch.budget,poll};
 let produced=(||{
  let rows=crate::reactive_raw_policy_pages::collect_marker_rows(|visit|pages.for_each(visit),order,&scratch.budget,crate::declare_policy::MARKERS,false,false,false,&mut||{scratch.budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;poll()?;scratch.budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))},&||scratch.budget.require().map_err(|message|oom(&scratch.budget,message)))?;
  let mut constructors=BTreeSet::new();
  let complete=pages.for_each(&mut|relative,views|{
   control.checkpoint()?;
   if relative.starts_with("code/engine/"){
    crate::declare_policy::visit_engine_constructors(&mut control,relative,views.raw()?,&mut|control,name|{
     if !constructors.contains(name){kc::reserve(control,||2048usize.checked_add(std::mem::size_of::<String>().checked_mul(16)?))?;constructors.insert(kc::own(control,name)?);}
     Ok(())
    })?;
   }
   control.checkpoint()?;Ok(true)
  })?;
  if !complete{return Err(Failure::Unsupported("Declare constructor traversal did not complete".into()))}
  let mut markers = Vec::new();
  let mut part_features = Vec::new();
  for row in &rows.markers {
   kc::row(&mut control, &mut markers)?;
   kc::row(&mut control, &mut part_features)?;
   markers.push(crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts});
   part_features.push(row.part.as_deref());
  }
  let input=crate::declare_policy::Input{markers:&markers,part_features:&part_features,engine_sources:&[],poll:None,budget:Some(Arc::clone(&scratch.budget))};
  let (mut generated, slot) = match relations {
   Relations::Template => {
    let (generated, slot) = crate::declare_policy::generate_relation_type_template(&input, &mut control, constructors)?;
    (generated, Some(slot))
   }
   Relations::Typed { inputs, workspace_root } => {
    let source = crate::reactive_original_source::ReadSource::native(inputs, workspace_root, &scratch.budget)?;
    let output = crate::declare_policy::generate_with_relation_types(&input, &mut control, Some(constructors),
        &mut |owner, var| source.variable_type(owner, var).map_err(Failure::from))?;
    (output, None)
   }
   Relations::Unavailable => {
    crate::declare_policy::visit_rel_var_type_candidates(&mut control, &input, |_, _, _| {
     Err(Failure::Unsupported(crate::declare_policy::REL_VAR_TYPES_UNAVAILABLE.into()))
    })?;
    (crate::declare_policy::generate_with_constructors(&input, &mut control, Some(constructors))?, None)
   }
  };
  control.checkpoint()?;
  let mut output=Output::default();output.body=std::mem::take(&mut generated.body);output.diags=std::mem::take(&mut generated.diags);drop(generated);
  Ok((output, slot))
 })();
 let produced=finish(produced,&mut control);drop(control);
 let funded=match produced{
  Ok((output, slot))=>{
   let bytes=output.diags.capacity().checked_mul(std::mem::size_of::<crate::sparse_slots_policy::Diagnostic>()).and_then(|n|n.checked_add(output.body.capacity())).and_then(|n|n.checked_add(std::mem::size_of::<Output>())).and_then(|n|output.diags.iter().try_fold(n,|n,row|n.checked_add(row.rel.capacity())?.checked_add(row.msg.capacity())));
   let bytes=bytes.and_then(|n| if let Some(slot) = &slot { n.checked_add(slot.retained_bytes()?) } else { Some(n) });
   match bytes.ok_or_else(||oom(root,"Declare output capacity overflow")).and_then(|bytes|root.charge(bytes).map_err(|message|oom(root,message))){Ok(())=>Ok((output, slot)),Err(actual)=>{drop((output, slot));Err(actual)}}
  },Err(actual)=>Err(actual)
 };
 scratch.complete=funded.is_ok();drop(scratch);
 finish(funded,&mut entry)
}

#[cfg(test)]#[path="support/declare_before_ids.rs"]mod declare_before_ids;
#[cfg(test)]#[path="support/declare_before_policy.rs"]mod declare_before_policy;
#[cfg(test)]mod tests{
 use super::*;use crate::{captured_raw_file::{File,RawPolicyViews},key_policy_control::Control as _};use std::cell::Cell;
 struct Pages{files:Vec<File>,fail:Cell<bool>,stop:Cell<bool>}
 impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{for file in &self.files{if !file.with_policy_views(visit)?{return Ok(false)}}if self.fail.get(){return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}Ok(!self.stop.get())}}
 fn fixture()->Pages{
  let root=std::env::current_dir().unwrap().join("declare-growth-data");
  let sources=[("code/a.dm",r#"CAPABILITY_TYPE(cover, CAP_COVER, /datum/cover, key = material, prefix = cover, material = null)
CAPABILITY_DEF(light, CAP_LIGHT, radius = 3)
cap_keys(CAP_COVER, OPEN = TRUE, COUNT = 2)
STAGE_DEF(build, ready)
SOURCE_DEF(wall)
STATE_GRAPH(BUILD, stage(ready), source(wall))
STATIC_ENTRY(loot)
CAPABILITIES(/datum/device)
    section(first, "The controls")
    cover(material = "steel")
    ref_one(nameof(target), /datum, weak = TRUE, target_key = id)
    param(nameof(rate))
    factors(scale = 1)
    loot(table = list(/obj/a = 2))
    section(duplicate)
    section(duplicate)
    unknown(4)
CAPABILITIES(/obj/device)
    section(empty)
    bad_assignment = 2
"#),("code/tests/test.dm","CAPABILITIES(/datum/unit_test/probe)\n    cover()\n"),("code/engine/source.dm","/proc/factors(scale)\n/proc/covering(value)\n    return value\n")];
  Pages{files:sources.into_iter().map(|(relative,text)|File::capture(&root,&root.join(relative),text.to_owned().into()).unwrap()).collect(),fail:Cell::new(false),stop:Cell::new(false)}
 }
 #[test]
 fn staged_declare_insertion_checks_reprobe_and_preserves_candidate_order() {
  let root = std::env::current_dir().unwrap().join("native-declare-template");
  let source = "CAPABILITIES(/datum/probe)\n    ref_one(nameof(zeta), weak = TRUE)\n    owns_one(nameof(alpha))\n    ref_one(nameof(zeta))\n    ref_one(nameof(listed))\n";
  let pages = Pages {
   files: vec![File::capture(&root, &root.join("code/probe.dm"), source.to_owned().into()).unwrap()],
   fail: Cell::new(false), stop: Cell::new(false),
  };
  let budget = Budget::new(32 * 1024 * 1024).unwrap();
  let template = collect_template(&pages, &HashMap::new(), &budget, &|| Ok(())).unwrap();
  let mut passes = 0;
  let parent = dm_syntax::SharedNativeReservation::try_new(32 * 1024 * 1024).unwrap();
  let baseline = parent.reserved_bytes();
  let output = template.prove(&budget, Some(&parent), &|| Ok(()), |text, roster| {
   assert_eq!(parent.reserved_bytes(), baseline + text.len());
   let requested: Vec<_> = roster.iter().map(|row| (row.owner.as_str(), row.var.as_str())).collect();
   assert_eq!(requested, [
    ("/datum/probe", "zeta"), ("/datum/probe", "alpha"), ("/datum/probe", "listed"),
   ]);
   assert!(text.contains("// GENERATED by tools/analyze: \u{60}analyze gen declare\u{60}."));
   assert!(text.contains("/proc/declared_rel_var_types()\n\t. = list()\n"));
   let alpha = text.find("\t.[\"/datum/probe|alpha\"] = /obj\n");
   let zeta = text.find("\t.[\"/datum/probe|zeta\"] = /datum\n");
   if passes == 0 {
    assert!(alpha.is_none() && zeta.is_none());
   } else {
    assert!(alpha.unwrap() < zeta.unwrap());
   }
   assert!(!text.contains("\t.[\"/datum/probe|listed\"]"));
   passes += 1;
   Ok(vec![Some("/datum".into()), Some("/obj".into()), Some("/list/obj".into())])
  }).unwrap();
  assert_eq!(passes, 2);
  assert!(output.body.contains("\t.[\"/datum/probe|zeta\"] = /datum\n"));

  let denied = Budget::new(32 * 1024 * 1024).unwrap();
  let template = collect_template(&pages, &HashMap::new(), &denied, &|| Ok(())).unwrap();
  let mut passes = 0;
  let failure = template.prove(&denied, None, &|| Ok(()), |_, _| {
   passes += 1;
   Ok(vec![Some(if passes == 1 { "/datum" } else { "/obj" }.into()), None, None])
  }).err().unwrap();
  assert!(matches!(failure, Failure::Unsupported(message) if message.contains("do not reproduce")));
  assert_eq!(passes, 2);

  let empty = Budget::new(32 * 1024 * 1024).unwrap();
  let template = collect_template(&pages, &HashMap::new(), &empty, &|| Ok(())).unwrap();
  let mut passes = 0;
  let output = template.prove(&empty, None, &|| Ok(()), |_, roster| {
   passes += 1;
   Ok(vec![None; roster.len()])
  }).unwrap();
  assert_eq!(passes, 1);
  assert!(output.body.contains("/proc/declared_rel_var_types()\n\t. = list()\n#endif\n"));
 }
 #[test]fn declare_growth_policy_matches_complete_preport_output_and_ordered_diagnostics(){
  let pages=fixture();let order=HashMap::from([("code/tests/test.dm".to_owned(),0),("code/a.dm".to_owned(),1)]);let root=Budget::new(32*1024*1024).unwrap();let output=generate_from_pages(&pages,&order,&root,&||Ok(())).unwrap();
  let oldbudget=Budget::new(32*1024*1024).unwrap();let rows=crate::reactive_raw_policy_pages::collect_marker_rows(|visit|pages.for_each(visit),&order,&oldbudget,crate::declare_policy::MARKERS,false,false,false,&mut||Ok(()),&||Ok(() )).unwrap();
  let markers:Vec<_>=rows.markers.iter().map(|row|declare_before_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts}).collect();
  let engines=vec![("code/engine/source.dm","/proc/factors(scale)\n/proc/covering(value)\n    return value\n")];
  let old=declare_before_policy::generate(&declare_before_policy::Input{markers:&markers,engine_sources:&engines,poll:None,budget:None},||Ok(())).unwrap();
  assert_eq!(output.body,old.body);assert_eq!(output.diags,old.diags);assert!(!output.diags.is_empty());assert!(output.body.contains("global.factors"));assert!(output.body.contains("weak_get"));assert!(output.body.contains("#if defined(UNIT_TESTS)"));
 }
 #[cfg(feature = "legacy-sem")]
 #[test]
 fn native_declare_part_composition_matches_current_master() {
  use crate::{sem::gen::{self, GenCx}, tree::{SourceFile, Tree}};
  let root = std::env::current_dir().unwrap().join("native-part-composition-oracle");
  let sources = [
   ("code/m.dm", "STATIC_ENTRY(loot)\nCAPABILITIES(/datum/probe)\n    wall(1)\n    loot(table = list(1))\nCAPABILITIES(/datum/cross)\n    loot(table = list(5))\n"),
   ("code/a.dm", "CAPABILITIES_PART(/datum/probe, zed)\n    section(part_section, \"part doc\")\n    wall(4)\n    loot(table = list(4))\nCAPABILITIES_PART(/datum/probe, \"invalid\")\n    wall(8)\n"),
   ("code/z.dm", "CAPABILITIES_PART(/datum/probe, alpha)\n    setup(PROC_REF(run))\n    wall(2)\n    loot(table = list(2))\n"),
   ("code/zz.dm", "CAPABILITIES_PART(/datum/probe, alpha)\n    wall(9)\nCAPABILITIES(/datum/probe)\n    wall(10)\nCAPABILITIES_PART(/datum/orphan, orphan)\n    wall(11)\nCAPABILITIES(/datum/second)\n    wall(12)\nCAPABILITIES_PART(/datum/second, alpha)\n    wall(13)\n"),
   ("code/tests/part.dm", "CAPABILITIES_PART(/datum/cross, cross_test)\n    wall(14)\n    loot(table = list(14))\nCAPABILITIES(/datum/test_probe)\n    wall(15)\nCAPABILITIES_PART(/datum/test_probe, test_part)\n    wall(16)\n"),
  ];
  let tree = Tree::from_files(sources.iter().map(|(rel, text)| SourceFile::from_text(rel, text)).collect());
  let cx = GenCx::new(&tree, &root);
  let master = gen::registry().into_iter().find(|g| g.name() == "declare").unwrap();
  let (master, master_diags) = gen::render(&*master, &cx);
  let pages = Pages {
   files: sources.iter().rev().map(|(rel, text)| File::capture(&root, &root.join(rel), (*text).to_owned().into()).unwrap()).collect(),
   fail: Cell::new(false), stop: Cell::new(false),
  };
  let out = generate_from_pages(&pages, &HashMap::from([("code/z.dm".to_owned(), 0)]), &Budget::new(32 * 1024 * 1024).unwrap(), &|| Ok(())).unwrap();
  fn between<'a>(text: &'a str, begin: &str, end: &str) -> &'a str {
   let (_, tail) = text.split_once(begin).unwrap();
   tail.split_once(end).unwrap().0.trim_end()
  }
  // The wider generator still has independent master relation/lazy-state
  // deltas. Compare the complete affected sections and ordered diagnostics.
  let static_start = "/// declared_static_blocks():";
  let dynamic_end = "#endif";
  let dynamic_start = "/// CAPABILITIES(/datum/cross)";
  let static_end = "/// make(type,";
  assert_eq!(between(&out.body, dynamic_start, dynamic_end), between(&master, dynamic_start, dynamic_end));
  assert_eq!(between(&out.body, static_start, static_end), between(&master, static_start, static_end));
  let actual: Vec<_> = out.diags.iter().map(|d| (d.rel.as_str(), d.line, d.msg.as_str())).collect();
  let expected: Vec<_> = master_diags.iter().map(|d| (d.rel.as_str(), d.line, d.msg.as_str())).collect();
  assert_eq!(actual, expected);
  assert_eq!(actual.len(), 6);
  assert_eq!(out.body.matches("/datum/probe/declared_entries(").count(), 1);
  assert!(out.body.contains("entry_line(3, \"part_section\", \"code/a.dm\")"));
  assert!(out.body.contains("entry_line(3, null, \"code/tests/part.dm\")"), "static composition sees both source halves");
  assert!(!out.body.contains("list(wall(14))"), "test part without a test-half root is rejected dynamically");
 }

 #[cfg(feature = "legacy-sem")]
 #[test]
 fn native_declare_lazy_accessors_match_current_master() {
  use crate::{sem::gen::{self, GenCx}, tree::{SourceFile, Tree}};
  let root = std::env::current_dir().unwrap().join("native-lazy-accessors-oracle");
  let sources = [
   ("code/a.dm", "CAPABILITIES(/obj/a)\n    lazy_state(table_example, /datum/table_example_state)\n    owns_one(nameof(storage), /datum/storage_state, lazy = TRUE)\n"),
   ("code/b.dm", "CAPABILITIES(/obj/b)\n    lazy_state(table_example, /datum/table_example_state)\n    owns_one(nameof(storage), /datum/storage_state, lazy = TRUE)\n    owns_one(nameof(bad), /datum/wrong_state, lazy = TRUE)\n"),
   ("code/part.dm", "CAPABILITIES_PART(/obj/a, extra)\n    lazy_state(extra, /datum/extra_state)\n    owns_one(nameof(storage), /datum/storage_state, lazy = TRUE)\n    owns_one(nameof(missing), missing_type, lazy = TRUE)\n    lazy_state(wrong, /datum/wrong_type)\n"),
   ("code/tests/test.dm", "CAPABILITIES(/datum/test_probe)\n    lazy_state(test_slot, /datum/test_slot_state)\n    lazy_state(table_example, /datum/table_example_state)\n    owns_one(nameof(test_var), /datum/test_var_state, lazy = TRUE)\n    owns_one(nameof(storage), /datum/storage_state, lazy = TRUE)\n"),
  ];
  let tree = Tree::from_files(sources.iter().map(|(rel, text)| SourceFile::from_text(rel, text)).collect());
  let cx = GenCx::new(&tree, &root);
  let master = gen::registry().into_iter().find(|g| g.name() == "declare").unwrap();
  let (master, master_diags) = gen::render(&*master, &cx);
  let pages = Pages {
   files: sources.iter().rev().map(|(rel, text)| File::capture(&root, &root.join(rel), (*text).to_owned().into()).unwrap()).collect(),
   fail: Cell::new(false), stop: Cell::new(false),
  };
  let out = generate_from_pages(&pages, &HashMap::new(), &Budget::new(32 * 1024 * 1024).unwrap(), &|| Ok(())).unwrap();
  fn lazy_body(text: &str) -> &str {
   text.split_once("/// Every lazy state declaration:").unwrap().1
       .split_once("/// declared_static_blocks():").unwrap().0
  }
  assert_eq!(lazy_body(&out.body), lazy_body(&master));
  let actual: Vec<_> = out.diags.iter().map(|d| (d.rel.as_str(), d.line, d.msg.as_str())).collect();
  let expected: Vec<_> = master_diags.iter().map(|d| (d.rel.as_str(), d.line, d.msg.as_str())).collect();
  assert_eq!(actual, expected);
  assert_eq!(actual.len(), 5);
  assert!(out.body.contains("/proc/extra_of(datum/H)"));
  assert!(out.body.contains("/proc/storage_ref_write(datum/H, field, datum/target)"));
  let registry = out.body.split_once("/proc/lazy_feature_rows()").unwrap().1.split_once("/// The lazy states' accessors").unwrap().0;
  assert!(!registry.contains("/datum/test_probe"));
 }

 #[test]
 fn native_declare_without_type_authority_refuses_implicit_relation_even_in_a_part() {
  let mut pages = fixture();
  let root = std::env::current_dir().unwrap().join("declare-growth-data");
  let path = root.join("code/part.dm");
  let run = |pages:&Pages| generate_from_pages(pages, &HashMap::new(), &Budget::new(32 * 1024 * 1024).unwrap(), &|| Ok(()));
  pages.files.push(File::capture(&root, &path,
   "CAPABILITIES_PART(/datum/device, extra)\n    ref_one(nameof(implicit), weak = TRUE)\n".into()).unwrap());
  let error = run(&pages).unwrap_err();
  assert!(matches!(error, Failure::Unsupported(msg) if msg == crate::declare_policy::REL_VAR_TYPES_UNAVAILABLE));
  pages.files.pop();
  pages.files.push(File::capture(&root, &path,
   "CAPABILITIES_PART(/datum/device, extra)\n    ref_one(nameof(explicit), /datum, weak = TRUE)\n".into()).unwrap());
  assert!(run(&pages).unwrap().body.contains("// part extra at code/part.dm:1"));
 }

 #[test]fn declare_growth_preserves_actual_io_quota_and_stopped_traversal_then_recovers(){
  let pages=fixture();pages.fail.set(true);let error=generate_from_pages(&pages,&HashMap::new(),&Budget::new(32*1024*1024).unwrap(),&||Ok(())).unwrap_err();assert!(matches!(error,Failure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));pages.fail.set(false);pages.stop.set(true);assert!(matches!(generate_from_pages(&pages,&HashMap::new(),&Budget::new(32*1024*1024).unwrap(),&||Ok(())),Err(Failure::Unsupported(_))));pages.stop.set(false);
  let tiny=Budget::new(4096).unwrap();let error=generate_from_pages(&pages,&HashMap::new(),&tiny,&||if tiny.denied(){Err(io::ErrorKind::Interrupted.into())}else{Ok(())}).unwrap_err();assert!(matches!(error,Failure::Operational(ref actual)if actual.kind()==io::ErrorKind::OutOfMemory));assert!(!generate_from_pages(&pages,&HashMap::new(),&Budget::new(32*1024*1024).unwrap(),&||Ok(())).unwrap().body.is_empty());
 }
 #[test]fn declare_shared_text_and_call_helpers_keep_preport_unicode_escape_and_match_quirks(){
  for text in["", "  alpha\t beta ", "a\\\n  b", "a\\\r\n b", "α\u{2003}β\u{a0}γ", "\\\\\n", "a\r\nb", "\"a\\b\"", "name(\"one\", list(a, b))"]{
   assert_eq!(crate::declare_policy::one_line(text),declare_before_policy::one_line(text));assert_eq!(crate::declare_policy::quote(text),declare_before_policy::quote(text));
  }
  for text in["f(1)","outer(f(1), f(list(2,3)))", "obj.f(1); /proc/f(2); global.f(3)","αf(1) f(2)", "\"f(inside)\" + f(outside)","f (1) f(2) f("]{
   let rewrite=|args:&[String]|format!("replace[{}]",args.join("|"));assert_eq!(crate::declare_policy::rewrite_calls(text,"f",&rewrite),declare_before_policy::rewrite_calls(text,"f",&rewrite));
  }
 }
 #[test]fn declare_engine_padding_is_not_charged_as_marker_or_constructor_transform_work(){
  let root=std::env::current_dir().unwrap().join("declare-engine-padding");let text=format!("{}\n/proc/wall(a,b)\n", "// unused engine source padding\n".repeat(4096));
  let pages=Pages{files:[("code/a.dm","CAPABILITIES(/datum/probe)\n    wall(1, 2)\n".to_owned()),("code/engine/large.dm",text)].into_iter().map(|(relative,text)|File::capture(&root,&root.join(relative),text.into()).unwrap()).collect(),fail:Cell::new(false),stop:Cell::new(false)};
  let budget=Budget::new(3*1024*1024).unwrap();let before=budget.used();let out=generate_from_pages(&pages,&HashMap::new(),&budget,&||Ok(())).unwrap();assert!(out.body.contains("global.wall(1, 2)"));assert!(!budget.denied());
  let retained=out.body.capacity()+out.diags.capacity()*std::mem::size_of::<crate::sparse_slots_policy::Diagnostic>()+out.diags.iter().map(|row|row.rel.capacity()+row.msg.capacity()).sum::<usize>()+std::mem::size_of::<Output>();
  assert_eq!(budget.used()-before,retained+std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>(),"only actual moved output and fixed scratch metadata survive");
 }

 #[test]fn declare_preport_reference_projection_changes_only_nominal_cap_type_paths(){
  let frozen=include_str!("support/declare_before_policy.frozen");let projected=include_str!("support/declare_before_policy.rs");
  let expected=frozen.replace("    declare_ids_policy::{split_opt, Cap},\n","").replace("use std::collections::{BTreeMap, BTreeSet};","use std::collections::{BTreeMap,BTreeSet};\nuse super::declare_before_ids::{split_opt,Cap};").replace("crate::declare_ids_policy::parse_capability","super::declare_before_ids::parse_capability");assert_eq!(projected,expected);
 }

}

#[cfg(test)]
mod exact_named_stage_tests {
    use super::*;

    #[test]
    fn exact_named_stage_preserves_bytes_and_releases_before_the_next_probe() {
        use crate::captured_generator_budget::Budget;
        for body in ["", "one line", "one line\n", "text: \u{6f22}\nsecond"] {
            let mut output = Output::default();
            output.body = body.to_owned();
            let mut expected = String::new();
            output.write_named_file_text("declare", "declare.dm", &mut expected).unwrap();
            let budget = Budget::new(65536).unwrap();
            let baseline = budget.used();
            let stage = capture_exact_named_file(&output, "declare", "declare.dm", &budget, None).unwrap();
            assert_eq!(stage.as_str(), expected);
            assert_eq!(budget.used(), baseline + expected.len());
            drop(stage);
            assert_eq!(budget.used(), baseline);
            let stage = capture_exact_named_file(&output, "declare", "declare.dm", &budget, None).unwrap();
            assert_eq!(stage.as_str(), expected);
            drop(stage);
            let short = Budget::new(baseline + expected.len() - 1).unwrap();
            let failure = capture_exact_named_file(&output, "declare", "declare.dm", &short, None).err().unwrap();
            assert_eq!(failure.kind(), std::io::ErrorKind::OutOfMemory);
            assert_eq!(short.used(), baseline);
        }
    }

    #[test]
    fn exact_named_stage_holds_parent_bytes_only_until_the_backing_is_freed() {
        let mut output = Output::default();
        output.body = "one line".to_owned();
        let mut expected = String::new();
        output.write_named_file_text("declare", "declare.dm", &mut expected).unwrap();
        let bytes = expected.len();
        let budget = Budget::new(65536).unwrap();
        let local_base = budget.used();
        let measure = dm_syntax::SharedNativeReservation::try_new(65536).unwrap();
        let parent_base = measure.reserved_bytes();
        let parent = dm_syntax::SharedNativeReservation::try_new(parent_base + bytes).unwrap();

        let stage = capture_exact_named_file(&output, "declare", "declare.dm", &budget, Some(&parent)).unwrap();
        assert_eq!(stage.as_str(), expected);
        assert_eq!(budget.used(), local_base + bytes);
        assert_eq!(parent.reserved_bytes(), parent_base + bytes);

        let denied = capture_exact_named_file(&output, "declare", "declare.dm", &budget, Some(&parent));
        assert_eq!(denied.err().unwrap().kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(budget.used(), local_base + bytes);
        assert_eq!(parent.reserved_bytes(), parent_base + bytes);
        drop(stage);
        assert_eq!(budget.used(), local_base);
        assert_eq!(parent.reserved_bytes(), parent_base);

        let short = Budget::new(local_base + bytes - 1).unwrap();
        let denied = capture_exact_named_file(&output, "declare", "declare.dm", &short, Some(&parent));
        assert_eq!(denied.err().unwrap().kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(short.used(), local_base);
        assert_eq!(parent.reserved_bytes(), parent_base);
    }
}
