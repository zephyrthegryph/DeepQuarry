//! Original relation declaration projection, not a general declaration model.
use crate::tree::{SourceFile, CODE_DM};
use std::collections::{BTreeMap, HashMap};
pub fn visit_legacy_line(t:&str,emit:impl FnMut(&str,&str)->Result<(),String>)->Result<(),String>{
    try_visit_legacy_line(t,emit)
}
/// SAME literal matcher; typed native callback failures do not become strings.
pub fn try_visit_legacy_line<E>(t:&str,mut emit:impl FnMut(&str,&str)->Result<(),E>)->Result<(),E>{
    let mut rows=None;
    let result=try_visit_legacy_line_using(t,&mut crate::key_policy_control::Compatibility,|owner,var|{rows=Some((owner,var));Ok(())});
    match result{Ok(())=>{},Err(never)=>match never{}}
    if let Some((owner,var))=rows{emit(owner,var)?;}Ok(())
}
const LEGACY_PAIR:&str=r"\A(?:OWN|OWN_POLICY|OWN_IF|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST)\(\s*(/[\w/]+)\s*,\s*(\w+)";
pub fn try_visit_legacy_line_using<'a,C:crate::key_policy_control::Control>(t:&'a str,work:&mut C,mut emit:impl FnMut(&'a str,&'a str)->Result<(),C::Error>)->Result<(),C::Error>{
    if let Some(m)=crate::key_policy_control::captures_static(work,LEGACY_PAIR,t,0,||crate::pat!(LEGACY_PAIR))?{emit(m.s(1),m.s(2))?;}work.checkpoint()
}
pub fn legacy_line(t: &str) -> Option<(String, String)> {
    let mut pair = None;
    visit_legacy_line(t, |a, b| {
        pair = Some((a.to_owned(), b.to_owned()));
        Ok(())
    })
    .expect("infallible legacy collector");
    pair
}

pub fn visit_capability_pairs(
    ty: &str,
    body: &str,
    mut emit: impl FnMut(&str, &str) -> Result<(), String>,
) -> Result<(), String> {
    try_visit_capability_pairs(ty,body,&mut||Ok::<(),String>(()),emit)
}
pub fn try_visit_capability_pairs<E>(ty:&str,body:&str,checkpoint:&mut impl FnMut()->Result<(),E>,mut emit:impl FnMut(&str,&str)->Result<(),E>)->Result<(),E>{
    struct Poll<'a,E,F>{poll:&'a mut F,_error:std::marker::PhantomData<E>}
    impl<E,F:FnMut()->Result<(),E>>crate::key_policy_control::Control for Poll<'_,E,F>{type Error=E;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),E>{(self.poll)()}fn reserve(&mut self,_:usize)->Result<(),E>{Ok(())}fn overflow(&mut self)->E{unreachable!()}fn allocation_failed(&mut self)->E{unreachable!()}}
    try_visit_capability_pairs_using(ty,body,&mut Poll{poll:checkpoint,_error:std::marker::PhantomData},emit)
}
const OWN_PAIR:&str=r"\b(?:owns_one|owns_many|ref_one|ref_many|hud_element|profile)\(\s*nameof\((\w+)\)";
const LINK_PAIR:&str=r"\blinks?\(\s*(/[\w/]+)::(\w+)\s*,\s*(/[\w/]+)::(\w+)";
pub fn try_visit_capability_pairs_using<C:crate::key_policy_control::Control>(ty:&str,body:&str,work:&mut C,mut emit:impl FnMut(&str,&str)->Result<(),C::Error>)->Result<(),C::Error>{
    let mut at=0;
    while let Some(c)=crate::key_policy_control::captures_static(work,OWN_PAIR,body,at,||crate::pat!(OWN_PAIR))?{work.checkpoint()?;emit(ty,c.s(1))?;at=c.end(0);}
    let mut at=0;
    while let Some(c)=crate::key_policy_control::captures_static(work,LINK_PAIR,body,at,||crate::pat!(LINK_PAIR))?{work.checkpoint()?;emit(c.s(1),c.s(2))?;emit(c.s(3),c.s(4))?;at=c.end(0);}
    work.checkpoint()
}
pub fn capability_pairs(ty: &str, body: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    visit_capability_pairs(ty, body, |a, b| {
        out.push((a.to_owned(), b.to_owned()));
        Ok(())
    })
    .expect("infallible legacy collector");
    out
}

fn add_using<C:crate::key_policy_control::Control>(
    out: &mut HashMap<String, Vec<String>>,
    owner: &str,
    var: &str,
    retained: &mut usize,
    limit: usize,work:&mut C,
) -> Result<(), C::Error> where C::Error:From<String>+for<'b>From<&'b str> {
    let bytes = owner
        .len()
        .checked_add(var.len())
        .and_then(|n| n.checked_mul(4))
        .and_then(|n| n.checked_add(256))
        .ok_or_else(||if C::CHECKED{work.overflow()}else{"relation declaration accounting overflow".into()})?;
    *retained = retained
        .checked_add(bytes)
        .ok_or_else(||if C::CHECKED{work.overflow()}else{"relation declaration accounting overflow".into()})?;
    if !C::CHECKED&&*retained > limit {
        return Err("relation declaration retention exceeds admission".into());
    }
    crate::key_policy_control::reserve(work,||bytes.checked_add(2048))?;
    if C::CHECKED{out.try_reserve(1).map_err(|_|work.allocation_failed())?;}
    let rows=out.entry(var.to_owned()).or_default();if C::CHECKED{rows.try_reserve(1).map_err(|_|work.allocation_failed())?;}rows.push(owner.to_owned());
    Ok(())
}
/// Exact union of Decls relations and ownership_index declaration projection.
/// The old scanner emits ephemeral events; no Index/member/type model is built.
pub(crate) struct DeclarationIndex {
    pub relations: HashMap<String, Vec<String>>,
    pub retained_admission: usize,
    pub registry: Vec<String>,
}
pub(crate) fn declarations(
    files: Vec<&SourceFile>,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<DeclarationIndex, String> {
    project(files, false, 0, checkpoint)
}
pub(crate) fn declarations_with_registry(
    files: Vec<&SourceFile>,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<DeclarationIndex, String> {
    project(files, true, 0, checkpoint)
}
pub(crate) fn declarations_with_registry_reserved(
    files: Vec<&SourceFile>,
    reserved: usize,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<DeclarationIndex, String> {
    project(files, true, reserved, checkpoint)
}
fn project(mut files:Vec<&SourceFile>,include_registry:bool,reserved:usize,mut checkpoint:impl FnMut()->Result<(),String>)->Result<DeclarationIndex,String>{
 struct Legacy<'a>(&'a mut dyn FnMut()->Result<(),String>);impl crate::key_policy_control::Control for Legacy<'_>{type Error=String;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),String>{(self.0)()}fn reserve(&mut self,_:usize)->Result<(),String>{Ok(())}fn overflow(&mut self)->String{"relation accounting overflow".into()}fn allocation_failed(&mut self)->String{"relation allocation failed".into()}}
 files.retain(|f|CODE_DM.matches(f));files.sort_by_key(|f|&f.rel);let shared=std::cell::RefCell::new(&mut checkpoint);let mut retained=Legacy(&mut||(*shared.borrow_mut())());let mut temporary=Legacy(&mut||(*shared.borrow_mut())());let mut projection=Projection::new_using(include_registry,reserved,&mut retained)?;for f in files{projection.file_using(f,&mut retained,&mut temporary)?;}projection.finish_using(&mut retained)
}
struct FileFacts{rel:String,relations:HashMap<String,Vec<String>>,legacy:BTreeMap<(String,String),String>,registry:Vec<String>}
pub(crate) struct Projection{pending:Vec<FileFacts>,retained:usize,registry:Vec<String>,include_registry:bool}
impl Projection{
 pub(crate) fn new_using<C:crate::key_policy_control::Control>(include_registry:bool,reserved:usize,work:&mut C)->Result<Self,C::Error>where C::Error:From<String>+for<'b>From<&'b str>{if !C::CHECKED&&reserved>64*1024*1024{return Err("relation coordination exceeds admission before allocation".into())}let mut value=Self{pending:Vec::new(),retained:reserved,registry:Vec::new(),include_registry};if include_registry{for ty in crate::raw_ownership_policy::FLYWEIGHT_TYPES{work.checkpoint()?;value.retained=value.retained.checked_add(ty.len().saturating_mul(4).saturating_add(128)).ok_or_else(||if C::CHECKED{work.overflow()}else{"registry accounting overflow".into()})?;crate::key_policy_control::row(work,&mut value.registry)?;value.registry.push(crate::key_policy_control::own(work,ty)?);}}Ok(value)}
 pub(crate) fn file_using<C:crate::key_policy_control::Control,T:crate::key_policy_control::Control<Error=C::Error>>(&mut self,f:&SourceFile,retained_work:&mut C,temporary_work:&mut T)->Result<(),C::Error>where C::Error:From<String>+for<'b>From<&'b str>{
  retained_work.checkpoint()?;if !CODE_DM.matches(f){return Err("relation projection source escaped actual CODE".into())}crate::key_policy_control::reserve(temporary_work,||f.raw().text.len().checked_mul(64)?.checked_add(8192))?;let mut out=HashMap::new();let mut legacy=BTreeMap::new();let mut registry=Vec::new();let include_registry=self.include_registry;let mut retained=self.retained;
        retained_work.checkpoint()?;
        let text = f.marker();
        let mut offset = 0;
        for line in text.as_str().split('\n') {
            retained_work.checkpoint()?;
            let t = line.trim_start();
            if !t.starts_with('#') && !t.is_empty() {
                try_visit_legacy_line_using(t, temporary_work, |owner, var| {
                    add_using(&mut out, owner, var, &mut retained, 64 * 1024 * 1024,retained_work)
                })?;
                if let Some(m) = crate::raw_marker_policy::statement_marker(
                    text.as_str(),
                    offset,
                    line,
                    &["CAPABILITIES"],
                ) {
                    let end = if line.len() == t.len() {
                        crate::raw_marker_policy::block_extent(text.as_str(), m.close)
                    } else {
                        None
                    };
                    let bytes = end
                        .unwrap_or(m.close)
                        .saturating_sub(m.open)
                        .checked_mul(32)
                        .ok_or_else(||if C::CHECKED{retained_work.overflow()}else{"relation block overflow".into()})?;
                    if !C::CHECKED&&retained.saturating_add(bytes) > 64 * 1024 * 1024 {
                        return Err("relation block exceeds admission before allocation".into());
                    }
                    let mut body = match end {
                        Some(end) => crate::raw_marker_policy::block_body(
                            text.as_str(),
                            m.open + 1,
                            m.close,
                            end,
                        ),
                        None => text.as_str()[m.open + 1..m.close].to_owned(),
                    };
                    let mut args = crate::raw_marker_policy::split_args(&body);
                    if m.name == "CAPABILITIES_PART" {
                        retained_work.checkpoint()?;
                        crate::raw_marker_policy::mask_capability_part(&mut body, &mut args);
                    }
                    if let Some(owner) = args.first() {
                        try_visit_capability_pairs_using(owner, &body,temporary_work, |owner, var| {
                            add_using(
                                &mut out,
                                owner,
                                var,
                                &mut retained,
                                (64usize * 1024 * 1024).saturating_sub(bytes),retained_work,
                            )
                        })?;
                    }
                }
            }
            offset += line.len() + 1;
        }
        let temporary = f
            .raw()
            .text
            .len()
            .checked_mul(32)
            .ok_or_else(||if C::CHECKED{retained_work.overflow()}else{"relation event admission overflow".into()})?;
        if !C::CHECKED&&retained.saturating_add(temporary) > 64 * 1024 * 1024 {
            return Err("relation event projection exceeds admission before allocation".into());
        }
        crate::raw_ownership_policy::try_visit_file_events_funded(&f.rel, f.raw(), f.code(),temporary_work, |ev| {
            if let crate::raw_ownership_policy::IdxEv::Decl {
                owner,
                name,
                macro_name,
                ..
            } = ev
            {
                // Original Index overwrites each (owner,var) with the last declaration.
                let bytes = owner
                    .len()
                    .saturating_add(name.len())
                    .saturating_add(macro_name.len())
                    .saturating_mul(4)
                    .saturating_add(256);
                retained = retained
                    .checked_add(bytes)
                    .ok_or_else(||if C::CHECKED{retained_work.overflow()}else{"relation legacy table accounting overflow".into()})?;
                if !C::CHECKED&&retained > 64 * 1024 * 1024 - temporary {
                    return Err("relation legacy table exceeds admission".into());
                }
                crate::key_policy_control::reserve(retained_work,||bytes.checked_add(2048))?;
                legacy.insert((owner, name), macro_name);
            } else if let crate::raw_ownership_policy::IdxEv::Registry(ty) = ev {
                if include_registry {
                    retained = retained
                        .checked_add(ty.len().saturating_mul(4).saturating_add(128))
                        .ok_or_else(||if C::CHECKED{retained_work.overflow()}else{"registry accounting overflow".into()})?;
                    if !C::CHECKED&&retained > 64 * 1024 * 1024 - temporary {
                        return Err("registry projection admission exceeded".into());
                    }
                    crate::key_policy_control::reserve(retained_work,||ty.len().checked_mul(4)?.checked_add(128))?;
                    registry.push(ty);
                }
            }
            Ok(())
        })?;

  self.retained=retained;crate::key_policy_control::row(retained_work,&mut self.pending)?;self.pending.push(FileFacts{rel:crate::key_policy_control::own(retained_work,&f.rel)?,relations:out,legacy,registry});retained_work.checkpoint()
 }
 pub(crate) fn finish_using<C:crate::key_policy_control::Control>(mut self,work:&mut C)->Result<DeclarationIndex,C::Error>where C::Error:From<String>+for<'b>From<&'b str>{
  crate::key_policy_control::reserve(work,||self.pending.len().checked_mul(std::mem::size_of::<FileFacts>())?.checked_add(128))?;crate::key_policy_control::sort_data(&mut self.pending,&mut|a,b|->Result<std::cmp::Ordering,C::Error>{work.checkpoint()?;Ok(a.rel.cmp(&b.rel))})?;let mut out=HashMap::new();let mut legacy=BTreeMap::new();let mut registry=self.registry;
  for file in self.pending{work.checkpoint()?;for(var,types)in file.relations{work.checkpoint()?;crate::key_policy_control::reserve(work,||Some(2048))?;if C::CHECKED{out.try_reserve(1).map_err(|_|work.allocation_failed())?;}let rows=out.entry(var).or_insert_with(Vec::new);if C::CHECKED{rows.try_reserve(types.len()).map_err(|_|work.allocation_failed())?;}rows.extend(types);}for(key,value)in file.legacy{work.checkpoint()?;crate::key_policy_control::reserve(work,||Some(2048))?;legacy.insert(key,value);}for value in file.registry{crate::key_policy_control::row(work,&mut registry)?;registry.push(value);}}
  for((owner,var),kind)in legacy{work.checkpoint()?;if kind!="ANNOTATE"{add_using(&mut out,&owner,&var,&mut self.retained,64*1024*1024,work)?;}}
  work.checkpoint()?;Ok(DeclarationIndex{relations:out,retained_admission:self.retained,registry})
 }
}

#[cfg(feature = "unified-oracle")]
pub fn oracle_projection(tree: &crate::tree::Tree) -> Result<HashMap<String, Vec<String>>, String> {
    Ok(declarations(tree.select(&CODE_DM), || Ok(()))?.relations)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn relation_pair_denial_happens_before_repeated_owner_rows_are_collected() {
        let mut seen = 0;
        let error = visit_capability_pairs(
            "/datum/holder",
            "ref_one(nameof(a)), ref_one(nameof(b))",
            |_, _| {
                seen += 1;
                Err("denied".into())
            },
        )
        .unwrap_err();
        assert_eq!(seen, 1);
        assert_eq!(error, "denied");
    }
}

#[cfg(all(test,feature="native-policy"))]mod workspace_projection_control_tests{
 use super::*;use crate::key_policy_control::Control;
 struct Work{polls:usize,fail_at:Option<usize>,denied:bool}impl Control for Work{type Error=crate::captured_reactive_reads::Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.fail_at==Some(self.polls){Err(crate::captured_reactive_reads::Failure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Ok(())}}fn reserve(&mut self,_:usize)->Result<(),Self::Error>{if self.denied{Err(self.allocation_failed())}else{Ok(())}}fn overflow(&mut self)->Self::Error{crate::captured_reactive_reads::Failure::Operational(std::io::ErrorKind::OutOfMemory.into())}fn allocation_failed(&mut self)->Self::Error{self.overflow()}}
 fn work()->Work{Work{polls:0,fail_at:None,denied:false}}
 #[test]fn same_file_projection_restores_cross_file_order_annotation_overwrite_and_actual_callback_failure(){let first=SourceFile::from_text("code/a.dm","CAPABILITIES(/datum/holder)\n    ref_one(nameof(declared))\n/datum/holder/relations()\n    . += owns(nameof(legacy))\n");let last=SourceFile::from_text("code/z.dm","/datum/holder/relations()\n    . += owns(nameof(legacy), policy = OWN_NONE)\n");let mut c=work();let mut temp=work();let mut projection=Projection::new_using(false,0,&mut c).unwrap();projection.file_using(&last,&mut c,&mut temp).unwrap();projection.file_using(&first,&mut c,&mut temp).unwrap();let result=projection.finish_using(&mut c).unwrap();assert_eq!(result.relations.get("declared"),Some(&vec!["/datum/holder".to_owned()]));assert!(!result.relations.contains_key("legacy"));let mut denied=work();denied.denied=true;let mut projection=Projection::new_using(false,0,&mut denied).unwrap();assert!(matches!(projection.file_using(&first,&mut denied,&mut work()),Err(crate::captured_reactive_reads::Failure::Operational(ref error))if error.kind()==std::io::ErrorKind::OutOfMemory));let mut count=0;let error=crate::raw_ownership_policy::try_visit_file_events(&first.rel,first.raw(),first.code(),&mut||{count+=1;if count==4{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}},|_|Ok(())).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(count,4);}
}

#[cfg(test)]mod projection_order_control_tests{#[test]fn exact_shared_sort_stops_at_first_io_and_recovers_in_ordinary_and_native_builds(){for limit in [false,true]{let mut values=(0..10000).rev().collect::<Vec<_>>();let mut comparisons=0usize;let error=crate::key_policy_control::sort_data(&mut values,&mut|a,b|->Result<std::cmp::Ordering,std::io::Error>{comparisons+=1;if comparisons==17{Err(if limit{std::io::ErrorKind::OutOfMemory.into()}else{std::io::Error::from_raw_os_error(1450)})}else{Ok(a.cmp(b))}}).unwrap_err();assert_eq!(comparisons,17);if limit{assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory)}else{assert_eq!(error.raw_os_error(),Some(1450))}crate::key_policy_control::sort_data(&mut values,&mut|a,b|Ok::<_,std::io::Error>(a.cmp(b))).unwrap();assert_eq!(values,(0..10000).collect::<Vec<_>>());}}}

#[cfg(all(test,feature="native-policy"))]
mod native_relation_pattern_port_tests{
 use super::*;
 use crate::{captured_allow_annotations::Operation,captured_generator_budget::Budget,captured_reactive_reads::Failure,native_pattern::{Provider,Spec}};
 use std::sync::atomic::{AtomicUsize,Ordering};
 struct Refusing{width:bool,lengths:AtomicUsize,captures:AtomicUsize}
 impl Provider for Refusing{
  fn capture_len(&self,_:Spec)->std::io::Result<usize>{self.lengths.fetch_add(1,Ordering::Relaxed);if self.width{Ok(5)}else{Err(std::io::Error::from_raw_os_error(1450))}}
  fn find(&self,_:Spec,_:&str,_:usize,_:&mut dyn FnMut((usize,usize))->std::io::Result<()>)->std::io::Result<bool>{panic!("capture policy must use the capture port")}
  fn capture(&self,_:Spec,_:&str,_:usize,_:&mut dyn FnMut(&[Option<(usize,usize)>])->std::io::Result<()>)->std::io::Result<bool>{self.captures.fetch_add(1,Ordering::Relaxed);Err(std::io::Error::from_raw_os_error(1450))}
 }
 fn provider(width:bool)->Refusing{Refusing{width,lengths:AtomicUsize::new(0),captures:AtomicUsize::new(0)}}
 struct Late<'a>{stopped:&'a std::sync::atomic::AtomicBool,actual_io:bool}
 impl Provider for Late<'_>{
  fn capture_len(&self,_:Spec)->std::io::Result<usize>{Ok(5)}
  fn find(&self,_:Spec,_:&str,_:usize,_:&mut dyn FnMut((usize,usize))->std::io::Result<()>)->std::io::Result<bool>{panic!("capture policy must use the capture port")}
  fn capture(&self,_:Spec,_:&str,_:usize,_:&mut dyn FnMut(&[Option<(usize,usize)>])->std::io::Result<()>)->std::io::Result<bool>{self.stopped.store(true,Ordering::Release);if self.actual_io{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(false)}}
 }
 #[test]
 fn native_relation_pattern_uses_provider_and_preserves_first_actual_io(){
  let budget=Budget::new(1<<20).unwrap();let p=provider(false);let mut c=Operation{budget:&budget,poll:&||Ok(())}.with_patterns(&p);
  let error=try_visit_capability_pairs_using("/datum/holder","ref_one(nameof(x))",&mut c,|_,_|panic!("no row after actual program IO")).unwrap_err();
  assert!(matches!(error,Failure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));assert_eq!(p.lengths.load(Ordering::Relaxed),1);assert_eq!(p.captures.load(Ordering::Relaxed),0);
 }
 #[test]
 fn native_relation_capture_reservation_precedes_execution(){
  let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();let budget=Budget::new(fixed).unwrap();let p=provider(true);let mut c=Operation{budget:&budget,poll:&||Ok(())}.with_patterns(&p);
  let error=try_visit_legacy_line_using("OWN(/datum/holder, x)",&mut c,|_,_|panic!("no row after actual reservation refusal")).unwrap_err();
  assert!(matches!(error,Failure::Operational(ref actual)if actual.kind()==std::io::ErrorKind::OutOfMemory));assert_eq!(p.lengths.load(Ordering::Relaxed),1);assert_eq!(p.captures.load(Ordering::Relaxed),0);
 }
 #[test]
 fn native_relation_projection_borrows_file_pattern_control(){
  let budget=Budget::new(4<<20).unwrap();let scratch=Budget::new(4<<20).unwrap();let p=provider(false);let mut retained=Operation{budget:&budget,poll:&||Ok(())};let mut temporary=Operation{budget:&scratch,poll:&||Ok(())}.with_patterns(&p);
  let file=SourceFile::from_text("code/probe.dm","CAPABILITIES(/datum/holder)\n    ref_one(nameof(x))\n");
  let mut projection=Projection::new_using(false,0,&mut retained).unwrap();let error=projection.file_using(&file,&mut retained,&mut temporary).unwrap_err();
  assert!(matches!(error,Failure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));assert_eq!(p.lengths.load(Ordering::Relaxed),1);
 }
 #[test]
 fn native_relation_final_cancel_and_first_actual_provider_io_have_distinct_channels(){
  for actual_io in [false,true]{
   let stopped=std::sync::atomic::AtomicBool::new(false);let p=Late{stopped:&stopped,actual_io};let budget=Budget::new(1<<20).unwrap();
   let poll=||if stopped.load(Ordering::Acquire){Err(std::io::ErrorKind::Interrupted.into())}else{Ok(())};let mut c=Operation{budget:&budget,poll:&poll}.with_patterns(&p);
   let error=try_visit_capability_pairs_using("/datum/holder","ref_one(nameof(x))",&mut c,|_,_|panic!("no row on failed/canceled provider")).unwrap_err();
   match error{Failure::Operational(actual)if actual_io=>assert_eq!(actual.raw_os_error(),Some(1450)),Failure::Operational(actual)=>assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted),Failure::Unsupported(reason)=>panic!("operational failure became unsupported: {reason}")}
  }
 }
 #[test]
 fn original_relation_pair_order_and_cross_link_ends_are_unchanged(){
  let rows=capability_pairs("/datum/holder","links(/datum/a::left, /datum/b::right), ref_many(nameof(second)), owns_one(nameof(first))");
  assert_eq!(rows,vec![("/datum/holder".into(),"second".into()),("/datum/holder".into(),"first".into()),("/datum/a".into(),"left".into()),("/datum/b".into(),"right".into())]);
  assert_eq!(legacy_line("REL_PAIR_LIST(/datum/holder, members)"),Some(("/datum/holder".into(),"members".into())));
  for rejected in ["prefix OWN(/datum/holder, x)"," OWN(/datum/holder, x)","\nOWN(/datum/holder, x)"]{assert_eq!(legacy_line(rejected),None,"old pat_match never searches after a prefix");}
 }
}
