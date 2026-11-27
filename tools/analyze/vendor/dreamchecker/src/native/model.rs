//! The type tree the native checker reads: BYOND's builtin types, vars and procs (`builtins.txt`) with the project's declarations
//! added in the compiler front end's declaration order, by the same registration rules SpacemanDMM's object tree follows (a type
//! path adds every missing step; a `proc/`/`verb/` definition declares, a bare one overrides; a definition after an override of
//! the same proc is moved before it). Types, vars and procs keep their registration order, children their name order: the checks
//! visit them in those orders, which are their diagnostics' order.
//!
//! A proc is a [`ProcId`] (type, name, value index), as SpacemanDMM's `ProcRef`: each definition of a name on a type is one value,
//! `..()` reaches the previous value or the parent type's last one.
use std::collections::BTreeMap;
use std::fmt;

use dm::Location;
use foldhash::{HashMap, HashMapExt};

use super::input::{InputType, Where};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, serde::Serialize, serde::Deserialize)]
pub struct TypeId(pub u32);

impl TypeId {
    pub const ROOT: TypeId = TypeId(0);
    pub fn index(self) -> usize {
        self.0 as usize
    }
}

/// Var flags SpacemanDMM keeps (`static`/`global` are one flag).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct VarFlags(pub u8);

impl VarFlags {
    pub const STATIC: u8 = 1;
    pub const CONST: u8 = 2;
    pub const TMP: u8 = 4;
    pub const FINAL: u8 = 8;
    pub const PRIVATE: u8 = 16;
    pub const PROTECTED: u8 = 32;

    pub fn from_name(name: &str) -> Option<u8> {
        Some(match name {
            "global" | "static" => Self::STATIC,
            "const" => Self::CONST,
            "tmp" => Self::TMP,
            "final" | "SpacemanDMM_final" => Self::FINAL,
            "SpacemanDMM_private" => Self::PRIVATE,
            "SpacemanDMM_protected" => Self::PROTECTED,
            _ => return None,
        })
    }
    pub fn is_final(self) -> bool {
        self.0 & Self::FINAL != 0
    }
    pub fn is_private(self) -> bool {
        self.0 & Self::PRIVATE != 0
    }
    pub fn is_protected(self) -> bool {
        self.0 & Self::PROTECTED != 0
    }
}

#[derive(Clone, Debug)]
pub struct VarDecl {
    pub flags: VarFlags,
    /// The declared type's pieces (`list`, `mob`), flags left out.
    pub type_path: Vec<String>,
    pub location: Where,
}

#[derive(Clone, Debug)]
pub struct TypeVar {
    /// Where its value was last set (a declaration or an override).
    pub value_location: Where,
    pub declaration: Option<VarDecl>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProcKind {
    Proc,
    Verb,
}

impl ProcKind {
    pub fn name(self) -> &'static str {
        match self {
            ProcKind::Proc => "proc",
            ProcKind::Verb => "verb",
        }
    }
}

impl fmt::Display for ProcKind {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(self.name())
    }
}

/// A proc's declared return type (`as num`, `as /mob`).
#[derive(Clone, Debug, Default)]
pub enum ReturnType {
    #[default]
    None,
    Input(InputType),
    TypePath(Vec<String>),
}

#[derive(Clone, Debug)]
pub struct ProcDecl {
    pub kind: ProcKind,
    pub is_final: bool,
    pub location: Where,
    pub return_type: ReturnType,
}

#[derive(Clone, Debug)]
pub struct Param {
    pub name: String,
    pub type_path: Vec<String>,
    pub location: Where,
}

#[derive(Clone, Debug)]
pub struct ProcValue {
    pub location: Where,
    pub parameters: Vec<Param>,
    /// The body (an index into the input's bodies), when the definition has one.
    pub body: Option<u32>,
}

#[derive(Clone, Debug, Default)]
pub struct TypeProc {
    pub values: Vec<ProcValue>,
    pub declaration: Option<ProcDecl>,
}

#[derive(Debug)]
pub struct Type {
    /// `""` for the root, else `/a/b`.
    pub path: String,
    pub location: Where,
    location_specificity: usize,
    pub parent_path: Option<TypeId>,
    pub parent_type: Option<TypeId>,
    pub children: BTreeMap<String, TypeId>,
    pub vars: Vec<(String, TypeVar)>,
    var_index: HashMap<String, usize>,
    pub procs: Vec<(String, TypeProc)>,
    proc_index: HashMap<String, usize>,
}

impl Type {
    pub fn is_root(&self) -> bool {
        self.path.is_empty()
    }
    pub fn pretty_path(&self) -> &str {
        if self.is_root() {
            "(global)"
        } else {
            &self.path
        }
    }
    pub fn var(&self, name: &str) -> Option<&TypeVar> {
        self.var_index.get(name).map(|&i| &self.vars[i].1)
    }
    pub fn proc(&self, name: &str) -> Option<&TypeProc> {
        self.proc_index.get(name).map(|&i| &self.procs[i].1)
    }
}

#[derive(Debug, Default)]
pub struct Model {
    pub types: Vec<Type>,
    by_path: HashMap<String, TypeId>,
}

/// A proc value: the type it is on, its name and which definition on that type.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, serde::Serialize, serde::Deserialize)]
pub struct ProcId {
    pub ty: TypeId,
    /// Index into the type's `procs`.
    pub slot: u32,
    pub idx: u32,
}

impl Model {
    pub fn root(&self) -> TypeId {
        TypeId::ROOT
    }
    pub fn ty(&self, t: TypeId) -> &Type {
        &self.types[t.index()]
    }
    pub fn find(&self, path: &str) -> Option<TypeId> {
        if path.is_empty() {
            return Some(TypeId::ROOT);
        }
        self.by_path.get(path).copied()
    }
    pub fn expect(&self, path: &str) -> TypeId {
        self.find(path).unwrap_or_else(|| panic!("type not found: {path:?}"))
    }
    /// A path's type by its pieces (`["datum", "x"]`), exact.
    pub fn type_by_path<S: AsRef<str>>(&self, pieces: &[S]) -> Option<TypeId> {
        let mut current = TypeId::ROOT;
        for piece in pieces {
            current = *self.ty(current).children.get(piece.as_ref())?;
        }
        Some(current)
    }
    pub fn parent_type(&self, t: TypeId) -> Option<TypeId> {
        self.ty(t).parent_type
    }
    pub fn is_subtype_of(&self, t: TypeId, parent: TypeId) -> bool {
        let mut current = Some(t);
        while let Some(c) = current {
            if c == parent {
                return true;
            }
            current = self.parent_type(c);
        }
        false
    }
    /// Every type in registration order.
    pub fn type_ids(&self) -> impl Iterator<Item = TypeId> {
        (0..self.types.len() as u32).map(TypeId)
    }
    /// `t` and every type under its path, depth first, children in name order.
    pub fn recurse(&self, t: TypeId, f: &mut dyn FnMut(TypeId)) {
        f(t);
        for &child in self.ty(t).children.values() {
            self.recurse(child, f);
        }
    }
    pub fn get_var_declaration(&self, t: TypeId, name: &str) -> Option<&VarDecl> {
        let mut current = Some(t);
        while let Some(c) = current {
            if let Some(decl) = self.ty(c).var(name).and_then(|v| v.declaration.as_ref()) {
                return Some(decl);
            }
            current = self.parent_type(c);
        }
        None
    }
    pub fn get_proc(&self, t: TypeId, name: &str) -> Option<ProcId> {
        let mut current = Some(t);
        while let Some(c) = current {
            if let Some(&slot) = self.ty(c).proc_index.get(name) {
                let len = self.ty(c).procs[slot].1.values.len();
                return Some(ProcId { ty: c, slot: slot as u32, idx: len as u32 - 1 });
            }
            current = self.parent_type(c);
        }
        None
    }
    pub fn get_proc_declaration(&self, t: TypeId, name: &str) -> Option<&ProcDecl> {
        let mut current = Some(t);
        while let Some(c) = current {
            if let Some(decl) = self.ty(c).proc(name).and_then(|p| p.declaration.as_ref()) {
                return Some(decl);
            }
            current = self.parent_type(c);
        }
        None
    }
    /// The procs `t` itself defines, every value, in registration order.
    pub fn self_procs(&self, t: TypeId) -> impl Iterator<Item = ProcId> + '_ {
        self.ty(t).procs.iter().enumerate().flat_map(move |(slot, (_, p))| {
            (0..p.values.len() as u32).map(move |idx| ProcId { ty: t, slot: slot as u32, idx })
        })
    }

    pub fn proc_name(&self, p: ProcId) -> &str {
        &self.ty(p.ty).procs[p.slot as usize].0
    }
    fn type_proc(&self, p: ProcId) -> &TypeProc {
        &self.ty(p.ty).procs[p.slot as usize].1
    }
    pub fn value(&self, p: ProcId) -> &ProcValue {
        &self.type_proc(p).values[p.idx as usize]
    }
    pub fn is_builtin(&self, p: ProcId) -> bool {
        matches!(self.value(p).location, Where::Fixed(l) if l.is_builtins())
    }
    pub fn parent_proc(&self, p: ProcId) -> Option<ProcId> {
        if p.idx > 0 {
            return Some(ProcId { idx: p.idx - 1, ..p });
        }
        let parent = self.parent_type(p.ty)?;
        self.get_proc(parent, self.proc_name(p))
    }
    pub fn get_declaration(&self, p: ProcId) -> Option<&ProcDecl> {
        self.get_proc_declaration(p.ty, self.proc_name(p))
    }
    /// The last value of the proc named like `p` on `p`'s type and on every type under its path.
    pub fn recurse_children(&self, p: ProcId, f: &mut dyn FnMut(ProcId)) {
        let name = self.proc_name(p).to_owned();
        self.recurse(p.ty, &mut |t| {
            if let Some(&slot) = self.ty(t).proc_index.get(&name) {
                let len = self.ty(t).procs[slot].1.values.len();
                f(ProcId { ty: t, slot: slot as u32, idx: len as u32 - 1 });
            }
        });
    }
    /// `/a/b/proc/name`, with `[idx/len]` when the type defines it more than once: SpacemanDMM's spelling.
    pub fn proc_display(&self, p: ProcId) -> String {
        let len = self.type_proc(p).values.len();
        let mut s = format!("{}/proc/{}", self.ty(p.ty).path, self.proc_name(p));
        if len > 1 {
            s.push_str(&format!("[{}/{}]", p.idx, len));
        }
        s
    }

    /// Navigate from `t` along `pieces` (`/` a child, `.` a child of it or of a path parent, `:` a child of it or of a descendant),
    /// as SpacemanDMM navigates a prefab: a `proc`/`verb` step names a proc (its type is the result).
    pub fn navigate_path(&self, t: TypeId, pieces: &[(char, String)]) -> Option<TypeId> {
        let mut next = Some(t);
        if let Some(('/', _)) = pieces.first() {
            next = Some(TypeId::ROOT);
        }
        let mut iter = pieces.iter();
        while let Some((op, name)) = iter.next() {
            let current = next?;
            if name == "proc" || name == "verb" {
                if let Some((_, proc_name)) = iter.next() {
                    return self.get_proc(current, proc_name).map(|p| p.ty);
                }
                return Some(current);
            }
            next = self.navigate(current, *op, name);
        }
        next
    }

    fn navigate(&self, t: TypeId, op: char, name: &str) -> Option<TypeId> {
        match op {
            '/' => self.ty(t).children.get(name).copied(),
            '.' => {
                let mut next = Some(t);
                while let Some(c) = next {
                    if let Some(&child) = self.ty(c).children.get(name) {
                        return Some(child);
                    }
                    next = self.ty(c).parent_path;
                }
                None
            }
            _ => {
                if let Some(&child) = self.ty(t).children.get(name) {
                    return Some(child);
                }
                for &child in self.ty(t).children.values() {
                    if let Some(found) = self.navigate(child, ':', name) {
                        return Some(found);
                    }
                }
                None
            }
        }
    }
}

/// What registering a declaration reports, as SpacemanDMM's object tree does (a hint when a definition follows an override).
pub struct Registered {
    pub hint: Option<Precedes>,
}

/// A definition registered after an override of the same proc.
pub struct Precedes {
    at: Where,
    defined: Where,
    path: String,
    kind: ProcKind,
    name: String,
}

impl Precedes {
    /// SpacemanDMM's hint, placed by `site`.
    pub fn error(&self, site: &dyn super::input::Site) -> dm::DMError {
        let (path, kind, name) = (&self.path, self.kind, &self.name);
        dm::DMError::new(site.place(self.at), format!("override of {path}/{name} precedes definition"))
            .set_severity(dm::Severity::Hint)
            .with_errortype("override_precedes_definition")
            .with_note(site.place(self.defined), format!("{path}/{kind}/{name} is defined here"))
    }
}

/// Builds a [`Model`]: types, vars and procs in the order the caller registers them.
pub struct ModelBuilder {
    model: Model,
}

impl Default for ModelBuilder {
    fn default() -> Self {
        let mut model = Model::default();
        model.types.push(Type {
            path: String::new(),
            location: Where::Fixed(Location::builtins()),
            location_specificity: 0,
            parent_path: None,
            parent_type: None,
            children: BTreeMap::new(),
            vars: Vec::new(),
            var_index: HashMap::new(),
            procs: Vec::new(),
            proc_index: HashMap::new(),
        });
        ModelBuilder { model }
    }
}

impl ModelBuilder {
    /// A builder holding BYOND's builtin types, vars and procs.
    pub fn with_builtins() -> ModelBuilder {
        let mut b = ModelBuilder::default();
        super::builtins::register(&mut b);
        b
    }

    pub fn model(&self) -> &Model {
        &self.model
    }

    fn subtype_or_add(&mut self, location: Where, parent: TypeId, child: &str, len: usize) -> TypeId {
        if let Some(&target) = self.model.ty(parent).children.get(child) {
            let node = &mut self.model.types[target.index()];
            if node.location_specificity > len {
                node.location_specificity = len;
                node.location = location;
            }
            return target;
        }
        let path = format!("{}/{}", self.model.ty(parent).path, child);
        let id = TypeId(self.model.types.len() as u32);
        self.model.types.push(Type {
            path: path.clone(),
            location,
            location_specificity: len,
            parent_path: Some(parent),
            parent_type: None,
            children: BTreeMap::new(),
            vars: Vec::new(),
            var_index: HashMap::new(),
            procs: Vec::new(),
            proc_index: HashMap::new(),
        });
        self.model.types[parent.index()].children.insert(child.to_owned(), id);
        self.model.by_path.insert(path, id);
        id
    }

    /// The type at an absolute path, adding every missing step.
    pub fn add_type_path(&mut self, location: Where, path: &str) -> TypeId {
        let pieces: Vec<&str> = path.split('/').filter(|p| !p.is_empty()).collect();
        let len = pieces.len() + 1;
        let mut current = TypeId::ROOT;
        for piece in pieces {
            current = self.subtype_or_add(location, current, piece, len);
        }
        current
    }

    fn insert_var(&mut self, ty: TypeId, name: &str, value_location: Where, declaration: Option<VarDecl>) {
        let t = &mut self.model.types[ty.index()];
        match t.var_index.get(name) {
            Some(&i) => {
                let v = &mut t.vars[i].1;
                if declaration.is_some() {
                    v.declaration = declaration;
                }
                v.value_location = value_location;
            }
            None => {
                t.var_index.insert(name.to_owned(), t.vars.len());
                t.vars.push((name.to_owned(), TypeVar { value_location, declaration }));
            }
        }
    }

    pub fn declare_var(&mut self, ty: TypeId, name: &str, location: Where, flags: VarFlags, type_path: Vec<String>) {
        self.insert_var(ty, name, location, Some(VarDecl { flags, type_path, location }));
    }

    pub fn override_var(&mut self, ty: TypeId, name: &str, location: Where) {
        self.insert_var(ty, name, location, None);
    }

    /// A builtin var: registered once (a repeat keeps the first).
    pub fn builtin_var(&mut self, ty: TypeId, name: &str, declared: Option<(VarFlags, Vec<String>)>) {
        let t = &mut self.model.types[ty.index()];
        if t.var_index.contains_key(name) {
            return;
        }
        let location = Where::Fixed(Location::builtins());
        t.var_index.insert(name.to_owned(), t.vars.len());
        t.vars.push((
            name.to_owned(),
            TypeVar { value_location: location, declaration: declared.map(|(flags, type_path)| VarDecl { flags, type_path, location }) },
        ));
    }

    /// A proc definition (with `declaration`) or override on `ty`. A definition after a value already registered goes first (DM
    /// moves the declaration before the override), reported with SpacemanDMM's hint.
    pub fn add_proc(&mut self, ty: TypeId, name: &str, declaration: Option<ProcDecl>, value: ProcValue) -> Registered {
        let t = &mut self.model.types[ty.index()];
        let slot = match t.proc_index.get(name) {
            Some(&i) => i,
            None => {
                t.proc_index.insert(name.to_owned(), t.procs.len());
                t.procs.push((name.to_owned(), TypeProc::default()));
                t.procs.len() - 1
            }
        };
        let path = t.path.clone();
        let proc = &mut t.procs[slot].1;
        let location = value.location;
        let kind = declaration.as_ref().map(|d| d.kind);
        let mut hint = None;
        if let Some(decl) = declaration {
            if proc.declaration.is_none() {
                proc.declaration = Some(decl);
            }
        }
        match kind {
            Some(kind) if !proc.values.is_empty() => {
                hint = Some(Precedes { at: proc.values[0].location, defined: location, path, kind, name: name.to_owned() });
                proc.values.insert(0, value);
            }
            _ => proc.values.push(value),
        }
        Registered { hint }
    }

    /// Parent types as SpacemanDMM assigns them: the root types have none, `/atom`, `/turf`, `/area`, `/obj` and `/mob` theirs, a
    /// type with `parent_type` the one it names, any other its path parent (`/datum` for a top-level path, the root for `/client`).
    pub fn finish(mut self, parent_overrides: &std::collections::HashMap<TypeId, String>) -> Model {
        let paths: Vec<(String, TypeId)> = {
            let mut v: Vec<_> = self.model.by_path.iter().map(|(p, &t)| (p.clone(), t)).collect();
            v.sort();
            v
        };
        for (path, t) in paths {
            let parent = match path.as_str() {
                "/datum" | "/list" | "/alist" | "/savefile" | "/world" | "/vector" | "/pixloc" | "/callee" => Some(TypeId::ROOT),
                "/atom" => self.model.find("/datum"),
                "/turf" | "/area" => self.model.find("/atom"),
                "/obj" | "/mob" => self.model.find("/atom/movable"),
                _ => match parent_overrides.get(&t) {
                    Some(named) => self.model.find(named.trim_end_matches('/')),
                    None => match path.rfind('/') {
                        Some(0) if path == "/client" => Some(TypeId::ROOT),
                        Some(0) => self.model.find("/datum"),
                        Some(i) => self.model.find(&path[..i]),
                        None => Some(TypeId::ROOT),
                    },
                },
            };
            self.model.types[t.index()].parent_type = parent;
        }
        self.model
    }
}
