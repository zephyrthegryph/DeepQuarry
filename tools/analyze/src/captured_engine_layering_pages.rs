//! Available-original-model engine layering DATA. No source/public report issuer.
//! The actual host must preflight selection BEFORE attempting the common model;
//! genuine unavailable/model/body outcomes remain its sealed issuer contract.
use crate::{captured_api_pages as fund,captured_allow_annotations::Operation,captured_generator_budget::Budget,captured_raw_file::Config,captured_reactive_reads::Failure,key_policy_control::{self as kc,Control},reactive_raw_policy_pages::RawPolicyPages,engine_layering_policy::{self as judge,Finding,Layer}};
use dm_analysis::{engine_layering_native::{self as native,DefinitionPointKind},policy_body_demand::WorkspaceWork};
use std::{collections::{BTreeMap,BTreeSet},io,path::Path,sync::Arc};
fn oom(b:&Budget,s:impl Into<String>)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,s.into()))}
struct Work<'a>{budget:&'a Budget,poll:&'a dyn Fn()->io::Result<()>,peak:usize}
impl WorkspaceWork for Work<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{fund::checked(self.budget,self.poll)}fn retain(&mut self,n:usize)->Result<(),Failure>{self.budget.charge(n).map_err(|m|oom(self.budget,m))}fn temporary(&mut self,n:usize)->Result<(),Failure>{if n>self.peak{self.budget.charge(n-self.peak).map_err(|m|oom(self.budget,m))?;self.peak=n;}Ok(())}fn overflow(&mut self)->Failure{oom(self.budget,"engine model observation geometry overflow")}fn allocation_failed(&mut self)->Failure{oom(self.budget,"engine model observation allocation refused")}fn body<'a>(&mut self,a:&'a dm_tree::frontend::BodyArchive,n:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Failure>{self.checkpoint()?;a.parse_checked(n).map_err(|e|match e{dm_tree::frontend::BodySyntaxFailure::Operational(e)=>Failure::Operational(e),dm_tree::frontend::BodySyntaxFailure::Syntax(e)=>Failure::Unsupported(e.message)})}}
struct Leaf<'a,C>{c:&'a mut C}
impl<C:Control<Error=Failure>> WorkspaceWork for Leaf<'_,C>{type Error=Failure;const CHECKED:bool=C::CHECKED;fn checkpoint(&mut self)->Result<(),Failure>{self.c.checkpoint()}fn retain(&mut self,n:usize)->Result<(),Failure>{self.c.reserve(n)}fn temporary(&mut self,n:usize)->Result<(),Failure>{self.c.temporary(0,n)}fn overflow(&mut self)->Failure{self.c.overflow()}fn allocation_failed(&mut self)->Failure{self.c.allocation_failed()}fn body<'a>(&mut self,_:&'a dm_tree::frontend::BodyArchive,_:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Failure>{Err("engine provenance leaf cannot trigger a body parse".into())}}
struct Scratch<C>{c:C,peaks:[usize;4]}
impl<C:Control> Control for Scratch<C>{type Error=C::Error;const CHECKED:bool=C::CHECKED;fn checkpoint(&mut self)->Result<(),Self::Error>{self.c.checkpoint()}fn reserve(&mut self,n:usize)->Result<(),Self::Error>{self.c.reserve(n)}fn temporary(&mut self,slot:usize,n:usize)->Result<(),Self::Error>{let old=*self.peaks.get(slot).ok_or_else(||self.c.overflow())?;if n>old{self.c.reserve(n-old)?;self.peaks[slot]=n;}Ok(())}fn overflow(&mut self)->Self::Error{self.c.overflow()}fn allocation_failed(&mut self)->Self::Error{self.c.allocation_failed()}}
struct Phase{budget:Arc<Budget>,ok:bool}impl Drop for Phase{fn drop(&mut self){if !self.ok{self.budget.keep_failed_scratch()}}}
/// Selection DATA only. No fabricated semantic model or whole-source authority.
pub struct Selection{layer:Layer,all:BTreeSet<String>,selected:BTreeSet<String>}
impl Selection{pub fn is_empty(&self)->bool{self.selected.is_empty()}pub fn first(&self)->Option<&str>{self.selected.first().map(String::as_str)}}
/// Borrowed current discovery-name DATA; the actual source factory owns the
/// receipt/EOF/current-frame proof. No CODE bytes or semantic input are demanded.
pub trait PathPages{fn for_each_path(&self,visit:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<bool,Failure>;}
pub fn preflight(pages:&dyn PathPages,config:&Config,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Selection,Failure>{
    preflight_for(Layer::Engine,pages,config,budget,poll)
}

pub fn preflight_for(layer:Layer,pages:&dyn PathPages,config:&Config,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Selection,Failure>{
    let mut out=Selection{layer,all:BTreeSet::new(),selected:BTreeSet::new()};
    if !pages.for_each_path(&mut|rel|{
        fund::checked(budget,poll)?;
        if !crate::captured_raw_file::is_code_dm(rel){return Err("layering preflight is outside actual visible CODE_DM domain".into())}
        fund::node(budget)?;
        out.all.insert(fund::own(budget,poll,rel)?);
        if layer.selects(rel)&&!config.policy_path_exempt(layer.name(),"",rel){
            fund::node(budget)?;
            out.selected.insert(fund::own(budget,poll,rel)?);
        }
        Ok(())
    })?{return Err("layering metadata selection ended before actual EOF".into())}
    fund::checked(budget,poll)?;
    Ok(out)
}

#[derive(Default)]struct Index{types:BTreeMap<String,Vec<String>>,owners:BTreeMap<String,Vec<String>>,defs:BTreeMap<String,Vec<(u32,String,String)>>}
fn index_file(map:&mut BTreeMap<String,Vec<String>>,ty:&str,file:&str,b:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{if !map.contains_key(ty){fund::node(b)?;map.insert(fund::own(b,poll,ty)?,Vec::new());}let row=map.get_mut(ty).unwrap();fund::row(b,poll,row)?;row.push(fund::own(b,poll,file)?);Ok(())}
struct Facts<'m,'a>{model:&'m native::Model<'a>,index:&'m Index}
impl<C:Control<Error=Failure>> judge::Facts<C> for Facts<'_,'_>{type Call=dm_analysis::checker_call_facts::CallableFact;
 fn builtin_type(&self,path:&str,c:&mut C)->Result<bool,Failure>{self.model.builtin_type(path,&mut Leaf{c})}fn type_exists(&self,path:&str,c:&mut C)->Result<bool,Failure>{self.model.type_exists(path,&mut Leaf{c})}
 fn def_at(&self,file:&str,line:u32,c:&mut C)->Result<Option<(String,String)>,Failure>{c.checkpoint()?;let Some(rows)=self.index.defs.get(file)else{return Ok(None)};let at=rows.partition_point(|(no,_,_)|*no<=line);if at==0{return Ok(None)}let row=&rows[at-1];kc::temporary(c,3,||row.1.len().checked_add(row.2.len())?.checked_mul(4)?.checked_add(512))?;Ok(Some((row.1.clone(),row.2.clone())))}
 fn type_headers(&self,path:&str)->Option<&[String]>{self.index.types.get(path).map(Vec::as_slice)}fn owner_definitions(&self,path:&str)->Option<&[String]>{self.index.owners.get(path).map(Vec::as_slice)}
 fn method(&self,owner:&str,name:&str,c:&mut C)->Result<Option<Self::Call>,Failure>{self.model.method(owner,name,&mut Leaf{c})}fn global(&self,name:&str,c:&mut C)->Result<Option<Self::Call>,Failure>{self.model.global(name,&mut Leaf{c})}
 fn builtin_call(&self,call:&Self::Call,c:&mut C)->Result<bool,Failure>{c.checkpoint()?;Ok(matches!(call,dm_analysis::checker_call_facts::CallableFact::CheckerBuiltin{..}))}
 fn callable_file(&self,call:&Self::Call,c:&mut C)->Result<String,Failure>{self.model.callable_file(call,&mut Leaf{c})?.ok_or_else(||Failure::from("builtin engine callable has no source file"))}
 fn visit_method_declaration_files(&self,owner:&str,name:&str,c:&mut C,emit:&mut dyn FnMut(&str,&mut C)->Result<bool,Failure>)->Result<(),Failure>{self.model.method_declaration_files(owner,name,&mut Leaf{c},&mut|file,leaf|emit(file,leaf.c))}
}
pub struct LayeringData{layer:Layer,sites:Vec<crate::lint::Site>,source_text:Option<Vec<String>>}
impl LayeringData{pub fn sites(&self)->&[crate::lint::Site]{&self.sites}pub fn metadata(&self)->&'static crate::lint::Meta{self.layer.metadata()}pub fn source_text(&self)->Option<&[String]>{self.source_text.as_deref()}pub fn notes(&self)->&[String]{&[]}pub fn allow_used(&self)->&[crate::lint::AllowUse]{&[]}}
/// Actual host may finish this DATA branch before constructing ANY semantic input.
/// Nonempty selection is not allowed to become a synthetic clean result.
pub fn finish_unselected(selection:Selection,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<LayeringData,Failure>{fund::checked(root,poll)?;if !selection.is_empty(){return Err("engine nonempty selection requires authentic original model outcome".into())}Ok(LayeringData{layer:selection.layer,sites:Vec::new(),source_text:(selection.layer==Layer::Library).then(Vec::new)})}
pub fn collect_available(pages:&dyn RawPolicyPages,inputs:&dm_analysis::policy_inputs::PolicyInputs,root_path:&Path,_config:&Config,selection:Selection,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<LayeringData,Failure>{
 fund::checked(root,poll)?;if selection.is_empty(){return finish_unselected(selection,root,poll)}let layer=selection.layer;let model=native::Model::new(inputs,root_path)?;let mut phase=Phase{budget:Budget::scoped_temporaries(root).map_err(|m|oom(root,m))?,ok:false};let b=&phase.budget;let pending=(||{
 let mut idx=Index::default();let cap_type=regex::Regex::new(r"^CAPABILITY_TYPE\s*\(\s*[^,]+,\s*[^,]+,\s*(/[A-Za-z_][\w/]*)").unwrap();let cap_def=regex::Regex::new(r"^CAPABILITY_DEF\s*\(\s*([A-Za-z_]\w*)\s*,").unwrap();
 if !pages.for_each(&mut|rel,views|{fund::checked(b,poll)?;if !selection.all.contains(rel){return Err("engine raw provenance source differs from preflight".into())}let code=views.code()?;let local=views.allocation_budget(root);let events=crate::layering_raw_policy::events_using(&code.text,&cap_type,&cap_def,&mut Operation{budget:local,poll})?;let mut parents:Vec<(usize,String)>=Vec::new();let mut work=Work{budget:local,poll,peak:0};for event in events{work.checkpoint()?;match event{crate::layering_raw_policy::Event::Owner(owner)=>if model.type_exists(&owner,&mut work)?{index_file(&mut idx.owners,&owner,rel,b,poll)?;},crate::layering_raw_policy::Event::Type(ty)=>index_file(&mut idx.types,&ty,rel,b,poll)?,crate::layering_raw_policy::Event::Indent(indent)=>while parents.last().is_some_and(|(n,_)|*n>=indent as usize){parents.pop();},crate::layering_raw_policy::Event::Header(indent,header)=>{let path=if header.starts_with('/'){header}else if let Some((_,parent))=parents.last(){let mut c=Operation{budget:local,poll};kc::format(&mut c,format_args!("{parent}/{header}"))?}else{continue};if path.split('/').any(|p|matches!(p,"var"|"proc"|"verb")){continue}if model.type_exists(&path,&mut work)?{index_file(&mut idx.types,&path,rel,b,poll)?;fund::row(local,poll,&mut parents)?;parents.push((indent as usize,path));}}}}let _=views.raw()?;Ok(true)})?{return Err("engine full raw provenance phase omitted EOF".into())}
 let mut work=Work{budget:b,poll,peak:0};model.declaration_points(&mut work,&mut|point,_|{if selection.all.contains(point.file){index_file(&mut idx.owners,point.owner,point.file,b,poll)?;}if point.kind!=DefinitionPointKind::VariableValue{if !idx.defs.contains_key(point.file){fund::node(b)?;idx.defs.insert(fund::own(b,poll,point.file)?,Vec::new());}let rows=idx.defs.get_mut(point.file).unwrap();fund::row(b,poll,rows)?;rows.push((point.line,fund::own(b,poll,point.owner)?,fund::own(b,poll,point.name)?));}Ok(())})?;for rows in idx.defs.values_mut(){kc::sort_data(rows,&mut|a,c|->Result<std::cmp::Ordering,Failure>{fund::checked(b,poll)?;Ok(a.cmp(c))})?;}
 let facts=Facts{model:&model,index:&idx};let mut found=BTreeSet::<Finding>::new();let mut judge_work=Scratch{c:Operation{budget:b,poll},peaks:[0;4]};
 model.formal_variables(&mut work,&mut|_,_,file,line,ty,_|{if selection.selected.contains(file)&&!ty.is_empty(){judge::ty(layer,&facts,&mut found,file,line,ty,&mut judge_work)?;}Ok(())})?;
 for ordinal in 0..inputs.archive().len(){fund::checked(b,poll)?;let occurrence=&inputs.archive().occurrences()[ordinal];let origin=inputs.archive().callable_header_policy_line(occurrence.member)?;let(file,_)=model.point(&origin.path,origin.line,&mut work)?;if !selection.selected.contains(&file){continue}let mut body_phase=Phase{budget:Budget::scoped_temporaries(root).map_err(|m|oom(root,m))?,ok:false};let mut body_work=Work{budget:&body_phase.budget,poll,peak:0};native::observe_body_using(&model,ordinal,&mut body_work,&mut|file,line,event,_|{match event{native::Use::Type(ty)=>judge::ty(layer,&facts,&mut found,file,line,ty,&mut judge_work),native::Use::Method{owner,name}=>judge::method(layer,&facts,&mut found,file,line,owner,name,&mut judge_work),native::Use::Global(name)=>judge::global(layer,&facts,&mut found,file,line,name,&mut judge_work)}})?;body_phase.ok=true;drop(body_phase);}
 let marker=regex::Regex::new(r"^(?:(?:CAPABILITIES_PART|CAPABILITIES|STAT)\s*\(\s*(/[A-Za-z_][\w/]*)|CAPABILITY_TYPE\s*\(\s*[^,]+,\s*[^,]+,\s*(/[A-Za-z_][\w/]*))").unwrap();
 let mut seen=BTreeSet::new();
 let mut fingerprints=BTreeMap::<String,Vec<(u32,String)>>::new();
 if !pages.for_each(&mut|rel,views|{
    fund::checked(b,poll)?;
    if !selection.selected.contains(rel){return Ok(true)}
    fund::node(b)?;
    if !seen.insert(fund::own(b,poll,rel)?){return Err("duplicate selected layering marker file".into())}
    let text=views.clean(root)?;
    let mut entries=false;
    let mut marker_owner=None;
    for(number,line)in text.split('\n').enumerate(){
        fund::checked(b,poll)?;
        let no=u32::try_from(number+1).map_err(|_|oom(b,"layering raw line overflow"))?;
        if !line.starts_with('\t')&&!line.starts_with(' ')&&!line.trim().is_empty(){
            entries=line.starts_with("CAPABILITIES(")||line.starts_with("CAPABILITIES_PART(")||line.starts_with("STAT(")||line.starts_with("CAPABILITY_TYPE(");
            marker_owner=marker.captures(line).and_then(|cap|cap.get(1).or_else(||cap.get(2)).map(|m|m.as_str()));
        }
        judge::source_paths(layer,&facts,&mut found,rel,no,line,&mut judge_work)?;
        judge::source_proc_refs(layer,&facts,&mut found,rel,no,line,marker_owner,&mut judge_work)?;
        if entries||line.trim_start().starts_with("var/")||(line.starts_with('/')&&line.contains('(')){
            judge::marker_calls(layer,&facts,&mut found,rel,no,line,&mut judge_work)?;
        }
    }
    if layer==Layer::Library{
        let local=views.allocation_budget(root);
        let first=Finding{rule:"external_dependency",file:fund::own(local,poll,rel)?,line:0,message:String::new()};
        let mut hits=found.range(first..).take_while(|row|row.file==rel).peekable();
        if hits.peek().is_some(){
            let mut lines=Vec::new();
            for (number,raw) in views.raw()?.split('\n').enumerate(){
                fund::checked(local,poll)?;
                let no=u32::try_from(number+1).map_err(|_|oom(b,"layering fingerprint line overflow"))?;
                if hits.next_if(|row|row.line==no).is_some(){
                    while hits.next_if(|row|row.line==no).is_some(){fund::checked(local,poll)?;}
                    fund::row(b,poll,&mut lines)?;
                    let bytes=raw.len().checked_add(64).ok_or_else(||oom(b,"layering fingerprint capacity overflow"))?;
                    b.charge(bytes).map_err(|message|oom(b,message))?;
                    lines.push((no,crate::util::normalize_ws(raw)));
                    if hits.peek().is_none(){break}
                }
            }
            if hits.next().is_some(){return Err("library layering fingerprint has no exact selected source line".into())}
            fund::node(b)?;
            fingerprints.insert(fund::own(b,poll,rel)?,lines);
        }
    }
    Ok(true)
 })?{return Err("layering selected marker source phase omitted EOF".into())}
 if seen!=selection.selected{return Err("layering selected marker source coverage differs from exact preflight".into())}
 let mut sites=Vec::new();
 let mut source_text=(layer==Layer::Library).then(Vec::new);
 for row in found{
    if let Some(text)=&mut source_text{
        let lines=fingerprints.get(&row.file).ok_or("library layering finding has no authenticated source file")?;
        let at=lines.binary_search_by_key(&row.line,|(line,_)|*line).map_err(|_|"library layering finding has no authenticated source line")?;
        fund::row(root,poll,text)?;
        text.push(fund::own(root,poll,&lines[at].1)?);
    }
    fund::row(root,poll,&mut sites)?;
    sites.push(crate::lint::Site{rule:fund::own(root,poll,row.rule)?,rel:fund::own(root,poll,&row.file)?,line:row.line,msg:fund::own(root,poll,&row.message)?,ident:String::new(),key:String::new()});
 }
 fund::checked(root,poll)?;
 Ok(LayeringData{layer,sites,source_text})
})();if matches!(&pending,Err(Failure::Operational(_))){return pending}fund::checked(root,poll)?;phase.ok=pending.is_ok();drop(phase);pending
}

/// Borrowed data branch; the actual host still must prove its closed no-model role.
pub fn finish_unselected_ref(selection:&Selection,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<LayeringData,Failure>{fund::checked(root,poll)?;if !selection.is_empty(){return Err("nonempty engine selection cannot finish without actual model outcome".into())}Ok(LayeringData{layer:selection.layer,sites:Vec::new(),source_text:(selection.layer==Layer::Library).then(Vec::new)})}
