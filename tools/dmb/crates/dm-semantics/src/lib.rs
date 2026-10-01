//! Ordered declaration indexing for the DM front end. The index preserves
//! source/include order independently from semantic path lookup. IDs here are
//! compiler-local and must be relocated by the deterministic DMB linker.

use dm_ir::{ProcId, Span, TypeId, TypePath, VarId};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ProcKind {
    Proc,
    Verb,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum DeclarationKind {
    Type {
        path: TypePath,
        explicit_parent: Option<TypePath>,
    },
    Var {
        owner: TypePath,
        name: String,
        is_static: bool,
    },
    Proc {
        owner: TypePath,
        name: String,
        kind: ProcKind,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Declaration {
    pub kind: DeclarationKind,
    pub span: Span,
}

/// Stable semantic lookup key. `occurrence` differentiates repeated definitions
/// of one member; callers may derive it from source order within an include.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum SemanticKey {
    Type(TypePath),
    Var {
        owner: TypePath,
        name: String,
        occurrence: u32,
    },
    Proc {
        owner: TypePath,
        name: String,
        kind: ProcKind,
        occurrence: u32,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LedgerEntry {
    Type { id: TypeId, span: Span },
    Var { id: VarId, span: Span },
    Proc { id: ProcId, span: Span },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TypeDef {
    pub id: TypeId,
    pub path: TypePath,
    pub parent: Option<TypeId>,
    pub explicit_parent: Option<TypePath>,
    pub declarations: Vec<Span>,
    pub synthetic: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VarDef {
    pub id: VarId,
    pub owner: TypeId,
    pub name: String,
    pub is_static: bool,
    pub span: Span,
    pub occurrence: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProcDef {
    pub id: ProcId,
    pub owner: TypeId,
    pub name: String,
    pub kind: ProcKind,
    pub span: Span,
    pub occurrence: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum IndexError {
    MissingParent { path: TypePath, parent: TypePath },
    InheritanceCycle { path: TypePath },
}

#[derive(Clone, Debug, Default)]
pub struct DeclarationIndex {
    pub types: Vec<TypeDef>,
    pub vars: Vec<VarDef>,
    pub procs: Vec<ProcDef>,
    pub ledger: Vec<LedgerEntry>,
    path_to_type: BTreeMap<TypePath, TypeId>,
    local_vars: BTreeMap<(TypeId, String), Vec<VarId>>,
    local_procs: BTreeMap<(TypeId, String, ProcKind), Vec<ProcId>>,
}

impl DeclarationIndex {
    /// Build from declarations in actual DME/include order. Implicit ancestor
    /// types are materialized at first reference, so their insertion is stable.
    pub fn build(
        declarations: impl IntoIterator<Item = Declaration>,
    ) -> Result<Self, Vec<IndexError>> {
        let mut index = Self::default();
        let root = TypePath::parse("/").expect("root path");
        index.ensure_type(&root);
        for declaration in declarations {
            match declaration.kind {
                DeclarationKind::Type {
                    path,
                    explicit_parent,
                } => {
                    let id = index.ensure_type(&path);
                    let ty = &mut index.types[id.index()];
                    ty.synthetic = false;
                    ty.declarations.push(declaration.span);
                    if explicit_parent.is_some() {
                        ty.explicit_parent = explicit_parent;
                    }
                    index.ledger.push(LedgerEntry::Type {
                        id,
                        span: declaration.span,
                    });
                }
                DeclarationKind::Var {
                    owner,
                    name,
                    is_static,
                } => {
                    let owner_id = index.ensure_type(&owner);
                    let key = (owner_id, name.clone());
                    let occurrence = index.local_vars.get(&key).map_or(0, |v| v.len() as u32);
                    let id = VarId(index.vars.len() as u32);
                    index.vars.push(VarDef {
                        id,
                        owner: owner_id,
                        name,
                        is_static,
                        span: declaration.span,
                        occurrence,
                    });
                    index.local_vars.entry(key).or_default().push(id);
                    index.ledger.push(LedgerEntry::Var {
                        id,
                        span: declaration.span,
                    });
                }
                DeclarationKind::Proc { owner, name, kind } => {
                    let owner_id = index.ensure_type(&owner);
                    let key = (owner_id, name.clone(), kind);
                    let occurrence = index.local_procs.get(&key).map_or(0, |v| v.len() as u32);
                    let id = ProcId(index.procs.len() as u32);
                    index.procs.push(ProcDef {
                        id,
                        owner: owner_id,
                        name,
                        kind,
                        span: declaration.span,
                        occurrence,
                    });
                    index.local_procs.entry(key).or_default().push(id);
                    index.ledger.push(LedgerEntry::Proc {
                        id,
                        span: declaration.span,
                    });
                }
            }
        }
        index.resolve_parents()
    }

    pub fn type_id(&self, path: &TypePath) -> Option<TypeId> {
        self.path_to_type.get(path).copied()
    }

    pub fn local_var(&self, owner: TypeId, name: &str) -> Option<VarId> {
        self.local_vars
            .get(&(owner, name.into()))
            .and_then(|ids| ids.last())
            .copied()
    }

    pub fn local_proc(&self, owner: TypeId, name: &str, kind: ProcKind) -> Option<ProcId> {
        self.local_procs
            .get(&(owner, name.into(), kind))
            .and_then(|ids| ids.last())
            .copied()
    }

    pub fn resolve_var(&self, owner: TypeId, name: &str) -> Option<VarId> {
        self.ancestors(owner)
            .find_map(|id| self.local_var(id, name))
    }

    pub fn resolve_proc(&self, owner: TypeId, name: &str, kind: ProcKind) -> Option<ProcId> {
        self.ancestors(owner)
            .find_map(|id| self.local_proc(id, name, kind))
    }

    /// Return the definition reached by `..()` from this proc. Reopened
    /// definitions on the same type form an override chain before inheritance.
    pub fn overridden_proc(&self, current: ProcId) -> Option<ProcId> {
        let definition = self.procs.get(current.index())?;
        let key = (definition.owner, definition.name.clone(), definition.kind);
        let chain = self.local_procs.get(&key)?;
        if definition.occurrence > 0 {
            return chain.get(definition.occurrence as usize - 1).copied();
        }
        let parent = self.types[definition.owner.index()].parent?;
        self.ancestors(parent)
            .find_map(|id| self.local_proc(id, &definition.name, definition.kind))
    }

    pub fn semantic_key_for_proc(&self, id: ProcId) -> Option<SemanticKey> {
        let definition = self.procs.get(id.index())?;
        Some(SemanticKey::Proc {
            owner: self.types[definition.owner.index()].path.clone(),
            name: definition.name.clone(),
            kind: definition.kind,
            occurrence: definition.occurrence,
        })
    }

    pub fn semantic_key_for_var(&self, id: VarId) -> Option<SemanticKey> {
        let definition = self.vars.get(id.index())?;
        Some(SemanticKey::Var {
            owner: self.types[definition.owner.index()].path.clone(),
            name: definition.name.clone(),
            occurrence: definition.occurrence,
        })
    }

    pub fn ancestors(&self, from: TypeId) -> Ancestors<'_> {
        Ancestors {
            index: self,
            next: Some(from),
        }
    }

    fn ensure_type(&mut self, path: &TypePath) -> TypeId {
        if let Some(id) = self.path_to_type.get(path) {
            return *id;
        }
        let parent = path.parent().map(|p| self.ensure_type(&p));
        let id = TypeId(self.types.len() as u32);
        self.types.push(TypeDef {
            id,
            path: path.clone(),
            parent,
            explicit_parent: None,
            declarations: Vec::new(),
            synthetic: true,
        });
        self.path_to_type.insert(path.clone(), id);
        id
    }

    fn resolve_parents(mut self) -> Result<Self, Vec<IndexError>> {
        let mut errors = Vec::new();
        for id in 0..self.types.len() {
            if let Some(parent_path) = self.types[id].explicit_parent.clone() {
                match self.path_to_type.get(&parent_path) {
                    Some(parent) => self.types[id].parent = Some(*parent),
                    None => errors.push(IndexError::MissingParent {
                        path: self.types[id].path.clone(),
                        parent: parent_path,
                    }),
                }
            }
        }
        for start in 0..self.types.len() {
            let mut seen = BTreeSet::new();
            let mut current = Some(TypeId(start as u32));
            while let Some(id) = current {
                if !seen.insert(id) {
                    errors.push(IndexError::InheritanceCycle {
                        path: self.types[start].path.clone(),
                    });
                    break;
                }
                current = self.types[id.index()].parent;
            }
        }
        if errors.is_empty() {
            Ok(self)
        } else {
            Err(errors)
        }
    }
}

pub struct Ancestors<'a> {
    index: &'a DeclarationIndex,
    next: Option<TypeId>,
}

impl Iterator for Ancestors<'_> {
    type Item = TypeId;
    fn next(&mut self) -> Option<Self::Item> {
        let id = self.next?;
        self.next = self.index.types.get(id.index()).and_then(|ty| ty.parent);
        Some(id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::FileId;

    fn path(value: &str) -> TypePath {
        TypePath::parse(value).unwrap()
    }
    fn span(n: u32) -> Span {
        Span::new(FileId(0), n, n + 1).unwrap()
    }
    fn ty(value: &str, parent: Option<&str>, n: u32) -> Declaration {
        Declaration {
            kind: DeclarationKind::Type {
                path: path(value),
                explicit_parent: parent.map(path),
            },
            span: span(n),
        }
    }
    fn proc(owner: &str, name: &str, n: u32) -> Declaration {
        Declaration {
            kind: DeclarationKind::Proc {
                owner: path(owner),
                name: name.into(),
                kind: ProcKind::Proc,
            },
            span: span(n),
        }
    }
    fn var(owner: &str, name: &str, n: u32) -> Declaration {
        Declaration {
            kind: DeclarationKind::Var {
                owner: path(owner),
                name: name.into(),
                is_static: false,
            },
            span: span(n),
        }
    }

    #[test]
    fn reopened_member_wins_and_ledger_preserves_order() {
        let index = DeclarationIndex::build([
            ty("/obj", None, 0),
            proc("/obj", "attack", 1),
            ty("/obj", None, 2),
            proc("/obj", "attack", 3),
        ])
        .unwrap();
        let obj = index.type_id(&path("/obj")).unwrap();
        let effective = index.local_proc(obj, "attack", ProcKind::Proc).unwrap();
        assert_eq!(index.procs[effective.index()].span, span(3));
        assert_eq!(index.procs[effective.index()].occurrence, 1);
        assert_eq!(
            index.types[obj.index()].declarations,
            vec![span(0), span(2)]
        );
        assert!(matches!(index.ledger[1], LedgerEntry::Proc { span: at, .. } if at == span(1)));
    }

    #[test]
    fn implicit_ancestors_and_inherited_lookup() {
        let index = DeclarationIndex::build([
            var("/obj", "weight", 0),
            proc("/obj", "attack", 1),
            ty("/obj/item/sword", None, 2),
        ])
        .unwrap();
        let item = index.type_id(&path("/obj/item")).unwrap();
        assert!(index.types[item.index()].synthetic);
        let sword = index.type_id(&path("/obj/item/sword")).unwrap();
        assert_eq!(
            index.vars[index.resolve_var(sword, "weight").unwrap().index()].name,
            "weight"
        );
        assert!(index
            .resolve_proc(sword, "attack", ProcKind::Proc)
            .is_some());
    }

    #[test]
    fn explicit_parent_retargets_lookup() {
        let index = DeclarationIndex::build([
            var("/obj", "weight", 0),
            var("/datum", "energy", 1),
            ty("/obj/item", Some("/datum"), 2),
        ])
        .unwrap();
        let item = index.type_id(&path("/obj/item")).unwrap();
        assert!(index.resolve_var(item, "energy").is_some());
        assert!(index.resolve_var(item, "weight").is_none());
    }

    #[test]
    fn cycle_and_missing_parent_are_errors() {
        let cycle = DeclarationIndex::build([ty("/a", Some("/b"), 0), ty("/b", Some("/a"), 1)])
            .unwrap_err();
        assert!(cycle
            .iter()
            .any(|e| matches!(e, IndexError::InheritanceCycle { .. })));
        let missing = DeclarationIndex::build([ty("/a", Some("/missing"), 0)]).unwrap_err();
        assert!(missing
            .iter()
            .any(|e| matches!(e, IndexError::MissingParent { .. })));
    }

    #[test]
    fn parent_call_follows_reopen_then_inheritance() {
        let index = DeclarationIndex::build([
            proc("/obj", "attack", 0),
            proc("/obj/item", "attack", 1),
            proc("/obj/item", "attack", 2),
        ])
        .unwrap();
        assert_eq!(index.overridden_proc(ProcId(2)), Some(ProcId(1)));
        assert_eq!(index.overridden_proc(ProcId(1)), Some(ProcId(0)));
        assert_eq!(index.overridden_proc(ProcId(0)), None);
        assert_eq!(
            index.semantic_key_for_proc(ProcId(2)),
            Some(SemanticKey::Proc {
                owner: path("/obj/item"),
                name: "attack".into(),
                kind: ProcKind::Proc,
                occurrence: 1,
            })
        );
    }
}
