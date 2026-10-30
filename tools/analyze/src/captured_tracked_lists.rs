//! Complete tracked-list template over one admitted raw/native source capture.
//! Only generator rows/nearest cursors are temporary; no declaration model/index.
use crate::{captured_generator_budget::{Budget,MAX_ROWS},captured_raw_policy::CapturedRawPolicy,
    sparse_slots_policy::Output,tracked_lists_policy::{self,Decl}};
use dm_analysis::policy_inputs::PolicyInputs;
use dm_ir::SymbolId;
use dm_tree::{DefinitionMode,MemberKind,Target};
use std::{collections::{BTreeMap,BTreeSet,HashSet},sync::Arc};
pub const FULL_WORKSPACE_COVERAGE:bool=false;
const OUTPUT:&str="code/engine/_generated/tracked_lists.dm";
const MAX_NEIGHBOR_WORK:usize=1_000_000;
pub struct BorrowedTrackedLists<'a>{raw:&'a CapturedRawPolicy,inputs:&'a PolicyInputs,budget:Arc<Budget>}
fn intact(raw:&CapturedRawPolicy)->Result<(),String>{raw.tree.captured_violation().map_or(Ok(()),Err)}
fn charge(b:&Budget,value:Option<usize>)->Result<(),String>{
    match value {Some(n)=>b.charge(n),None=>{b.deny();Err("tracked-list admission overflow".into())}}
}
fn defined_type(line:&str)->Option<&str>{
    if !line.starts_with('/')||line.starts_with("//"){return None;}
    let end=line.find(|c:char|!(c.is_ascii_alphanumeric()||c=='_'||c=='/')).unwrap_or(line.len());
    let mut path=line[..end].trim_end_matches('/');
    for keyword in ["/var/","/proc/","/verb/"]{if let Some(i)=path.find(keyword){path=&path[..i];}}
    if line[end..].trim_start().starts_with('('){path=path.rsplit_once('/').map(|(a,_)|a).unwrap_or(path);}
    (path.len()>1).then_some(path)
}
impl<'a> BorrowedTrackedLists<'a>{
    pub fn capture(raw:&'a CapturedRawPolicy,inputs:&'a PolicyInputs,budget:Arc<Budget>)->Result<Self,String>{
        raw.validate_current_raw_roster(inputs)?;
        Ok(Self{raw,inputs,budget})
    }
    fn cursor_file(&self,path:&std::path::Path)->Result<&dm_analysis::policy_inputs::PolicyFile,String>{
        // Existing canonical lookup is the identity authority. Precharge its
        // PathBuf/component scratch; raw provider spellings need not be equal.
        charge(&self.budget,path.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)))?;
        self.inputs.file(path).filter(|f|f.is_compiled()&&f.role()==dm_analysis::policy_inputs::PolicyRole::DmSource)
            .ok_or_else(||"tracked-list declaration cursor has no captured original compiled source".into())
    }
    fn variable(&self,ty:&str,name:&str)->Result<Option<dm_analysis::checker_variable_facts::VariableFact>,String>{
        let tree=self.inputs.archive().tree();
        let profile=tree.checker_builtin_profile().ok_or("tracked-list checker profile absent")?;
        if !tree.checker_source_type_presence(profile,ty).map_err(|e|format!("{e:?}"))?{return Ok(None);}
        dm_analysis::checker_variable_facts::variable_original(tree,profile,SymbolId::of(ty),SymbolId::of(name))
    }
    fn list(&self,d:&Decl)->Result<bool,String>{
        let Some(fact)=self.variable(&d.ty,&d.var)? else{return Ok(false)};
        if let Some(formal)=fact.formal{
            let archive=self.inputs.archive();let tree=archive.tree();
            let profile=tree.checker_builtin_profile().ok_or("tracked-list checker profile absent")?;
            archive.checker_variable_qualifiers(formal,profile)?;
            if let Some(array)=&fact.metadata.array{
                if array.dimensions.is_empty(){return Err("tracked-list array dimensions unissued".into());}
                // Any original array declarator introduces an outer /list;
                // element/nested dimensions cannot remove that container.
                return Ok(true);
            }
            let path=fact.metadata.declared_type.and_then(|id|tree.symbols().text(id));
            let width=path.map_or(0,str::len).checked_add(fact.metadata.list_element_type.and_then(|id|tree.symbols().text(id)).map_or(0,str::len)).ok_or("tracked-list type width overflow")?;
            charge(&self.budget,width.checked_mul(64).and_then(|n|n.checked_add(4096)))?;
            let props=archive.checker_variable_properties(formal,profile)?;
            Ok(props.declared_hint().is_some_and(|p|p=="/list"||p.starts_with("/list/")))
        }else{
            // Borrow the hash-qualified ORIGINAL builtin declaration metadata,
            // including its list-element annotation, never runtime value types.
            Ok(fact.metadata.declared_type==Some(SymbolId::of("/list")))
        }
    }
    fn subtype(&self,child:&str,parent:&str)->Result<bool,String>{
        let tree=self.inputs.archive().tree();let profile=tree.checker_builtin_profile().ok_or("tracked-list checker profile absent")?;
        if !tree.checker_source_type_presence(profile,child).map_err(|e|format!("{e:?}"))?||
            !tree.checker_source_type_presence(profile,parent).map_err(|e|format!("{e:?}"))?{return Ok(false);}
        Ok(dm_analysis::checker_variable_facts::original_ancestor_depth(tree,SymbolId::of(child),SymbolId::of(parent))?.is_some())
    }
    fn add_taken(&self,taken:&mut BTreeSet<(String,String)>,ty:&str,name:&str)->Result<(),String>{
        charge(&self.budget,ty.len().checked_add(name.len()).and_then(|n|n.checked_mul(2)).and_then(|n|n.checked_add(512)))?;
        taken.insert((ty.into(),name.into()));Ok(())
    }
    pub fn generate(&self,mut checkpoint:impl FnMut()->Result<(),String>)->Result<Output,String>{
        checkpoint()?;self.budget.require()?;intact(self.raw)?;self.raw.validate_current_raw_roster(self.inputs)?;
        charge(&self.budget,self.raw.tree.files.len().checked_mul(512).and_then(|n|n.checked_add(4096)))?;
        let files=self.raw.tree.select(&crate::tree::CODE_DM);
        let mut declarations=Vec::new();let mut taken=BTreeSet::new();let mut work=0usize;
        let archive=self.inputs.archive();let tree=archive.tree();
        for f in &files{
            checkpoint()?;intact(self.raw)?;
            let raw=f.raw();let lines=raw.text.lines().count();
            charge(&self.budget,f.abs.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)))?;
            let current_file=self.inputs.file(&f.abs).ok_or("tracked-list raw source binding absent")?;
            // Raw selectors clone <= input bytes plus per-row path. Vec old/new
            // growth + sorting scratch and later selected-row clones are charged
            // before invoking the unchanged selectors (one hit per source line).
            charge(&self.budget,raw.text.len().checked_mul(16).and_then(|n|n.checked_add(lines.checked_mul(f.rel.len().checked_mul(4)?.checked_add(512)?)?)))?;
            let mut rows=tracked_lists_policy::declarations_in(f);
            if declarations.len().checked_add(rows.len()).is_none_or(|n|n>MAX_ROWS){return Err("tracked-list marker count exceeds captured scope".into());}
            declarations.append(&mut rows);
            let lookalikes=tracked_lists_policy::lookalikes(f);intact(self.raw)?;
            for (line,ty,name) in lookalikes{
                checkpoint()?;
                if !ty.is_empty(){self.add_taken(&mut taken,&ty,&name)?;continue;}
                // Preserve the old previous/current AND NEXT definition-owner
                // rule. Borrow original declaration storage, not a copied index.
                let mut previous:Option<(usize,&str,&str)>=None;let mut next:Option<(usize,&str,&str)>=None;
                for target in tree.declarations(){
                    work=match work.checked_add(1){Some(n) if n<=MAX_NEIGHBOR_WORK=>n,_=>{
                        self.budget.deny();return Err("tracked-list nearest-owner work exceeds captured scope".into());
                    }};
                    if work%256==0{checkpoint()?;self.budget.require()?;}
                    let Target::Member(member)=target else{continue};
                    let node=tree.member(*member).ok_or("tracked-list declaration member absent")?;
                    if node.kind==MemberKind::Var&&node.definition!=DefinitionMode::Declare{continue;}
                    if archive.member_location(*member).is_none(){continue;}
                    let (path,definition_line)=match node.kind{
                        MemberKind::Var=>{let cursor=archive.member_policy_compatibility_cursor(*member)?;(cursor.path,cursor.line)},
                        MemberKind::Proc|MemberKind::Verb=>{let origin=archive.callable_header_policy_origin(*member)?;(origin.path,origin.line)},
                    };
                    let cursor_file=self.cursor_file(&path)?;
                    if !std::ptr::eq(cursor_file,current_file){continue;}
                    let owner=tree.type_node(node.owner).and_then(|t|tree.symbols().text(t.path)).ok_or("tracked-list definition owner absent")?;
                    let name=tree.symbols().text(node.name).ok_or("tracked-list definition name absent")?;
                    let point=(definition_line,owner,name);
                    if point.0<=line as usize{if previous.is_none_or(|p|p<point){previous=Some(point);}}
                    else if next.is_none_or(|p|point<p){next=Some(point);}
                }
                if let Some((_,owner,_))=previous{self.add_taken(&mut taken,owner,&name)?;}
                if let Some((_,owner,_))=next{self.add_taken(&mut taken,owner,&name)?;}
            }
        }
        declarations.sort();declarations.dedup();
        let mut lists=BTreeMap::new();
        for d in declarations{
            checkpoint()?;if self.list(&d)?{
                charge(&self.budget,d.ty.len().checked_add(d.var.len()).and_then(|n|n.checked_mul(2)).and_then(|n|n.checked_add(512)))?;
                lists.entry((d.ty.clone(),d.var.clone())).or_insert(d);
            }
        }
        let mut tests=BTreeSet::new();let mut production=HashSet::new();
        for f in &self.raw.tree.files{
            checkpoint()?;
            if !f.rel.ends_with(".dm")||f.rel.starts_with("code/engine/_generated/")||f.rel.starts_with("code/_generated/"){continue;}
            let raw=f.text();
            charge(&self.budget,raw.len().checked_mul(8).and_then(|n|n.checked_add(raw.lines().count().checked_mul(512)?)))?;
            for line in raw.lines(){if let Some(ty)=defined_type(line){
                if crate::generator_test_scope::test_only(&f.rel){tests.insert(ty.to_owned());}else{production.insert(ty.to_owned());}
            }}
        }
        tests.retain(|ty|!production.contains(ty));
        let mut test_rows=Vec::new();let mut out=Output::captured(self.budget.clone());
        for d in lists.into_values(){
            checkpoint()?;self.budget.require()?;
            if crate::generator_test_scope::test_only(&d.rel)||tests.contains(&d.ty){
                if !self.budget.row(&mut test_rows){return Err("tracked-list test roster allocation denied".into());}
                test_rows.push(d);continue;
            }
            charge(&self.budget,d.var.len().checked_mul(2).and_then(|n|n.checked_add(128)))?;
            if let Some(version)=self.variable(&d.ty,&format!("{}_version",d.var))?{
                let generated=if let Some(formal)=version.formal{
                    let cursor=archive.member_policy_compatibility_cursor(formal)?;
                    let source=self.cursor_file(&cursor.path)?;
                    if let Some(file)=self.raw.tree.get(OUTPUT){
                        charge(&self.budget,file.abs.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(512)))?;
                        let current=self.inputs.file(&file.abs).ok_or("tracked-list generated raw source binding absent")?;
                        std::ptr::eq(source,current)
                    }else{false}
                }else{false};
                if !generated{
                    out.diag_fmt(&d.rel,d.line,format_args!("tracked list `{}` needs a var `{}_version`, which {} already declares",d.var,d.var,d.ty));continue;
                }
            }
            let mut collision=false;
            for (prefix,suffix) in [("add_",""),("include_",""),("remove_",""),("set_","_at"),("clear_",""),("insert_",""),("swap_",""),("cut_","")]{
                checkpoint()?;
                charge(&self.budget,d.var.len().checked_add(prefix.len()).and_then(|n|n.checked_add(suffix.len())).and_then(|n|n.checked_mul(2)).and_then(|n|n.checked_add(64)))?;
                let name=format!("{prefix}{}{suffix}",d.var);
                for (ty,n) in &taken{
                    checkpoint()?;
                    if n==&name&&(self.subtype(ty,&d.ty)?||self.subtype(&d.ty,ty)?){
                        out.diag_fmt(&d.rel,d.line,format_args!("tracked list `{}`: {} (or a type on its path) already defines the proc `{}` the generator would write; rename that proc",d.var,d.ty,name));
                        collision=true;break;
                    }
                }
                if collision{break;}
            }
            if !collision{tracked_lists_policy::emit(&mut out,&d);}
        }
        if !test_rows.is_empty(){out.line(crate::generator_test_scope::TEST_GUARD);out.blank();
            for d in test_rows{checkpoint()?;self.budget.require()?;tracked_lists_policy::emit(&mut out,&d);}
            out.line("#endif");
        }
        checkpoint()?;self.budget.require()?;intact(self.raw)?;Ok(out)
    }
}
