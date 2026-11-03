//! Original native declaration/callable projections for the reactive walk.
//! This is NOT a second type/procedure model and does not itself close reads.
//! All fields remain selected from the actual original archive/current capture.
use crate::{captured_raw_policy::CapturedRawPolicy,captured_generator_budget::Budget};
use dm_analysis::{policy_inputs::{PolicyInputs,PolicyRole},checker_variable_facts};
use dm_ir::{SymbolId,ProcedureIdentity,ResolvedMeaning};
use dm_tree::{MemberKind,Target};
// Exact existing dm-tree adapter declaration flag layout.
const STATIC_FLAG:u32=1;const CONST_FLAG:u32=2;const TMP_FLAG:u32=4;
use std::{path::Path,sync::Arc,collections::HashMap,borrow::Cow};

/// Stack-only source binding. No raw/native tree, callable map or AST is copied.
pub(crate) struct ReadSource<'a>{raw:Option<&'a CapturedRawPolicy>,raw_pages:Option<&'a dyn crate::reactive_raw_policy_pages::RawPolicyPages>,native_root:Option<&'a Path>,inputs:&'a PolicyInputs,budget:&'a Arc<Budget>,order:ReadOrder<'a>,checkpoint:Option<&'a dyn Fn()->std::io::Result<()>>,body_borrower:Option<&'a dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>>}
/// One existing include-order map; temporary page views borrow it directly.
enum ReadOrder<'a>{Owned(HashMap<String,usize>),Borrowed(&'a HashMap<String,usize>)}
impl std::ops::Deref for ReadOrder<'_>{type Target=HashMap<String,usize>;fn deref(&self)->&Self::Target{match self{Self::Owned(map)=>map,Self::Borrowed(map)=>map}}}
/// A callable defining owner/header, borrowed from the original producer.
/// A callback cannot manufacture this value or replace its ordinal/member.
pub(crate) struct ReadCallable<'a>{
    pub owner:&'a str,pub name:&'a str,pub ordinal:usize,
    pub member:dm_tree::MemberId,pub file:&'a dm_analysis::policy_inputs::PolicyFile,
    pub header:usize,
}
pub(crate) struct OriginalDefinitionPoint<'a>{pub member:dm_tree::MemberId,pub ordinal:dm_tree::OccurrenceId,pub line:usize,pub owner:&'a str,pub name:&'a str,pub path:Arc<std::path::PathBuf>}
pub(crate) enum SelectedCallable<'a>{Source(ReadCallable<'a>),Builtin,Missing}
pub(crate) struct ReadVariable<'a>{
    pub owner:&'a str,pub declared:String,pub file:Option<Cow<'a,str>>,
    pub is_static:bool,pub is_const:bool,pub is_tmp:bool,
}
#[derive(Clone,Copy)]enum VariableProjection{Full,TypeOnly}
fn charge(b:&Budget,n:Option<usize>)->Result<(),String>{
    match n{Some(n)=>b.charge(n),None=>{b.deny();Err("reactive original source admission overflow".into())}}
}
impl<'a> ReadSource<'a>{
    /// Stack-only budget loan over the SAME original source/input/order and
    /// active control/body borrower. No recapture, new map, source clone, query
    /// or credit is issued here. The caller must preadmit its temporary page
    /// and retain graph allocations under their real parent before page drop.
    pub(crate) fn with_budget<'page,T>(&'page self,budget:&'page Arc<Budget>,operation:impl FnOnce(&ReadSource<'page>)->T)->T{
        let page=ReadSource{raw:self.raw,raw_pages:self.raw_pages,native_root:self.native_root,inputs:self.inputs,budget,order:ReadOrder::Borrowed(&self.order),checkpoint:self.checkpoint,body_borrower:self.body_borrower};operation(&page)
    }
    pub(crate) fn reserve(&self,n:Option<usize>)->Result<(),String>{charge(self.budget,n)}
    pub(crate) fn inputs(&self)->&'a PolicyInputs{self.inputs}


    pub(crate) fn with_checkpoint(mut self,checkpoint:&'a dyn Fn()->std::io::Result<()>)->Self{self.checkpoint=Some(checkpoint);self}
    /// Stack-only operation control; no query/cache/gate/reset or source grant.
    /// Native long helpers must use this in addition to budget-only require().
    pub(crate) fn checkpoint(&self)->std::io::Result<()>{
        self.checkpoint.ok_or_else(||std::io::Error::new(std::io::ErrorKind::NotConnected,"reactive source requires active original query checkpoint"))?()
    }
    /// The SAME active query context must observe each actual body demand.
    /// This stack callback confers no source owner and cannot replace syntax.
    pub(crate) fn with_body_borrower(mut self,borrower:&'a dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>)->Self{self.body_borrower=Some(borrower);self}
    pub(crate) fn parse_body(&self,ordinal:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,dm_tree::frontend::BodySyntaxFailure>{
        use dm_tree::frontend::BodySyntaxFailure;
        self.require().map_err(|error|BodySyntaxFailure::Operational(std::io::Error::new(if self.budget.denied(){std::io::ErrorKind::OutOfMemory}else{std::io::ErrorKind::InvalidData},error)))?;
        let borrower=self.body_borrower.ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"reactive body demand requires active original query observation")))?;
        self.inputs.archive().parse_checked_using(ordinal,borrower)
    }
    pub(crate) fn capture(raw:&'a CapturedRawPolicy,inputs:&'a PolicyInputs,budget:&'a Arc<Budget>)->Result<Self,String>{
        charge(budget,raw.tree.files.len().checked_mul(512).and_then(|n|n.checked_add(4096)))?;
        raw.validate_current_raw_roster(inputs)?;
        let tree=inputs.archive().tree();
        let profile=tree.checker_builtin_profile().ok_or("reactive original source lacks exact builtin profile")?;
        tree.validate_checker_builtin_profile(profile).map_err(|e|format!("reactive source profile: {e:?}"))?;
        let order=crate::captured_sparse_slots::captured_order(raw,inputs,budget)?;
        Ok(Self{raw:Some(raw),raw_pages:None,native_root:None,inputs,budget,order:ReadOrder::Owned(order),checkpoint:None,body_borrower:None})
    }
    /// Original-native-only semantic source loan. PolicyInputs is the existing
    /// private captured archive/mapping producer; root is diagnostic formatting
    /// only. Fresh evidence/config/current-owner checks remain the endpoint's
    /// responsibility. No raw roster, marker table, path map or body is built.
    pub(crate) fn native(inputs:&'a PolicyInputs,root:&'a Path,budget:&'a Arc<Budget>)->Result<Self,String>{
        budget.require()?;if !root.is_absolute(){return Err("native reactive diagnostic root must be absolute".into())}let tree=inputs.archive().tree();let profile=tree.checker_builtin_profile().ok_or("reactive original source lacks exact builtin profile")?;let proof=tree.validated_checker_profile(profile).map_err(|e|format!("reactive source profile: {e:?}"))?;Self::native_validated(inputs,root,budget,&proof,profile)
    }
    pub(crate) fn native_validated(inputs:&'a PolicyInputs,root:&'a Path,budget:&'a Arc<Budget>,proof:&dm_tree::checker_builtins::ValidatedCheckerProfile<'_>,profile:dm_ir::PackedU128)->Result<Self,String>{
        budget.require()?;if !root.is_absolute(){return Err("native reactive diagnostic root must be absolute".into())}proof.require(inputs.archive().tree(),profile).map_err(|e|format!("reactive source profile: {e:?}"))?;
        Ok(Self{raw:None,raw_pages:None,native_root:Some(root),inputs,budget,order:ReadOrder::Owned(HashMap::new()),checkpoint:None,body_borrower:None})
    }

    /// Policy-only page provider. This does NOT prove full raw coverage; the
    /// actual host must consume its exhausted traversal receipt before sealing.
    pub(crate) fn with_raw_policy_pages(mut self,pages:&'a dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&'a HashMap<String,usize>)->Self{self.raw_pages=Some(pages);self.order=ReadOrder::Borrowed(order);self}
    pub(crate) fn with_policy_files(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,crate::reactive_reads_native::Failure>)->Result<bool,crate::reactive_reads_native::Failure>{
        use crate::reactive_reads_native::Failure;
        self.checkpoint()?;self.require()?;
        let pending=(||{
            if let Some(pages)=self.raw_pages{return pages.for_each(visit)}
            for file in self.raw()?.tree.files.iter().filter(|file|crate::tree::CODE_DM.matches(file)){
                self.checkpoint()?;self.require()?;let next=visit(&file.rel,crate::captured_raw_file::RawPolicyViews::from_source(file))?;file.require_view_budget().map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;if !next{return Ok(false)}
            }
            Ok(true)
        })();
        if matches!(&pending,Err(Failure::Operational(_))){return pending}
        self.checkpoint()?;self.require()?;pending
    }

    fn raw(&self)->Result<&'a CapturedRawPolicy,String>{self.raw.ok_or_else(||"raw marker policy requires genuine captured raw roster".into())}



    fn relative_file(&self,path:&Path)->Result<Cow<'a,str>,String>{
        let file=self.file(path)?;
        if let Some(raw)=self.raw{
            for raw in &raw.tree.files{
                charge(self.budget,raw.abs.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)))?;
                let current=self.inputs.file(&raw.abs).ok_or("reactive declaration raw source absent")?;
                if std::ptr::eq(current,file){return Ok(Cow::Borrowed(&raw.rel))}
            }
            return Err("reactive declaration lacks exact original raw provider".into())
        }
        let root=self.native_root.ok_or("native reactive diagnostic root absent")?;
        // Only AFTER the original issuer resolves to the same authenticated
        // compiled PolicyFile, compare equivalent filesystem prefixes for
        // formatting. Provider keys/membership are unchanged. The existing
        // reservation covers both comparison paths and the old slash/dot fold.
        charge(self.budget,file.path().as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(4096)))?;
        let relative=dm_preprocess::regions::relative_filesystem_path(file.path(),root);
        Ok(Cow::Owned(match relative{Some(relative)=>crate::util::rel_slash(&relative,Path::new("")),None=>crate::util::rel_slash(file.path(),root)}))
    }
    pub(crate) fn site(&self,ordinal:usize,offset:usize)->Result<(String,u32),String>{
        let line=self.line_at(offset)?;self.site_line(ordinal,line)
    }
    pub(crate) fn line_at(&self,offset:usize)->Result<u32,String>{
        self.require()?;let point=self.inputs.archive().source_mapping().original_policy_line(offset)?;
        u32::try_from(point.line).map_err(|_|"reactive source site line overflow".into())
    }
    pub(crate) fn site_line(&self,ordinal:usize,line:u32)->Result<(String,u32),String>{
        self.require()?;let archive=self.inputs.archive();
        if self.raw.is_some(){let widest=self.inputs.files().map(|f|f.path().as_os_str().len()).max().unwrap_or(0);
        charge(self.budget,widest.checked_mul(32).and_then(|n|n.checked_add(2048)))?;}
        let occurrence=archive.occurrences().get(ordinal).ok_or("reactive source site body absent")?;
        let header=archive.callable_header_policy_line(occurrence.member)?;
        // The current proc's original issuer file, with the existing term line.
        let relative=self.relative_file(&header.path)?;
        if matches!(&relative,Cow::Borrowed(_)){charge(self.budget,relative.len().checked_mul(4).and_then(|n|n.checked_add(256)))?;}
        Ok((relative.into_owned(),line))
    }

    pub(crate) fn raw_width_checked(&self)->Result<usize,crate::reactive_reads_native::Failure>{
        use crate::reactive_reads_native::Failure;let mut total=0usize;
        if !self.with_policy_files(&mut|_,views|{self.checkpoint()?;total=total.checked_add(views.raw()?.len()).ok_or_else(||{self.budget.deny();Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original raw policy width overflow"))})?;Ok(true)})?{return Err("original raw policy width traversal incomplete".into())}Ok(total)
    }
    pub(crate) fn marker_rows_checked(&self,checkpoint:&mut dyn FnMut()->std::io::Result<()>)->Result<crate::captured_marker_rows::Rows<'a>,crate::reactive_reads_native::Failure>{self.policy_marker_rows(false,false,false,checkpoint)}
    fn policy_marker_rows(&self,entries:bool,capabilities:bool,runtime:bool,checkpoint:&mut dyn FnMut()->std::io::Result<()>)->Result<crate::captured_marker_rows::Rows<'a>,crate::reactive_reads_native::Failure>{
        self.policy_marker_rows_named(&["READS_AS","PROC_SUMMARY","READ_LOOKUP","CAPABILITY_TYPE","CAPABILITY_DEF","cap_keys","SYSTEM_ACCESSOR","READS_FROM","CAPABILITIES","STAT"],entries,capabilities,runtime,checkpoint)
    }
    fn policy_marker_rows_named(&self,names:&[&str],entries:bool,capabilities:bool,runtime:bool,checkpoint:&mut dyn FnMut()->std::io::Result<()>)->Result<crate::captured_marker_rows::Rows<'a>,crate::reactive_reads_native::Failure>{
        crate::reactive_raw_policy_pages::collect_marker_rows(|visit|self.with_policy_files(visit),&self.order,self.budget,names,entries,capabilities,runtime,checkpoint,&||self.require().map_err(crate::reactive_reads_native::Failure::from))
    }
    pub(crate) fn raw_metadata_checked(&self,checkpoint:&mut dyn FnMut()->std::io::Result<()>,emit:&mut dyn FnMut(&str,crate::raw_reactive_metadata_policy::Event<'_>)->Result<(),crate::reactive_reads_native::Failure>)->Result<(),crate::reactive_reads_native::Failure>{
        let completed=self.with_policy_files(&mut|relative,views|{for line in views.marker()?.split('\n'){checkpoint()?;self.require()?;crate::raw_reactive_metadata_policy::visit_line(line,|event|emit(relative,event))?;}Ok(true)})?;
        if !completed{return Err("original raw metadata traversal incomplete".into())}checkpoint()?;self.require()?;Ok(())
    }

    pub(crate) fn raw_width(&self)->Result<usize,String>{
        let raw=self.raw()?;raw.tree.files.iter().try_fold(0usize,|n,f|n.checked_add(f.text().len())).ok_or_else(||{self.budget.deny();"reactive raw source width overflow".into()})
    }
    pub(crate) fn budget(&self)->&Arc<Budget>{self.budget}
    pub(crate) fn marker_rows(&self,checkpoint:&mut impl FnMut()->Result<(),String>)->Result<crate::captured_marker_rows::Rows<'a>,String>{
        crate::captured_marker_rows::collect(self.raw()?,&self.order,self.budget,&[
            "READS_AS","PROC_SUMMARY","READ_LOOKUP","CAPABILITY_TYPE","CAPABILITY_DEF","cap_keys","SYSTEM_ACCESSOR","READS_FROM","CAPABILITIES","STAT",
        ],false,checkpoint)
    }

    /// DATA-only original file loans for Plans metadata. Finite capture may
    /// contain compiled reader definitions outside CODE_DM; code eligibility is
    /// computed by the SAME existing selector, never supplied by the caller.
    /// Page providers remain CODE-only; an absent required reader is refused by
    /// the collector then requires an exact original callable-file loan.
    pub(crate) fn with_plan_metadata_files(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>,bool)->Result<bool,crate::reactive_reads_native::Failure>)->Result<bool,crate::reactive_reads_native::Failure>{
      if self.raw_pages.is_some(){return self.with_policy_files(&mut|relative,views|visit(relative,views,true))}
      use crate::reactive_reads_native::Failure;self.checkpoint()?;self.require()?;let pending=(||{for file in &self.raw()?.tree.files{self.checkpoint()?;self.require()?;let next=visit(&file.rel,crate::captured_raw_file::RawPolicyViews::from_source(file),crate::tree::CODE_DM.matches(file))?;file.require_view_budget().map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;if !next{return Ok(false)}}Ok(true)})();if matches!(&pending,Err(Failure::Operational(_))){return pending}self.checkpoint()?;self.require()?;pending
    }

    /// Required callable-source DATA remains distinct from CODE coverage.
    pub(crate) fn with_plan_reader_file(&self,ordinal:usize,name:&str,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<(),crate::reactive_reads_native::Failure>)->Result<(),crate::reactive_reads_native::Failure>{
      use crate::reactive_reads_native::Failure;self.checkpoint()?;self.require()?;let pages=self.raw_pages.ok_or_else(||Failure::Unsupported("required original Plans reader file unavailable".into()))?;let pending=pages.with_callable_file(ordinal,name,visit);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.budget.require().map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;self.checkpoint()?;self.require()?;pending
    }
    /// Borrow authenticated RAW-policy code views only. These include inactive
    /// text and cannot issue compiled BodySyntax/declaration/source receipts.
    pub(crate) fn with_reaction_code(&self,hint:&str,mut visit:impl FnMut(&str,&crate::tree::View)->Result<bool,crate::reactive_reads_native::Failure>)->Result<(),crate::reactive_reads_native::Failure>{
        // Each callback is local to ONE actual page/file loan. Unique reaction
        // summaries own only identifiers/coords before another lookup begins.
        self.with_policy_files(&mut|relative,views|{if !views.raw()?.contains(hint){return Ok(true)}visit(relative,views.code()?)})?;Ok(())
    }

    /// Local raw-policy procedure loan. Body text cannot escape this callback.
    pub(crate) fn with_raw_procedures(&self,selector:crate::reactive_reaction_native::ProcedureSelector<'_>,visit:&mut dyn FnMut(crate::reactive_reaction_policy::ProcedureKey<'_>,crate::reactive_reaction_policy::Procedure<'_>)->Result<bool,crate::reactive_reads_native::Failure>)->Result<(),crate::reactive_reads_native::Failure>{crate::reactive_reaction_native::visit_procedures(self,selector,visit)}

    /// Original Decls define roster through the SAME marker-text header policy.
    /// Entries are not retained here; this is policy data, never source authority.
    pub(crate) fn dependency_defines(&self)->Result<std::collections::BTreeSet<String>,crate::reactive_reads_native::Failure>{crate::reactive_global_source::Source::dependency_defines(self)}

    /// Full dependency declarations use the SAME first-statement projectors as
    /// legacy Decls; no body syntax demand or source acquisition occurs here.
    pub(crate) fn dependency_marker_rows(&self)->Result<crate::captured_marker_rows::Rows<'a>,crate::reactive_reads_native::Failure>{self.policy_marker_rows(true,true,true,&mut||self.checkpoint())}
    /// Exact Plans declaration families, including STATE_GRAPH reader keys.
    /// The dependency producer keeps its existing family selection unchanged.
    pub(crate) fn plans_marker_rows(&self)->Result<crate::captured_marker_rows::Rows<'a>,crate::reactive_reads_native::Failure>{self.policy_marker_rows_named(&["CAPABILITIES","CAPABILITY_DEF","CAPABILITY_TYPE","STATE_GRAPH","STAT"],true,true,true,&mut||self.checkpoint())}

    pub(crate) fn raw_metadata<E:From<String>>(&self,checkpoint:impl FnMut()->Result<(),E>,mut emit:impl FnMut(crate::raw_reactive_metadata_policy::Event<'_>)->Result<(),E>)->Result<(),E>{
        self.raw_metadata_with_file(checkpoint,|_,event|emit(event))
    }
    pub(crate) fn raw_metadata_with_file<E:From<String>>(&self,mut checkpoint:impl FnMut()->Result<(),E>,mut emit:impl FnMut(&str,crate::raw_reactive_metadata_policy::Event<'_>)->Result<(),E>)->Result<(),E>{
        self.require()?;
        for file in self.raw()?.tree.files.iter().filter(|file|crate::tree::CODE_DM.matches(file)){
            checkpoint()?;let marker=file.marker();self.require()?;
            for line in marker.as_str().split('\n'){
                checkpoint()?;crate::raw_reactive_metadata_policy::visit_line(line,|event|emit(&file.rel,event))?;
            }
        }
        checkpoint()?;self.require().map_err(E::from)
    }
    pub(crate) fn parent_type(&self,path:&str)->Result<Option<&'a str>,String>{
        self.require()?;let tree=self.inputs.archive().tree();
        let Some(owner)=tree.lookup_type(SymbolId::of(path))else{
            let profile=tree.checker_builtin_profile().ok_or("reactive parent profile absent")?;
            if tree.checker_source_type_presence(profile,path).map_err(|e|format!("{e:?}"))?{return Err("reactive positive type has no original parent graph projection".into());}
            return Ok(None)
        };
        let Some(parent)=tree.parent(owner)else{return Ok(None)};
        let parent=tree.type_node(parent).and_then(|node|tree.symbols().text(node.path)).ok_or("reactive parent original spelling absent")?;
        Ok(Some(parent))
    }
    pub(crate) fn own_callable_exists(&self,owner:&str,name:&str)->Result<bool,String>{
        self.require()?;let tree=self.inputs.archive().tree();let profile=tree.checker_builtin_profile().ok_or("reactive own callable profile absent")?;
        if !tree.checker_source_type_presence(profile,owner).map_err(|e|format!("{e:?}"))?{return Ok(false);}
        let owner_symbol=SymbolId::of(owner);let name=SymbolId::of(name);
        let Some(owner_id)=tree.lookup_type(owner_symbol)else{return Err("reactive own callable type presence differs from original graph".into())};
        let node=tree.type_node(owner_id).ok_or("reactive own callable owner absent")?;
        for member in node.members.iter(){
            let member=tree.member(*member).ok_or("reactive original owner callable roster member absent")?;
            if member.name==name&&matches!(member.kind,MemberKind::Proc|MemberKind::Verb){return Ok(true);}
        }
        use dm_ir::{Resolver,ResolveQuery as Q,ResolvedMeaning as M};
        for verb in[false,true]{match Resolver::resolve(tree,Q::CheckerBuiltinProc{profile,owner:owner_symbol,name,verb}){
            M::Missing=>(),M::Member{owner,data,..}=>{if data.procedure.is_none()||data.inherited_opaque.is_some(){return Err("reactive own builtin callable unissued".into());}if owner==owner_symbol{return Ok(true);}},
            _=>return Err("reactive own builtin callable presence unissued".into()),
        }}
        Ok(false)
    }
    pub(crate) fn require(&self)->Result<(),String>{
        self.budget.require()?;
        if let Some(actual)=self.raw.and_then(|raw|raw.tree.captured_violation()){self.budget.deny();return Err(actual);}
        Ok(())
    }
    fn file(&self,path:&Path)->Result<&'a dm_analysis::policy_inputs::PolicyFile,String>{
        if let Some(file)=self.inputs.file_exact(path){return if file.is_compiled()&&file.role()==PolicyRole::DmSource{Ok(file)}else{Err("reactive original cursor has no captured compiled source".into())}}
        // EXACT existing canonical PolicyInputs lookup, not reconstructed raw
        // spelling. Canonical path scratch is admitted before entering lookup.
        charge(self.budget,path.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)))?;
        self.inputs.file(path).filter(|f|f.is_compiled()&&f.role()==PolicyRole::DmSource)
            .ok_or_else(||"reactive original cursor has no captured compiled source".into())
    }
    /// One original ancestry candidate without unused type/path projection.
    /// This stack-only borrowed result is not a source/cache receipt; current
    /// endpoint guards and the original profile/declaration issuer still bind it.
    pub(crate) fn declaring_owner(&self,receiver:&str,name:&str)->Result<Option<&'a str>,crate::reactive_reads_native::Failure>{
        use crate::reactive_reads_native::Failure;
        self.checkpoint().map_err(Failure::Operational)?;
        self.require()?;
        let pending=(||->Result<Option<&'a str>,String>{
            let tree=self.inputs.archive().tree();let profile=tree.checker_builtin_profile().ok_or("reactive original source profile absent")?;
            if !tree.checker_source_type_presence(profile,receiver).map_err(|e|format!("{e:?}"))?{return Ok(None)}
            let Some(fact)=checker_variable_facts::variable_original(tree,profile,SymbolId::of(receiver),SymbolId::of(name))?else{return Ok(None)};
            // Defer the general lookup's implicit root fallback until the caller
            // reaches the actual root in its original parent chain. This is a
            // per-level candidate, not the complete Sem::var_owner walk.
            if receiver!="/"&&fact.owner==SymbolId::of("/"){return Ok(None)}
            Ok(Some(tree.symbols().text(fact.owner).ok_or("reactive original variable owner spelling absent")?))
        })();
        self.checkpoint().map_err(Failure::Operational)?;
        self.require()?;
        pending.map_err(Failure::from)
    }
    /// The complete original declared-owner ancestry walk, including actual
    /// root inheritance. Each level authenticates a current issuer candidate;
    /// the general lookup's implicit root fallback is never accepted early.
    pub(crate) fn variable_declaring_owner(&self,receiver:&str,name:&str)->Result<Option<&'a str>,crate::reactive_reads_native::Failure>{
        use crate::reactive_reads_native::Failure;
        let attempt:Result<Option<&'a str>,Failure>=(||{
            let bound=self.inputs.archive().tree().types().len().checked_add(1).ok_or_else(||{self.budget.deny();Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original owner ancestry bound overflow"))})?;
            variable_declaring_owner_original(receiver,name,bound,&mut||{self.checkpoint().map_err(Failure::Operational)?;self.require()?;Ok(())},&mut|ty,name|self.declaring_owner(ty,name),&mut|ty|self.parent_type(ty).map_err(Failure::from))
        })();
        if matches!(&attempt,Err(Failure::Operational(_))){return attempt}
        if self.budget.denied(){return Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original owner ancestry admission refused")))}attempt
    }

    /// Only the unique lexical setter policy needs this code view. It is the
    /// SAME admitted raw-file transform, not another DM parse or source read.
    pub(crate) fn visit_setter_call_files(&self,mut emit:impl FnMut(&str,&str,&str)->Result<(),crate::reactive_reads_native::Failure>)->Result<(),crate::reactive_reads_native::Failure>{
        let completed=self.with_policy_files(&mut|relative,views|{let raw=views.raw()?;if !crate::auto_setter_calls_policy::wants_file(relative,raw){return Ok(true)}emit(relative,raw,&views.code()?.text)?;Ok(true)})?;
        if !completed{return Err("original setter-call traversal incomplete".into())}self.checkpoint()?;self.require()?;Ok(())
    }

    /// Original selected declaration facts. Source properties use the original
    /// declaration issuer, not runtime normalized type hints or inferred values.
    pub(crate) fn variable(&self,receiver:&str,name:&str)->Result<Option<ReadVariable<'a>>,String>{self.variable_projected(receiver,name,VariableProjection::Full)}
    /// SAME original declaration type meaning without unused diagnostic file text.
    pub(crate) fn variable_type(&self,receiver:&str,name:&str)->Result<Option<String>,String>{Ok(self.variable_projected(receiver,name,VariableProjection::TypeOnly)?.map(|value|value.declared))}
    fn variable_projected(&self,receiver:&str,name:&str,projection:VariableProjection)->Result<Option<ReadVariable<'a>>,String>{
        self.require()?;
        let archive=self.inputs.archive();let tree=archive.tree();
        let profile=tree.checker_builtin_profile().ok_or("reactive original source profile absent")?;
        if !tree.checker_source_type_presence(profile,receiver).map_err(|e|format!("{e:?}"))?{return Ok(None);}
        let Some(fact)=checker_variable_facts::variable_original(tree,profile,SymbolId::of(receiver),SymbolId::of(name))? else{return Ok(None)};
        let owner=tree.symbols().text(fact.owner).ok_or("reactive original variable owner spelling absent")?;
        let mut definition_file=None;
        let (declared,flags)=if let Some(formal)=fact.formal{
            // The shared property projection allocates only from these SAME
            // original metadata type spellings: cleaned_type's Vec<&str>
            // contains at most one component per byte (geometric capacity <=2N),
            // plus joined output and the caller-owned copy. Definition-point
            // validation invokes that same projection once more sequentially.
            // 64B per original spelling byte covers both live pointer-vector
            // peaks and String copies on 64-bit hosts, without using whole-file
            // width per variable or inventing a copied declaration table.
            let width=[fact.metadata.declared_type,fact.metadata.list_element_type,fact.metadata.array.as_ref().and_then(|a|a.element_type)]
                .into_iter().flatten().try_fold(0usize,|n,id|tree.symbols().text(id).and_then(|s|n.checked_add(s.len())));
            charge(self.budget,width.and_then(|n|n.checked_mul(64)).and_then(|n|n.checked_add(4096)))?;
            archive.checker_variable_qualifiers(formal,profile)?;
            if matches!(projection,VariableProjection::Full){let point=archive.member_policy_line(formal)?;definition_file=Some(self.relative_file(&point.path)?);}
            let props=archive.checker_variable_properties(formal,profile)?;
            (props.declared_hint().unwrap_or("").to_owned(),fact.metadata.flags)
        }else{
            let declared=fact.metadata.declared_type.and_then(|id|tree.symbols().text(id)).unwrap_or("");
            let element=fact.metadata.list_element_type.and_then(|id|tree.symbols().text(id));
            charge(self.budget,declared.len().checked_add(element.map_or(0,str::len)).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(512)))?;
            let declared=match element{
                Some(element) if declared=="/list"=>format!("/list{element}"),
                Some(_)=>return Err("reactive original builtin list-element owner is inconsistent".into()),
                None=>declared.to_owned(),
            };
            (declared,fact.metadata.flags)
        };
        Ok(Some(ReadVariable{owner,declared,file:definition_file,is_static:flags&STATIC_FLAG!=0,is_const:flags&CONST_FLAG!=0,is_tmp:flags&TMP_FLAG!=0}))
    }

    /// Resolve using the SAME native source/profile policy already used by
    /// checker consumers. The transient answers contain only original Arc
    /// metadata and SymbolIds; no callable/type table is retained here.
    pub(crate) fn callable(&self,receiver:&str,name:&str)->Result<SelectedCallable<'a>,String>{self.callable_using(receiver,name,&mut||Ok(()))}
    pub(crate) fn callable_checked(&self,receiver:&str,name:&str)->Result<SelectedCallable<'a>,crate::reactive_reads_native::Failure>{
      use crate::reactive_reads_native::Failure;let mut checkpoint=||{self.budget.require().map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;self.checkpoint()?;Ok(())};let pending=self.callable_using(receiver,name,&mut checkpoint);if matches!(&pending,Err(Failure::Operational(_))){return pending}if self.budget.denied(){return Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original callable admission denied")))}checkpoint()?;pending
    }
    fn callable_using<E:From<String>+From<&'static str>>(&self,receiver:&str,name:&str,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<SelectedCallable<'a>,E>{
        self.require()?;checkpoint()?;
        let archive=self.inputs.archive();let tree=archive.tree();
        let profile=tree.checker_builtin_profile().ok_or("reactive callable profile absent")?;
        if !tree.checker_source_type_presence(profile,receiver).map_err(|e|format!("{e:?}"))?{return Ok(SelectedCallable::Missing)}
        // callable_any asks both kind-qualified source chains and ancestry.
        // Four answer-vector envelopes cover simultaneous old/new capacities;
        // metadata stays the actual original Arc and is not materialized.
        let rows=archive.callables().members().len();
        let row_bytes=std::mem::size_of::<ResolvedMeaning>().checked_mul(16);
        let ancestry_bytes=tree.types().len().checked_mul(std::mem::size_of::<SymbolId>()*16);
        charge(self.budget,row_bytes.and_then(|n|n.checked_mul(rows)).and_then(|n|n.checked_add(ancestry_bytes?)).and_then(|n|n.checked_add(8192)))?;
        match dm_analysis::checker_call_facts::callable_any_using(tree,tree,profile,SymbolId::of(receiver),SymbolId::of(name),checkpoint)?{
            dm_analysis::checker_call_facts::CallableFact::Source{identity,..}=>self.callable_identity_using(identity,checkpoint).map(SelectedCallable::Source),
            dm_analysis::checker_call_facts::CallableFact::CheckerBuiltin{..}=>Ok(SelectedCallable::Builtin),
            dm_analysis::checker_call_facts::CallableFact::Missing=>Ok(SelectedCallable::Missing),
        }
    }
    fn callable_identity(&self,identity:ProcedureIdentity)->Result<ReadCallable<'a>,String>{self.callable_identity_using(identity,&mut||Ok(()))}
    fn callable_identity_using<E:From<String>+From<&'static str>>(&self,identity:ProcedureIdentity,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<ReadCallable<'a>,E>{
        let archive=self.inputs.archive();let roster=archive.callables();let tree=archive.tree();let owner=tree.lookup_type(identity.owner).ok_or("reactive selected callable owner absent")?;let kind=if identity.verb{MemberKind::Verb}else{MemberKind::Proc};let mut current=tree.resolve(owner,identity.name,kind);let mut selected=None;
        // Existing immutable same-name previous links plus the existing roster's
        // member index replace a whole-body linear search; no new index is built.
        for _ in 0..=tree.members().len(){checkpoint()?;let Some(member)=current else{break};let node=tree.member(member).ok_or("reactive selected callable member absent")?;if node.owner!=owner||node.name!=identity.name||node.kind!=kind{break}if tree.member_occurrence(member)==Some(identity.occurrence){selected=Some(member);break}current=node.previous;}
        let member=selected.ok_or("reactive selected callable has no original source member")?;let ordinal=roster.ordinal(member).ok_or("reactive selected callable has no ORIGINAL body occurrence")?;if roster.identity(ordinal)!=Some(identity)||roster.identity_for_member(member)!=Some(identity){return Err("reactive selected callable original identity differs".into())}
        let occurrence=archive.occurrences().get(ordinal).ok_or("reactive selected callable occurrence absent")?;if occurrence.member!=member{return Err("reactive selected callable body/member index differs".into())}let node=tree.member(member).ok_or("reactive selected callable member absent")?;let owner=tree.type_node(node.owner).and_then(|node|tree.symbols().text(node.path)).ok_or("reactive selected callable owner spelling absent")?;let name=tree.symbols().text(node.name).ok_or("reactive selected callable name absent")?;
        // Certified current-header file/line shares the existing source Path Arc;
        // no byte origin is requested and original display-line semantics stay.
        let headers=archive.callable_header_source();let point=headers.reported_policy_line(member)?;let file=self.file(point.path.as_path())?;let header=file.analyze_display_line(point.line).map_err(|error|E::from(error.to_string()))?;checkpoint()?;Ok(ReadCallable{owner,name,ordinal,member,file,header})
    }
    /// Original predecessor, including same-owner replacement versions. This
    /// selects an existing roster occurrence; it never normalizes a signature.
    /// Borrowed source-type roster coordination for the ORIGINAL override union.
    /// No retained dispatch index; latest own definition per subtype, sorted by
    /// original path exactly as old overrides(), then original callable lookup.
    pub(crate) fn visit_overrides<E:From<String>+From<&'static str>>(&self,receiver:&str,name:&str,mut checkpoint:impl FnMut()->Result<(),E>,mut emit:impl FnMut(ReadCallable<'a>)->Result<(),E>)->Result<(),E>{
        self.require()?;let tree=self.inputs.archive().tree();
        charge(self.budget,tree.types().len().checked_mul(std::mem::size_of::<&str>()*4).and_then(|n|n.checked_add(1024)))?;
        let mut owners=Vec::new();owners.try_reserve_exact(tree.types().len()).map_err(|_|{self.budget.deny();E::from("reactive override roster allocation refused")})?;
        for node in tree.types(){
            checkpoint()?;let owner=tree.symbols().text(node.path).ok_or("reactive override type spelling absent")?;
            if subtype_original(tree,owner,receiver,&mut checkpoint,&mut|child|{let profile=tree.checker_builtin_profile().ok_or("reactive subtype profile absent")?;tree.checker_source_type_presence(profile,child).map_err(|error|E::from(format!("{error:?}")))})?&&self.own_callable_exists(owner,name)?{owners.push(owner)}
        }
        owners.sort_unstable();owners.dedup();
        for owner in owners{checkpoint()?;if let SelectedCallable::Source(callable)=self.callable_using(owner,name,&mut checkpoint)?{emit(callable)?;}}
        checkpoint()?;self.require().map_err(E::from)
    }
    pub(crate) fn parent_callable(&self,ordinal:usize)->Result<Option<ReadCallable<'a>>,String>{
        let archive=self.inputs.archive();let tree=archive.tree();
        let body=archive.occurrences().get(ordinal).ok_or("reactive parent caller occurrence absent")?;
        let profile=tree.checker_builtin_profile().ok_or("reactive parent profile absent")?;
        match dm_analysis::checks_parent_call::source_predecessor_in_profile(tree,body.member,tree,profile)?{
            dm_analysis::checks_parent_call::SourcePredecessorProjection::Source(identity)=>self.callable_identity(identity).map(Some),
            dm_analysis::checks_parent_call::SourcePredecessorProjection::NoParent|dm_analysis::checks_parent_call::SourcePredecessorProjection::BuiltinBoundary=>Ok(None),
        }
    }
    pub(crate) fn parent_callable_checked(&self,ordinal:usize)->Result<Option<ReadCallable<'a>>,crate::reactive_reads_native::Failure>{
      use crate::reactive_reads_native::Failure;let mut checkpoint=||{self.budget.require().map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;self.checkpoint()?;Ok(())};let pending=(||{checkpoint()?;self.require()?;let archive=self.inputs.archive();let tree=archive.tree();let body=archive.occurrences().get(ordinal).ok_or("reactive parent caller occurrence absent")?;let identity=archive.callables().identity(ordinal).ok_or("reactive parent original identity absent")?;if archive.callables().identity_for_member(body.member)!=Some(identity){return Err("reactive parent original body/member identity differs".into())}let profile=tree.checker_builtin_profile().ok_or("reactive parent profile absent")?;
      let rows=archive.callables().members().len();let width=rows.checked_mul(std::mem::size_of::<ResolvedMeaning>()).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(tree.types().len().checked_mul(std::mem::size_of::<SymbolId>()*16)?)).and_then(|n|n.checked_add(8192));charge(self.budget,width)?;
      match dm_analysis::checks_parent_call::source_value_predecessor_using(tree,body.member,tree,profile,&mut checkpoint)?{dm_analysis::checks_parent_call::SourcePredecessorProjection::Source(identity)=>self.callable_identity_using(identity,&mut checkpoint).map(Some),dm_analysis::checks_parent_call::SourcePredecessorProjection::NoParent|dm_analysis::checks_parent_call::SourcePredecessorProjection::BuiltinBoundary=>Ok(None)}
      })();if matches!(&pending,Err(Failure::Operational(_))){return pending}if self.budget.denied(){return Err(Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original predecessor admission denied")))}checkpoint()?;pending
    }
    /// Bounded allocation-free traversal of the SAME original hierarchy. A
    /// missing cache is not absence; no ancestry table or guessed prefix rule.
    pub(crate) fn is_subtype(&self,child:&str,parent:&str)->Result<bool,String>{
        self.require()?;let tree=self.inputs.archive().tree();
        subtype_original(tree,child,parent,&mut||Ok(()),&mut|child|{let profile=tree.checker_builtin_profile().ok_or("reactive subtype profile absent")?;tree.checker_source_type_presence(profile,child).map_err(|e|format!("{e:?}"))})
    }

    pub(crate) fn is_subtype_checked(&self,child:&str,parent:&str)->Result<bool,crate::reactive_reads_native::Failure>{
      use crate::reactive_reads_native::Failure;self.budget.require().map_err(|m|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;self.require()?;let tree=self.inputs.archive().tree();let mut checkpoint=||{self.budget.require().map_err(|m|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,m)))?;self.checkpoint()?;Ok(())};subtype_original(tree,child,parent,&mut checkpoint,&mut|child|{let profile=tree.checker_builtin_profile().ok_or("reactive subtype profile absent")?;tree.checker_source_type_presence(profile,child).map_err(|e|Failure::from(format!("{e:?}")))})
    }

    /// SAME original definition proximity used by the unique annotation policy.
    /// Only two scalar tuples survive the scan; no def_index/model is rebuilt.
    /// Match only the SAME existing compiled roster. Equivalent drive prefixes
    /// affect diagnostic file selection, never provider keys or source authority.
    /// A fallback is one linear borrowed roster walk, followed by the existing
    /// declaration walk; no path index/model is constructed.
    fn relative_compiled_file_using<E:From<String>+From<&'static str>>(&self,relative:&str,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Option<&'a dm_analysis::policy_inputs::PolicyFile>,E>{
        checkpoint()?;self.require()?;let root=self.native_root.ok_or("reactive annotation diagnostic root absent")?;
        charge(self.budget,root.as_os_str().len().checked_add(relative.len()).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(1024)))?;
        let path=root.join(relative);if let Some(file)=self.inputs.file(&path).filter(|file|file.is_compiled()&&file.role()==PolicyRole::DmSource){return Ok(Some(file))}
        let mut selected:Option<&'a dm_analysis::policy_inputs::PolicyFile>=None;let mut funded=0usize;
        for file in self.inputs.files(){checkpoint()?;self.require()?;if !file.is_compiled()||file.role()!=PolicyRole::DmSource{continue}
            let peak=file.path().as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(64)).and_then(|n|n.checked_add(4096)).ok_or_else(||{self.budget.deny();String::from("reactive relative source comparison admission overflow")})?;
            if peak>funded{charge(self.budget,Some(peak-funded))?;funded=peak;}
            let candidate=dm_preprocess::regions::relative_filesystem_path(file.path(),root);
            if candidate.as_deref()!=Some(Path::new(relative)){continue}
            if selected.is_some_and(|prior|!std::ptr::eq(prior,file)){return Err("reactive relative compiled source is ambiguous".into())}selected=Some(file);
        }checkpoint()?;Ok(selected)
    }

    pub(crate) fn definition_neighbors<E:From<String>+From<&'static str>>(&self,rel:&str,line:u32,mut checkpoint:impl FnMut()->Result<(),E>)->Result<(Option<(usize,&'a str,&'a str)>,Option<(usize,&'a str,&'a str)>),E>{
        self.require()?;if self.raw.is_none()&&self.raw_pages.is_none(){return Err("reactive annotation source requires genuine raw policy loans".into())}let archive=self.inputs.archive();
        let current=if let Some(raw)=self.raw{
            let raw=raw.tree.get(rel).ok_or("reactive annotation source is not in current raw roster")?;
            charge(self.budget,raw.abs.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)))?;
            self.inputs.file(&raw.abs).ok_or("reactive annotation current raw provider missing")?
        }else{
            // A lexical page may honestly contain uncompiled code. It has no
            // semantic definition neighbor. Compiled metadata is selected only
            // from the existing actual current PolicyInputs file issuer.
            let Some(file)=self.relative_compiled_file_using(rel,&mut checkpoint)?else{checkpoint()?;return Ok((None,None))};file
        };
        let mut before=None;let mut after=None;
        self.visit_definition_points(&mut checkpoint,&mut|point|{if !std::ptr::eq(self.file(&point.path)?,current){return Ok(())}let item=(point.line,point.owner,point.name);if item.0<=line as usize{if before.is_none_or(|p|p<item){before=Some(item);}}else if after.is_none_or(|p|item<p){after=Some(item);}Ok(())})?;
        checkpoint()?;Ok((before,after))
    }
    /// Borrow actual ordered source definition points, without a second
    /// declaration index. Each authored skeleton owns its MemberId; the exact
    /// current occurrence ordinal selects the original compatibility cursor.
    pub(crate) fn visit_definition_points<E:From<String>+From<&'static str>>(&self,checkpoint:&mut impl FnMut()->Result<(),E>,emit:&mut impl FnMut(OriginalDefinitionPoint<'a>)->Result<(),E>)->Result<(),E>{
        self.require()?;let archive=self.inputs.archive();let tree=archive.tree();
        for(ordinal,occurrence)in archive.original_declaration_occurrences().source_order().iter().enumerate(){checkpoint()?;self.require()?;let Target::Member(member)=occurrence.target else{continue};let node=tree.member(member).ok_or("reactive definition member missing")?;let ordinal=dm_tree::OccurrenceId(u32::try_from(ordinal).map_err(|_|"reactive definition ordinal overflow")?);if archive.source_mapping().location_of(ordinal).is_none(){continue}
            let owner=tree.type_node(node.owner).and_then(|n|tree.symbols().text(n.path)).ok_or("reactive definition owner missing")?;let name=tree.symbols().text(node.name).ok_or("reactive definition name missing")?;
            let(path,line)=match node.kind{MemberKind::Var=>{if node.definition!=dm_tree::DefinitionMode::Declare{continue}let formal=tree.source_formal_variable_member(tree.type_node(node.owner).ok_or("reactive source owner missing")?.path,node.name).map_err(str::to_owned)?;if formal!=Some(member){continue}if node.metadata.inherited_opaque.is_some()||node.metadata.procedure.is_some(){return Err("checker original variable metadata opaque".into())}let cursor=archive.source_mapping().declaration_policy_compatibility_cursor(ordinal)?;(cursor.path,cursor.line)},MemberKind::Proc|MemberKind::Verb=>{let origin=archive.callable_header_policy_line(member)?;(origin.path,origin.line)}};
            emit(OriginalDefinitionPoint{member,ordinal,line,owner,name,path})?;
        }checkpoint()?;Ok(())
    }
    /// Unique proc_defs selection, without body demand or a copied index. The
    /// original opening token supplies the exact old raw-policy header line.
    pub(crate) fn visit_callables<E:From<String>+From<&'static str>>(&self,names:&[&str],checkpoint:impl FnMut()->Result<(),E>,visit:impl FnMut(ReadCallable<'a>)->Result<(),E>)->Result<(),E>{self.visit_callables_inner(Some(names),checkpoint,visit)}
    pub(crate) fn visit_all_callables<E:From<String>+From<&'static str>>(&self,checkpoint:impl FnMut()->Result<(),E>,visit:impl FnMut(ReadCallable<'a>)->Result<(),E>)->Result<(),E>{self.visit_callables_inner(None,checkpoint,visit)}
    fn visit_callables_inner<E:From<String>+From<&'static str>>(&self,names:Option<&[&str]>,mut checkpoint:impl FnMut()->Result<(),E>,mut visit:impl FnMut(ReadCallable<'a>)->Result<(),E>)->Result<(),E>{
        self.require()?;let archive=self.inputs.archive();let tree=archive.tree();
        for target in tree.declarations(){
            checkpoint()?;self.budget.require()?;
            let Target::Member(member)=target else{continue};
            let node=tree.member(*member).ok_or("reactive original declaration member absent")?;
            if !matches!(node.kind,MemberKind::Proc|MemberKind::Verb){continue;}
            let name=tree.symbols().text(node.name).ok_or("reactive original callable spelling absent")?;
            if names.is_some_and(|names|!names.contains(&name)){continue;}
            let Some(ordinal)=archive.callables().ordinal(*member) else{continue};
            let occurrence=archive.occurrences().get(ordinal).ok_or("reactive original callable occurrence absent")?;
            if occurrence.member!=*member{return Err("reactive callable roster/original occurrence mismatch".into());}
            // Inherited/external/builtin no-body entries do not become fake
            // empty bodies. The issued archive roster is the body authority.
            let point=archive.callable_header_policy_line(*member)?;
            let file=self.file(&point.path)?;
            let header=file.analyze_display_line(point.line).map_err(|e|e.to_string())?;
            let owner=tree.type_node(node.owner).and_then(|n|tree.symbols().text(n.path)).ok_or("reactive original callable owner absent")?;
            visit(ReadCallable{owner,name,ordinal,member:*member,file,header})?;
        }
        checkpoint()?;self.require().map_err(E::from)
    }

pub(crate) fn visit_setter_definitions(&self,mut emit:impl FnMut(&str,&str)->Result<(),crate::reactive_reads_native::Failure>)->Result<(),crate::reactive_reads_native::Failure>{crate::reactive_global_source::Source::visit_setter_definitions(self,&mut emit)}
pub(crate) fn visit_own_declared_variables(&self,mut emit:impl FnMut(&str,&str)->Result<(),crate::reactive_reads_native::Failure>)->Result<(),crate::reactive_reads_native::Failure>{crate::reactive_global_source::Source::visit_own_declared_variables(self,&mut emit)}

    pub(crate) fn with_original_header_line(&self,member:dm_tree::MemberId,consume:&mut dyn FnMut(&str,usize,&str)->Result<(),crate::reactive_reads_native::Failure>)->Result<(),crate::reactive_reads_native::Failure>{
        use crate::reactive_reads_native::Failure;
        self.checkpoint()?;self.require()?;
        if let Some(pages)=self.raw_pages{
         let archive=self.inputs.archive();let node=archive.tree().member(member).ok_or("setter header original member absent")?;let name=archive.tree().symbols().text(node.name).ok_or("setter header original name absent")?;
         let pending=pages.with_setter_header(member,name,consume);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.budget.require().map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;self.checkpoint()?;self.require()?;return pending
        }

        let archive=self.inputs.archive();let point=archive.callable_header_policy_line(member)?;let relative=self.relative_file(&point.path)?;let file=self.file(&point.path)?;let display=file.analyze_display_line(point.line).map_err(|e|e.to_string())?;let raw=file.view(dm_analysis::policy_inputs::TextView::AnalyzeRaw).map_err(|e|e.to_string())?;let line=raw.as_str().lines().nth(display.saturating_sub(1)).ok_or("setter raw source line absent")?;consume(&relative,display,line)
    }

}

#[cfg(test)]mod page_order_tests{use super::*;
 #[test]fn page_order_is_the_same_original_map_not_a_second_table(){let original=ReadOrder::Owned(HashMap::from([("code/probe.dm".to_owned(),0)]));let borrowed=ReadOrder::Borrowed(&original);assert!(std::ptr::eq(&*original,&*borrowed));assert_eq!(borrowed.get("code/probe.dm"),Some(&0));}
}

#[cfg(test)]
#[path="../../dmb/crates/dm-analysis/examples/support/reference_hierarchy.rs"]
mod native_source_test_profile;
#[cfg(test)]mod native_source_tests{
 use super::*;use std::{collections::BTreeMap,path::PathBuf};
 struct Files{rows:BTreeMap<PathBuf,dm_preprocess::AcquiredSource>,reads:std::cell::Cell<usize>}
 impl dm_preprocess::SourceProvider for Files{
  fn read(&self,_:&Path)->Result<String,String>{panic!("must use original acquisition")}
  fn acquired_source(&self,p:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{self.reads.set(self.reads.get()+1);Ok(self.rows.get(&dm_preprocess::regions::canonical_path(p)).cloned())}
  fn source_acquisition(&self,p:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.rows.get(&dm_preprocess::regions::canonical_path(p)).filter(|source|source.lease().source_text().same_view(text)).cloned()}
 }
 #[test]fn native_only_metadata_borrows_original_compiled_roster_without_raw_views_or_file_cap(){
  let root=std::env::current_dir().unwrap().join("native-only-read-source");let mut rows=BTreeMap::new();let mut manifest=String::new();
  for i in 0..129{let relative=format!("code/part_{i}.dm");manifest.push_str(&format!("#include \"{relative}\"\n"));let text=if i==0{"var/global/only_global=0\n/datum/probe\n    var/value=1\n    var/charge=1\n    proc/leaf()\n        return value\n/datum/probe\n    proc/set_audit(v)\n        return\n/datum/probe/child\n    value=2\n    var/own_charge=3\n    set_audit(v)\n        return\n"}else{"// actual acquired include\n"};rows.insert(dm_preprocess::regions::canonical_path(&root.join(relative)),dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()));}
  rows.insert(dm_preprocess::regions::canonical_path(&root.join("deepquarry.dme")),dm_preprocess::AcquiredSource::from_original_bytes(manifest.into_bytes(),()));let provider=Files{rows,reads:std::cell::Cell::new(0)};
  let executor=dm_exec::BuildExecutor::new(1).unwrap();let seed=native_source_test_profile::seed();let front=dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(&root.join("deepquarry.dme"),&provider,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(&seed),observer:None},None,&executor,None,true).unwrap();
  let inputs=PolicyInputs::capture(&front,std::iter::empty()).unwrap();assert!(inputs.files().filter(|f|f.is_compiled()).count()>128);assert!(inputs.files().all(|f|f.view(dm_analysis::policy_inputs::TextView::AnalyzeRaw).is_err()));
  let budget=Budget::new(8*1024*1024).unwrap();let before=provider.reads.get();let checkpoint=||Ok(());let source=ReadSource::native(&inputs,&root,&budget).unwrap().with_checkpoint(&checkpoint);
  let variable=source.variable("/datum/probe","value").unwrap().unwrap();assert_eq!(variable.owner,"/datum/probe");assert_eq!(variable.file.as_deref(),Some("code/part_0.dm"));assert!(matches!(variable.file,Some(Cow::Owned(_))));

  assert_eq!(source.variable("/datum/probe","only_global").unwrap().unwrap().owner,"/","general checker lookup intentionally permits actual global fallback");
  assert_eq!(source.declaring_owner("/datum/probe","only_global").unwrap(),None,"implicit root fallback is deferred until the ancestry walker reaches root");
  assert_eq!(source.declaring_owner("/","only_global").unwrap(),Some("/"),"actual global receiver retains its own original declaration");
  assert_eq!(source.variable_declaring_owner("/datum/probe","only_global").unwrap(),Some("/"),"actual root is an original ancestor, as frozen Sem::var_owner confirms");assert_eq!(source.variable_declaring_owner("/datum/probe","absent").unwrap(),None);
  let budget_before=budget.used();assert_eq!(source.declaring_owner("/datum/probe","value").unwrap(),Some(variable.owner));assert_eq!(source.variable_declaring_owner("/datum/probe","value").unwrap(),Some(variable.owner));assert_eq!(budget.used(),budget_before,"borrowed owner requires no unused type/file allocation reservation");
  let fail=||Err(std::io::Error::from_raw_os_error(1450));let refused=ReadSource::native(&inputs,&root,&budget).unwrap().with_checkpoint(&fail).declaring_owner("/datum/probe","value");assert!(matches!(refused,Err(crate::reactive_reads_native::Failure::Operational(ref error))if error.raw_os_error()==Some(1450)));
  let refused=ReadSource::native(&inputs,&root,&budget).unwrap().with_checkpoint(&fail).variable_declaring_owner("/datum/probe","only_global");assert!(matches!(refused,Err(crate::reactive_reads_native::Failure::Operational(ref error))if error.raw_os_error()==Some(1450)));
  assert_eq!(source.variable_declaring_owner("/datum/probe","value").unwrap(),Some(variable.owner),"same current original owner recovers with fresh operation control");
  let mut calls=0;source.visit_all_callables(||Ok::<_,String>(()),|call|{calls+=1;assert_eq!(source.site_line(call.ordinal,7)?,("code/part_0.dm".into(),7));Ok(())}).unwrap();assert_eq!(calls,3);
  assert!(source.raw_width().is_err());assert!(source.marker_rows(&mut||panic!("refuse before raw work")).is_err());
  let error=source.raw_metadata::<String>(||panic!("no raw callback"),|_|panic!("no invented metadata"));assert!(error.is_err());assert!(source.definition_neighbors::<String>("code/part_0.dm",1,||panic!("no raw annotation lookup")).is_err());
  let mut declared=std::collections::BTreeSet::new();source.visit_own_declared_variables(|owner,name|{declared.insert((owner.to_owned(),name.to_owned()));Ok(())}).unwrap();
  for pair in [("/","only_global"),("/datum/probe","charge"),("/datum/probe/child","own_charge")]{assert!(declared.contains(&(pair.0.into(),pair.1.into())),"actual own source formal must be enumerated: {pair:?}");}
  assert!(!declared.contains(&("/datum/probe/child".into(),"value".into())),"an override is not a new own declaration");
  assert!(declared.contains(&("/atom".into(),"name".into())),"real pinned builtin own declarations remain present");
  assert!(matches!(crate::auto_tracking_native::setter_defs(&source),Err(crate::reactive_reads_native::Failure::Unsupported(_))),"TRACKED-origin policy requires a genuine raw view; native-only metadata is not that receipt");
  let candidates=std::collections::BTreeSet::from([("/datum/probe".to_owned(),"charge".to_owned()),("/datum/probe".to_owned(),"value".to_owned())]);
  let decision=crate::auto_tracking_native::decide(&source,&HashMap::new(),&candidates,&[]).unwrap();
  assert_eq!(decision.tracked,vec![crate::auto_tracking_policy::Auto{ty:"/datum/probe".into(),var:"charge".into(),list:false}]);
  assert_eq!(decision.blocked,vec![("/datum/probe".into(),"value".into(),"a reserved name".into())]);
  let defs=HashMap::from([("set_charge".to_owned(),vec!["/datum/probe".to_owned()])]);
  let collision=crate::auto_tracking_native::decide(&source,&defs,&candidates,&[]).unwrap();assert!(collision.tracked.is_empty());assert_eq!(collision.blocked[0].2,"/datum/probe already defines set_charge()");
  let stopped=ReadSource::native(&inputs,&root,&budget).unwrap().with_checkpoint(&fail);
  let actual=crate::auto_tracking_native::decide(&stopped,&HashMap::new(),&candidates,&[]).err().expect("actual IO must refuse metadata decision");assert!(matches!(actual,crate::reactive_reads_native::Failure::Operational(ref e)if e.raw_os_error()==Some(1450)));
  assert_eq!(crate::auto_tracking_native::decide(&source,&HashMap::new(),&candidates,&[]).unwrap().tracked,decision.tracked,"same original source recovers after actual IO");
  let tiny=Budget::new(std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()).unwrap();let limited=ReadSource::native(&inputs,&root,&tiny).unwrap().with_checkpoint(&checkpoint);
  let refused=crate::auto_tracking_native::decide(&limited,&HashMap::new(),&candidates,&[]).err().expect("cold metadata allocation must refuse");assert!(matches!(refused,crate::reactive_reads_native::Failure::Operational(ref e)if e.kind()==std::io::ErrorKind::OutOfMemory));assert!(tiny.denied(),"actual metadata reservation must deny the same tiny budget; missing checkpoint is not quota evidence");
  // Pure original source coordinates grant no raw annotation/body role.
  let mut points=Vec::new();source.visit_definition_points(&mut||Ok::<_,String>(()),&mut|point|{points.push(point);Ok(())}).unwrap();
  assert!(points.iter().any(|p|p.owner=="/datum/probe"&&p.name=="value"));assert!(!points.iter().any(|p|p.owner=="/datum/probe/child"&&p.name=="value"));
  let tree=inputs.archive().tree();let profile=tree.checker_builtin_profile().unwrap();let proof=tree.validated_checker_profile(profile).unwrap();
  assert!(tree.checker_source_type_presence_validated(profile,"/datum/probe",&proof).unwrap());
  assert!(tree.checker_source_type_presence_validated(dm_ir::PackedU128::default(),"/datum/probe",&proof).is_err());
  let fact=dm_analysis::checker_variable_facts::variable_original_validated(tree,&proof,profile,dm_ir::SymbolId::of("/datum/probe"),dm_ir::SymbolId::of("value")).unwrap().unwrap();
  let formal=fact.formal.unwrap();let point=points.iter().find(|p|p.member==formal).unwrap();let archive=inputs.archive();
  let old=archive.checker_variable_properties(formal,profile).unwrap();let current=archive.checker_variable_properties_original_at(formal,point.ordinal,profile,&proof).unwrap();assert_eq!(current.declared_hint(),old.declared_hint());assert_eq!(archive.checker_variable_qualifiers_original_at(formal,point.ordinal,profile,&proof).unwrap(),archive.checker_variable_qualifiers(formal,profile).unwrap());
  let other=points.iter().find(|p|p.member!=formal).unwrap();assert!(archive.checker_variable_properties_original_at(formal,other.ordinal,profile,&proof).is_err());
  let mut refused=0;let failure=source.visit_definition_points(&mut||Err::<(),crate::reactive_reads_native::Failure>(crate::reactive_reads_native::Failure::Operational(std::io::Error::from_raw_os_error(1450))),&mut|_|{refused+=1;Ok(())});assert!(matches!(failure,Err(crate::reactive_reads_native::Failure::Operational(ref e))if e.raw_os_error()==Some(1450)));assert_eq!(refused,0);
  #[cfg(windows)]{
   // The original acquired PolicyFile stays unchanged; only the diagnostic
   // caller root uses an equivalent Windows verbatim drive prefix.
   let ordinary=dm_preprocess::regions::filesystem_comparison_key(&root);
   let verbatim=PathBuf::from(format!(r"\\?\{}",ordinary.display()));
   assert_ne!(ordinary,verbatim);
   let alternate=ReadSource::native(&inputs,&verbatim,&budget).unwrap().with_checkpoint(&checkpoint);
   assert_eq!(alternate.variable("/datum/probe","value").unwrap().unwrap().file.as_deref(),Some("code/part_0.dm"));
   alternate.visit_all_callables(||Ok::<_,String>(()),|call|{assert_eq!(alternate.site_line(call.ordinal,7)?,("code/part_0.dm".into(),7));Ok(())}).unwrap();
   let found=alternate.relative_compiled_file_using("code/part_0.dm",&mut||Ok::<(),String>(())).unwrap().unwrap();
   assert!(std::ptr::eq(found,inputs.file(&ordinary.join("code/part_0.dm")).unwrap()),"reverse lookup must borrow the exact actual compiled PolicyFile");
   assert!(alternate.relative_compiled_file_using("code/absent.dm",&mut||Ok::<(),String>(())).unwrap().is_none());
   let mut polls=0;let first=alternate.relative_compiled_file_using("code/part_128.dm",&mut||{polls+=1;if polls==3{Err(crate::reactive_reads_native::Failure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Ok(())}});
   assert!(matches!(first,Err(crate::reactive_reads_native::Failure::Operational(ref error))if error.raw_os_error()==Some(1450)));assert_eq!(polls,3);
   assert!(alternate.relative_file(&ordinary.join("code/absent.dm")).is_err(),"formatting cannot mint original source membership");
   assert!(alternate.relative_file(&ordinary.parent().unwrap().join("outside.dm")).is_err(),"equivalent prefixes grant no external source");
   let path_budget=Budget::new(std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()).unwrap();
   let limited=ReadSource::native(&inputs,&verbatim,&path_budget).unwrap().with_checkpoint(&checkpoint);
   assert!(limited.relative_file(inputs.files().find(|file|file.is_compiled()).unwrap().path()).is_err());
   assert!(path_budget.denied(),"actual formatting must charge the same source budget");
  }
  assert_eq!(provider.reads.get(),before,"constructor/metadata queries cannot acquire source again");assert!(source.parse_body(0).is_err(),"no original active-context body borrower is fabricated");
 }
}

/// SAME native ancestry algorithm for original full and generation-only data.
/// Presence/control callbacks preserve each caller's actual source/error role.
pub(crate) fn subtype_original<E:From<&'static str>>(tree:&dm_tree::SemanticTree,child:&str,parent:&str,checkpoint:&mut impl FnMut()->Result<(),E>,presence:&mut impl FnMut(&str)->Result<bool,E>)->Result<bool,E>{
        let Some(mut ty)=tree.lookup_type(SymbolId::of(child))else{
            if presence(child)?{return Err("reactive positive checker type has no borrowed original hierarchy node".into());}
            return Ok(false)
        };
        let parent=SymbolId::of(parent);
        for _ in 0..=tree.types().len(){
            checkpoint()?;let node=tree.type_node(ty).ok_or("reactive original hierarchy node absent")?;
            if node.path==parent{return Ok(true)};
            match tree.parent(ty){Some(next)=>ty=next,None=>return Ok(false)}
        }
        Err("reactive original hierarchy contains a cycle".into())
}

/// Exact bounded old declared-owner walk, including the actual root ancestor.
/// The candidate issuer may observe implicit global fallback; exact equality
/// prevents accepting it until the real parent chain reaches that owner.
pub(crate) fn variable_declaring_owner_original<'a,E:From<&'static str>>(receiver:&str,name:&str,bound:usize,checkpoint:&mut impl FnMut()->Result<(),E>,candidate:&mut impl FnMut(&str,&str)->Result<Option<&'a str>,E>,parent:&mut impl FnMut(&str)->Result<Option<&'a str>,E>)->Result<Option<&'a str>,E>{
 let mut current=Some(receiver);for _ in 0..bound{checkpoint()?;let Some(owner)=current else{return Ok(None)};if let Some(declaring)=candidate(owner,name)?{if declaring==owner{return Ok(Some(declaring))}}current=parent(owner)?;}if current.is_some(){return Err("source ancestry exceeds actual original type roster".into())}Ok(None)
}

impl ReadSource<'_>{pub(crate) fn callable_header_site(&self,ordinal:usize)->Result<(String,u32),String>{self.require()?;let archive=self.inputs.archive();let occurrence=archive.occurrences().get(ordinal).ok_or("setter header original occurrence absent")?;let point=archive.callable_header_policy_line(occurrence.member)?;let file=self.file(&point.path)?;let line=file.analyze_display_line(point.line).map_err(|e|e.to_string())?;self.site_line(ordinal,u32::try_from(line).map_err(|_|"setter original header line overflow")?)}}
