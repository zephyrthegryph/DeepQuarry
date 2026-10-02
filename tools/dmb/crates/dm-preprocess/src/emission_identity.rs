//! Canonical source identity follows emitted include recipes, never rope pieces.
use crate::PreprocessedProject;
use dm_syntax::{SegmentedSource,Span};
use serde::{Serialize,Deserialize};
use sha2::{Digest,Sha256};
use std::{path::Path,sync::Arc};
#[derive(Clone,Debug,Eq,PartialEq,Serialize,Deserialize)]
pub enum EmissionPart { Literal{span:Span,digest:[u8;32]}, Child{unit:usize} }
#[derive(Clone,Debug,Default,Eq,PartialEq,Serialize,Deserialize)]
pub struct EmissionRecipe {pub key:String,pub parts:Vec<EmissionPart>}
#[derive(Clone,Debug,Default,Eq,PartialEq,Serialize,Deserialize)]
pub struct SourceSemanticIdentity {
    pub version:u32,pub root:[u8;32],pub units:Vec<[u8;32]>,pub recipes:Vec<Arc<EmissionRecipe>>,pub root_recipe:Arc<EmissionRecipe>,
}
impl SourceSemanticIdentity {
    pub fn build(project:&PreprocessedProject,source:&SegmentedSource,directory:&Path)->Result<Self,String> {
        Self::rebuild(project,source,directory,None,&[])
    }
    pub fn rebuild(project:&PreprocessedProject,source:&SegmentedSource,directory:&Path,previous:Option<&Self>,edits:&[Span])->Result<Self,String> {
        if project.unit_parents.len()!=project.units.len() {return Err("incomplete emission include tree".into());}
        let mut children=vec![Vec::new();project.units.len()];let mut roots=Vec::new();
        for (index,parent) in project.unit_parents.iter().enumerate() {
            if let Some(parent)=parent {
                if *parent<=index || *parent>=children.len() {return Err("invalid emission parent".into());}
                let child=project.units[index].output_span;let owner=project.units[*parent].output_span;
                if child.start<owner.start || child.end>owner.end {return Err("emission child outside parent".into());}
                children[*parent].push(index);
            } else {roots.push(index);}
        }
        let mut result=Self{version:1,..Self::default()};
        for (index,unit) in project.units.iter().enumerate() {
            let key=unit.path.strip_prefix(directory).unwrap_or(&unit.path).to_string_lossy().replace('\\',"/");
            let old=previous.and_then(|old|old.recipes.get(index)).filter(|old|old.key==key);
            let recipe=recipe(key,unit.output_span,&children[index],project,source,old.map(Arc::as_ref),edits)?;
            let reuse=old.is_some_and(|old|same_recipe(old,&recipe,previous.map(|identity|identity.units.as_slice()).unwrap_or(&[]),&result.units));
            let digest=if reuse {previous.and_then(|old|old.units.get(index)).copied().ok_or("previous emission digest unavailable")?} else {hash_recipe(&recipe,&result.units)?};
            result.units.push(digest);result.recipes.push(Arc::new(recipe));
        }
        let root=recipe("<expanded-root>".into(),Span::new(0,source.len()),&roots,project,source,previous.map(|old|old.root_recipe.as_ref()),edits)?;
        result.root=hash_recipe(&root,&result.units)?;result.root_recipe=Arc::new(root);Ok(result)
    }
    pub fn validate(&self,project:&PreprocessedProject,source_len:usize)->bool {
        if self.version!=1 || self.units.len()!=project.units.len() || self.recipes.len()!=project.units.len() || project.unit_parents.len()!=project.units.len() {return false;}
        let mut children=vec![Vec::new();project.units.len()];let mut roots=Vec::new();
        for (index,parent) in project.unit_parents.iter().enumerate() {
            if let Some(parent)=parent {if *parent<=index || *parent>=children.len() {return false;}children[*parent].push(index);} else {roots.push(index);}
        }
        for (index,recipe) in self.recipes.iter().enumerate() {
            if !layout_matches(recipe,project.units[index].output_span,&children[index],project) || hash_recipe(recipe,&self.units[..index]).ok()!=Some(self.units[index]) {return false;}
        }
        layout_matches(&self.root_recipe,Span::new(0,source_len),&roots,project) && hash_recipe(&self.root_recipe,&self.units).ok()==Some(self.root)
    }
    pub fn resident_bytes(&self)->usize {self.units.capacity()*32+self.recipes.capacity()*std::mem::size_of::<Arc<EmissionRecipe>>() +self.recipes.iter().chain(std::iter::once(&self.root_recipe)).map(|recipe|recipe.key.len()+recipe.parts.capacity()*std::mem::size_of::<EmissionPart>()).sum::<usize>()}
}
fn recipe(key:String,span:Span,children:&[usize],project:&PreprocessedProject,source:&SegmentedSource,old:Option<&EmissionRecipe>,edits:&[Span])->Result<EmissionRecipe,String> {
    let mut result=EmissionRecipe{key,parts:Vec::new()};let mut cursor=span.start;
    for &child in children {
        let child_span=project.units[child].output_span;
        if child_span.start<cursor || child_span.end>span.end {return Err("overlapping emission children".into());}
        literal(&mut result,cursor,child_span.start,source,old,edits)?;
        result.parts.push(EmissionPart::Child{unit:child});cursor=child_span.end;
    }
    literal(&mut result,cursor,span.end,source,old,edits)?;Ok(result)
}
fn literal(recipe:&mut EmissionRecipe,start:usize,end:usize,source:&SegmentedSource,old:Option<&EmissionRecipe>,edits:&[Span])->Result<(),String> {
    if start==end {return Ok(());}
    let span=Span::new(start,end);
    let reused=old.and_then(|old|old.parts.get(recipe.parts.len())).and_then(|part|match part {
        EmissionPart::Literal{span:before,digest} if before.end-before.start==end-start && !edits.iter().any(|edit| {
            if edit.start==edit.end {edit.start>=before.start&&edit.start<before.end} else {edit.start<before.end&&edit.end>before.start}
        })=>Some(*digest),_=>None});
    let digest=if let Some(digest)=reused {digest} else {let mut hash=Sha256::new();source.visit_range(span,|text|hash.update(text.as_bytes()))?;hash.finalize().into()};
    recipe.parts.push(EmissionPart::Literal{span,digest});Ok(())
}
fn hash_recipe(recipe:&EmissionRecipe,units:&[[u8;32]])->Result<[u8;32],String> {
    let mut hash=Sha256::new();hash.update(b"dm-emission-recipe-v1\0");hash.update((recipe.key.len() as u64).to_le_bytes());hash.update(recipe.key.as_bytes());hash.update((recipe.parts.len() as u64).to_le_bytes());
    for part in &recipe.parts {match part {
        EmissionPart::Literal{span,digest}=>{hash.update([0]);hash.update(((span.end-span.start) as u64).to_le_bytes());hash.update(digest);},
        EmissionPart::Child{unit}=>{hash.update([1]);hash.update(units.get(*unit).ok_or("emission child digest unavailable")?);}
    }}Ok(hash.finalize().into())
}

fn same_recipe(before:&EmissionRecipe,current:&EmissionRecipe,old_units:&[[u8;32]],new_units:&[[u8;32]])->bool {
    before.key==current.key && before.parts.len()==current.parts.len() && before.parts.iter().zip(&current.parts).all(|(a,b)|match (a,b) {
        (EmissionPart::Literal{span:a,digest:ad},EmissionPart::Literal{span:b,digest:bd})=>a.end-a.start==b.end-b.start&&ad==bd,
        (EmissionPart::Child{unit:a},EmissionPart::Child{unit:b})=>old_units.get(*a).is_some_and(|old|new_units.get(*b)==Some(old)),_=>false,
    })
}
fn layout_matches(recipe:&EmissionRecipe,span:Span,children:&[usize],project:&PreprocessedProject)->bool {
    let mut parts=recipe.parts.iter();let mut cursor=span.start;
    for &child in children {
        let child_span=project.units[child].output_span;
        if child_span.start<cursor || child_span.end>span.end {return false;}
        if cursor<child_span.start && !matches!(parts.next(),Some(EmissionPart::Literal{span,..}) if span.start==cursor&&span.end==child_span.start) {return false;}
        if !matches!(parts.next(),Some(EmissionPart::Child{unit}) if *unit==child) {return false;}
        cursor=child_span.end;
    }
    if cursor<span.end && !matches!(parts.next(),Some(EmissionPart::Literal{span:part,..}) if part.start==cursor&&part.end==span.end) {return false;}
    parts.next().is_none()
}
