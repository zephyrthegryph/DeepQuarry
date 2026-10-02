//! Generation-local physical declaration projection. Semantic meaning lives in
//! semantic_declarations; this index only resolves current variable table IDs.
use super::*;
use std::cell::RefCell;
#[derive(Default)]
struct Index { classes:HashMap<u32,ClassFields>, bytes:usize, dynamic_pointer:usize, dynamic_len:usize, constructors:u32, authored_constructors:u32 }
struct ClassFields { list:u32, words:usize, fields:HashMap<String,(u32,u32)>, charge:usize }
thread_local! {static INDEX:RefCell<Index>=RefCell::new(Index::default());}
pub(super) struct Generation;
impl Drop for Generation {fn drop(&mut self) {INDEX.with(|index|*index.borrow_mut()=Index::default());}}
pub(super) fn begin()->Generation {INDEX.with(|index|*index.borrow_mut()=Index::default());Generation}
pub(super) fn local(dmb:&Dmb,class:u32,name:&str)->Option<(u32,u32)> {
    let owner=dmb.classes.get(class as usize)?;
    let list=owner.lists_and_procs[4];let words=dmb.lists.get(list as usize).map_or(0,Vec::len);
    INDEX.with(|index| {
        let mut index=index.borrow_mut();
        if let Some(fields)=index.classes.get(&class) {
            if fields.list==list&&fields.words==words {return fields.fields.get(name).copied();}
        }
        if let Some(old)=index.classes.remove(&class) {index.bytes=index.bytes.saturating_sub(old.charge);}
        let mut fields=HashMap::new();let mut charge=128;
        for (variable,flags) in dmb.class_variable_declarations(class as usize).unwrap_or_default() {
            let Some(name)=dmb.string(dmb.variables[variable as usize].name).and_then(|name|std::str::from_utf8(name).ok()) else {continue;};
            charge+=name.len()+80;fields.entry(name.to_owned()).or_insert((variable,flags));
        }
        let result=fields.get(name).copied();
        if charge<=16*1024*1024 {
            if index.bytes.saturating_add(charge)>16*1024*1024 {index.classes.clear();index.bytes=0;}
            index.bytes+=charge;index.classes.insert(class,ClassFields {list,words,fields,charge});
        }
        result
    })
}
pub(super) fn inherited(dmb:&Dmb,mut class:u32,name:&str)->Option<(u32,u32)> {
    let mut visited=HashSet::new();
    while class!=0xffff&&visited.insert(class) {
        if let Some(variable)=local(dmb,class,name) {return Some(variable);}
        class=dmb.classes.get(class as usize)?.parent_class_id();
    }
    None
}
pub(super) fn builtin_field(dmb:&Dmb,mut class:u32,name:&str)->bool {
    let mut visited=HashSet::new();
    while class!=0xffff&&visited.insert(class) {
        let Some(owner)=dmb.classes.get(class as usize) else {return false;};
        if let Some(path)=dmb.string(owner.path_string_id()).and_then(|path|std::str::from_utf8(path).ok()) {
            if builtin_field_names(path).contains(&name) {return true;}
        }
        class=owner.parent_class_id();
    }
    false
}

/// Constructor ordinals are a prefix fold, not a repeated scan of all previous
/// initializers. A cloned/replaced vector starts a new cursor automatically.
pub(super) fn constructor_counts(assignments:&[PendingDynamic])->(u32,u32) {
    INDEX.with(|index| {
        let mut index=index.borrow_mut();
        let pointer=assignments.as_ptr() as usize;
        if pointer!=index.dynamic_pointer||assignments.len()<index.dynamic_len {
            index.dynamic_pointer=pointer;index.dynamic_len=0;index.constructors=0;index.authored_constructors=0;
        }
        for assignment in &assignments[index.dynamic_len..] {
            if assignment.owner.is_none()&&assignment.expression.starts_with("new ") {
                index.constructors+=1;
                if !assignment.name.starts_with("__dm_static_") {index.authored_constructors+=1;}
            }
        }
        index.dynamic_len=assignments.len();(index.authored_constructors,index.constructors)
    })
}
