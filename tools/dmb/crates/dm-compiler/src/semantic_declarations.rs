//! Declaration expression resolution over an allocation-independent owner model.
//! Wire tables are consulted only once to import the immutable builtin schema.
use super::*;
use std::cell::RefCell;
use std::sync::{Mutex, OnceLock};
use sha2::{Digest, Sha256};

#[derive(Clone)]
struct Field {
    expression: Option<String>,
    constant: bool,
    override_only: bool,
    imported: Option<const_eval::Constant>,
}
#[derive(Clone, Default)]
struct Owner {
    parent: Option<String>,
    fields: BTreeMap<String, Field>,
}
#[derive(Default)]
pub(super) struct SemanticDeclarations {
    owners: HashMap<String, Arc<Owner>>,
    globals: HashMap<String, Field>,
    values: Mutex<HashMap<(String, String), Option<const_eval::Constant>>>,
}
thread_local! {
    static ACTIVE: RefCell<Option<Arc<SemanticDeclarations>>> = const { RefCell::new(None) };
}
pub(super) struct ActiveModel(Option<Arc<SemanticDeclarations>>);
impl Drop for ActiveModel {
    fn drop(&mut self) { ACTIVE.with(|active| *active.borrow_mut() = self.0.take()); }
}
pub(super) fn activate(model: Arc<SemanticDeclarations>) -> ActiveModel {
    ActiveModel(ACTIVE.with(|active| active.replace(Some(model))))
}
pub(super) fn capture_active() -> Option<Arc<SemanticDeclarations>> {
    ACTIVE.with(|active| active.borrow().clone())
}
pub(super) fn activate_optional(model: Option<Arc<SemanticDeclarations>>) -> ActiveModel {
    ActiveModel(ACTIVE.with(|active| active.replace(model)))
}
/// None means no semantic model is installed (legacy isolated helper callers).
/// Some(None) is a witnessed missing/dynamic binding and never consults wire IDs.
pub(super) fn evaluate(source: &str, owner: Option<&str>, blocked: &HashSet<String>) -> Option<Option<const_eval::Constant>> {
    let model = ACTIVE.with(|active| active.borrow().clone())?;
    let owner = owner.unwrap_or("");
    Some(const_eval::evaluate(source, |name| model.resolve(owner, name, blocked, &mut HashSet::new())))
}
impl SemanticDeclarations {
    pub(super) fn build(items: &[Item], modified: &[Item], builtin: &Dmb) -> Arc<Self> {
        let mut model = Self::default();
        let strings = StringIndex::new(builtin);
        for (class_id, class) in builtin.classes.iter().enumerate() {
            let Some(path) = builtin.string(class.path_string_id()).and_then(|path|std::str::from_utf8(path).ok()) else {continue};
            let parent = builtin.classes.get(class.parent_class_id() as usize)
                .and_then(|class|builtin.string(class.path_string_id()))
                .and_then(|path|std::str::from_utf8(path).ok()).map(str::to_owned);
            let mut owner = Owner {parent, fields:BTreeMap::new()};
            for (id, flags) in builtin.class_variable_declarations(class_id).unwrap_or_default() {
                let variable = &builtin.variables[id as usize];
                let Some(name)=builtin.string(variable.name).and_then(|name|std::str::from_utf8(name).ok()) else {continue};
                owner.fields.insert(name.to_owned(), Field {expression:None,constant:flags&2!=0,override_only:false,imported:constant_from_variable(builtin,id,&strings)});
            }
            for value in builtin.class_initial_values(class_id).unwrap_or_default() {
                let variable = &builtin.variables[value.variable_id as usize];
                let Some(name)=builtin.string(variable.name).and_then(|name|std::str::from_utf8(name).ok()) else {continue};
                let imported=constant_from_value(builtin,&Variable {name:0,kind:value.value.tag(),value:value.value.number_bits().unwrap_or_else(||value.value.id())},&strings);
                let field=owner.fields.entry(name.to_owned()).or_insert(Field {expression:None,constant:false,override_only:false,imported:None});
                field.imported=imported;
            }
            model.owners.insert(path.to_owned(),Arc::new(owner));
        }
        for (name,id) in &strings.1 {
            model.globals.insert(name.clone(),Field {expression:None,constant:true,override_only:false,imported:constant_from_variable(builtin,*id,&strings)});
        }
        fn ensure(model:&mut SemanticDeclarations,path:&str) {
            if path.is_empty() || model.owners.contains_key(path) {return;}
            let parent=path.rsplit_once('/').map(|(parent,_)|parent).filter(|parent|!parent.is_empty()).unwrap_or("/datum");
            if parent!=path {ensure(model,parent);}
            model.owners.insert(path.to_owned(),Arc::new(Owner {parent:(parent!=path).then(||parent.to_owned()),fields:BTreeMap::new()}));
        }
        let mut types=Vec::new();
        collect_type_items(items,&mut types);
        types.extend(modified.iter());
        for item in &types {ensure(&mut model,item.header.trim());}
        for item in types {
            let path=item.header.trim();
            let plan=default_plans::owner(item);
            let owner=Arc::make_mut(model.owners.get_mut(path).unwrap());
            if let Some(parent)=&plan.explicit_parent {owner.parent=Some(parent.clone());}
            for expression in &plan.expressions {
                if expression.override_only {
                    let field=owner.fields.entry(expression.name.clone()).or_insert(Field {expression:None,constant:false,override_only:true,imported:None});
                    field.expression=expression.expression.clone();field.imported=None;field.override_only=true;
                } else {
                    owner.fields.insert(expression.name.clone(),Field {expression:expression.expression.clone(),constant:expression.constant,override_only:false,imported:None});
                }
            }
        }
        for item in items.iter().filter(|item|item.kind==ItemKind::Var) {
            if let Ok(plan)=default_plans::declaration(item.header.trim()) {
                let name=plan.name.split('[').next().unwrap_or(&plan.name).to_owned();
                let expression=if plan.name.contains('[') {"list()".to_owned()} else {plan.initial.clone().unwrap_or_else(||"null".to_owned())};
                model.globals.insert(name,Field {expression:Some(expression),constant:plan.is_const,override_only:false,imported:None});
            }
        }
        // Intern immutable owner nodes across project revisions/worktrees. The
        // identity contains every local semantic field and symbolic parent edge;
        // parent values are observed lazily, not copied into each child node.
        for owner in model.owners.values_mut() { *owner = intern_owner(Arc::clone(owner)); }
        Arc::new(model)
    }
    fn resolve(&self,owner:&str,name:&str,blocked:&HashSet<String>,active:&mut HashSet<(String,String)>) -> Option<const_eval::Constant> {
        if let Some((path,field))=name.split_once("::") {return self.field(path,field,true,active);}
        if blocked.contains(name) {return None;}
        let mut path=owner;
        let mut visited=HashSet::new();
        while !path.is_empty() && visited.insert(path.to_owned()) {
            let Some(scope)=self.owners.get(path) else {
                path = lexical_parent(path)?;
                continue;
            };
            if let Some(field)=scope.fields.get(name) {
                let constant = field.constant || (field.override_only && self.inherited_constant(scope.parent.as_deref(), name));
                return if constant {self.value(path,name,field,active)} else {None};
            }
            path=scope.parent.as_deref().unwrap_or("");
        }
        if let Some(field)=self.globals.get(name) {
            return if field.constant {self.value("",name,field,active)} else {None};
        }
        builtin_constant(name)
    }
    fn field(&self,path:&str,name:&str,allow_mutable:bool,active:&mut HashSet<(String,String)>) -> Option<const_eval::Constant> {
        let mut path=path;
        let mut visited=HashSet::new();
        while visited.insert(path.to_owned()) {
            let Some(scope)=self.owners.get(path) else {
                path=lexical_parent(path)?;
                continue;
            };
            if let Some(field)=scope.fields.get(name) {
                return if allow_mutable||field.constant {self.value(path,name,field,active)} else {None};
            }
            path=scope.parent.as_deref()?;
        }
        None
    }
    fn inherited_constant<'a>(&'a self, mut path: Option<&'a str>, name: &str) -> bool {
        let mut visited = HashSet::new();
        while let Some(current) = path {
            if !visited.insert(current) { return false; }
            let Some(owner) = self.owners.get(current) else { path = lexical_parent(current); continue; };
            if let Some(field) = owner.fields.get(name) {
                if field.constant { return true; }
                if !field.override_only { return false; }
            }
            path = owner.parent.as_deref();
        }
        false
    }
    fn value(&self,owner:&str,name:&str,field:&Field,active:&mut HashSet<(String,String)>) -> Option<const_eval::Constant> {
        let key=(owner.to_owned(),name.to_owned());
        if !active.insert(key.clone()) {return None;}
        if let Some(value)=self.values.lock().unwrap_or_else(|error|error.into_inner()).get(&key).cloned() {
            active.remove(&key);return value;
        }
        let result = match &field.expression {
            Some(expression)=>const_eval::evaluate(expression,|name| {
                let mut nested = active.clone();
                self.resolve(owner,name,&HashSet::new(),&mut nested)
            }),
            None=>field.imported.clone(),
        };
        active.remove(&key);
        self.values.lock().unwrap_or_else(|error|error.into_inner()).insert(key,result.clone());
        result
    }
}

fn lexical_parent(path:&str)->Option<&str> {
    if path == "/datum" { return None; }
    Some(path.rsplit_once('/').map(|(parent,_)|parent).filter(|parent|!parent.is_empty()).unwrap_or("/datum"))
}

#[derive(Default)]
struct OwnerNodes { entries:BTreeMap<String,(Arc<Owner>,usize)>, bytes:usize }
fn intern_owner(owner:Arc<Owner>)->Arc<Owner> {
    let mut hash=Sha256::new();
    fn part(hash:&mut Sha256, bytes:&[u8]) {hash.update((bytes.len() as u64).to_le_bytes());hash.update(bytes);}
    part(&mut hash,owner.parent.as_deref().unwrap_or("").as_bytes());
    let mut charge=128+owner.parent.as_ref().map_or(0,String::len);
    for (name,field) in &owner.fields {
        part(&mut hash,name.as_bytes());hash.update([field.constant as u8,field.override_only as u8,field.expression.is_some() as u8]);
        part(&mut hash,field.expression.as_deref().unwrap_or("").as_bytes());
        charge+=128+name.len()+field.expression.as_ref().map_or(0,String::len);
        match &field.imported {
            None=>hash.update([0]),
            Some(const_eval::Constant::Null)=>hash.update([1]),
            Some(const_eval::Constant::Number(number))=>{hash.update([2]);hash.update(number.to_bits().to_le_bytes());},
            Some(const_eval::Constant::Text(text))=>{hash.update([3]);part(&mut hash,text.as_bytes());charge+=text.len();},
            Some(const_eval::Constant::EncodedText(text))=>{hash.update([4]);part(&mut hash,text);charge+=text.len();},
            Some(const_eval::Constant::TypePath(path))=>{hash.update([5]);part(&mut hash,path.as_bytes());charge+=path.len();},
        }
    }
    let identity=format!("{:x}",hash.finalize());
    let mut nodes=owner_nodes().lock().unwrap_or_else(|error|error.into_inner());
    if let Some((node,_))=nodes.entries.get(&identity) {return Arc::clone(node);}
    if charge<=32*1024*1024 {
        while nodes.bytes.saturating_add(charge)>32*1024*1024 {
            let Some(key)=nodes.entries.keys().next().cloned() else {break};
            if let Some((_,old))=nodes.entries.remove(&key) {nodes.bytes=nodes.bytes.saturating_sub(old);}
        }
        nodes.bytes+=charge;nodes.entries.insert(identity,(Arc::clone(&owner),charge));
    }
    owner
}

fn owner_nodes()->&'static Mutex<OwnerNodes> {
    static NODES:OnceLock<Mutex<OwnerNodes>>=OnceLock::new();
    NODES.get_or_init(||Mutex::new(OwnerNodes::default()))
}
pub(super) fn resident_bytes()->usize {
    owner_nodes().lock().unwrap_or_else(|error|error.into_inner()).bytes
}
/// Auxiliary process cache trimming drops indexes only; active requests retain
/// their immutable owner Arcs until completion.
pub(super) fn trim_to(max_bytes:usize) {
    let mut nodes=owner_nodes().lock().unwrap_or_else(|error|error.into_inner());
    while nodes.bytes>max_bytes {
        let Some(key)=nodes.entries.keys().next().cloned() else {break};
        if let Some((_,old))=nodes.entries.remove(&key) {nodes.bytes=nodes.bytes.saturating_sub(old);}
    }
}
