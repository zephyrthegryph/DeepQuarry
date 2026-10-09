use super::*;

impl dm_ir::Resolver for SemanticTree {
    fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
        if domain != dm_ir::ReadDomain::Tree {
            return None;
        }
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"dm-tree-answer-domain-v1\0");
        hash.update(&self.identity.to_le_bytes());
        Some(hash.digest128())
    }

    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M};
        let root = SymbolId::of("/");
        let member = |owner, name, kind| {
            self.lookup_type(owner)
                .and_then(|id| self.resolve(id, name, kind))
                .map(|id| {
                    let node = &self.members[id.index()];
                    if node.metadata.inherited_opaque.is_some() {
                        return M::Unsupported(query);
                    }
                    let mut bytes = node.content.to_le_bytes().to_vec();
                    bytes.extend_from_slice(&metadata_fingerprint(&node.metadata).to_le_bytes());
                    M::Member {
                        owner: self.types[node.owner.index()].path,
                        name: node.name,
                        data: Arc::clone(&node.metadata),
                        fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes),
                    }
                })
                .unwrap_or(M::Missing)
        };
        let result = match query {
            Q::Type(path) => self
                .lookup_type(path)
                .map(|_| M::Symbol(path))
                .unwrap_or(M::Missing),
            Q::Parent(path) => self
                .lookup_type(path)
                .and_then(|id| self.parent(id))
                .map(|id| M::Symbol(self.types[id.index()].path))
                .unwrap_or(M::Missing),
            Q::Ancestry(path) => {
                let Some(mut id) = self.lookup_type(path) else {
                    return self.complete_answer(query, M::Missing);
                };
                let mut paths = Vec::new();
                loop {
                    paths.push(self.types[id.index()].path);
                    match self.parent(id) {
                        Some(parent) => id = parent,
                        None => break,
                    }
                }
                M::Symbols(paths)
            }
            Q::Var { owner, name } => member(owner, name, MemberKind::Var),
            Q::Proc { owner, name, verb } => member(
                owner,
                name,
                if verb {
                    MemberKind::Verb
                } else {
                    MemberKind::Proc
                },
            ),
            Q::ProcedureValue {
                owner,
                name,
                verb,
                formal,
            } => {
                let kind = if verb {
                    MemberKind::Verb
                } else {
                    MemberKind::Proc
                };
                let selected = self
                    .lookup_type(owner)
                    .and_then(|id| self.resolve(id, name, kind))
                    .and_then(|head| {
                        if !formal {
                            return Some(head);
                        }
                        self.override_chain(head).into_iter().find(|id| {
                            self.member(*id).is_some_and(|node| {
                                self.types[node.owner.index()].path == owner
                                    && node.definition == DefinitionMode::Declare
                            })
                        })
                    });
                selected
                    .and_then(|id| {
                        let node = self.member(id)?;
                        node.metadata.procedure.as_ref()?;
                        let occurrence = self
                            .override_chain(id)
                            .into_iter()
                            .filter(|previous| {
                                self.member(*previous).is_some_and(|other| {
                                    other.owner == node.owner
                                        && other.name == node.name
                                        && other.kind == node.kind
                                })
                            })
                            .count()
                            .checked_sub(1)?;
                        Some(M::Value(dm_ir::SemanticValue::Procedure(
                            dm_ir::ProcedureIdentity {
                                owner: self.types[node.owner.index()].path,
                                name,
                                verb,
                                occurrence: u32::try_from(occurrence).ok()?,
                            },
                        )))
                    })
                    .unwrap_or(M::Missing)
            }
            Q::MethodProcedureValue { owner, name, verb } => {
                let kind = if verb {
                    MemberKind::Verb
                } else {
                    MemberKind::Proc
                };
                self.lookup_type(owner)
                    .and_then(|id| self.resolve(id, name, kind))
                    .and_then(|head| {
                        // The chain is source-certified, including inherited
                        // links and implicit-before-formal normalization. Use
                        // the actual formal anchor, never receiver spelling or
                        // a guessed occurrence zero.
                        self.override_chain(head).into_iter().find(|id| {
                            self.member(*id)
                                .is_some_and(|node| node.definition == DefinitionMode::Declare)
                        })
                    })
                    .and_then(|id| {
                        let node = self.member(id)?;
                        node.metadata.procedure.as_ref()?;
                        let occurrence = self
                            .override_chain(id)
                            .into_iter()
                            .filter(|previous| {
                                self.member(*previous).is_some_and(|other| {
                                    other.owner == node.owner
                                        && other.name == node.name
                                        && other.kind == node.kind
                                })
                            })
                            .count()
                            .checked_sub(1)?;
                        Some(M::Value(dm_ir::SemanticValue::Procedure(
                            dm_ir::ProcedureIdentity {
                                owner: self.types[node.owner.index()].path,
                                name: node.name,
                                verb: node.kind == MemberKind::Verb,
                                occurrence: u32::try_from(occurrence).ok()?,
                            },
                        )))
                    })
                    .unwrap_or(M::Missing)
            }
            Q::GlobalVar(name) => member(root, name, MemberKind::Var),
            Q::GlobalProc(name) => member(root, name, MemberKind::Proc),
            Q::OverrideChain { owner, name, verb } => {
                let kind = if verb {
                    MemberKind::Verb
                } else {
                    MemberKind::Proc
                };
                self.lookup_type(owner)
                    .and_then(|id| self.resolve(id, name, kind))
                    .map(|id| {
                        M::Members(
                            self.override_chain(id)
                                .iter()
                                .map(|id| {
                                    let node = &self.members[id.index()];
                                    let mut bytes = node.content.to_le_bytes().to_vec();
                                    bytes.extend_from_slice(
                                        &metadata_fingerprint(&node.metadata).to_le_bytes(),
                                    );
                                    M::Member {
                                        owner: self.types[node.owner.index()].path,
                                        name: node.name,
                                        data: Arc::clone(&node.metadata),
                                        fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes),
                                    }
                                })
                                .collect(),
                        )
                    })
                    .unwrap_or(M::Missing)
            }
            // Phase1 adapter must populate typed constant/signature/resource
            // domains before callers may issue these unsupported queries.
            Q::Signature(path) => {
                let Some(text) = self.symbols.text(path) else {
                    return self.complete_answer(query, M::Missing);
                };
                let Some((owner, name)) = text
                    .rsplit_once("/proc/")
                    .or_else(|| text.rsplit_once("/verb/"))
                else {
                    return self.complete_answer(query, M::Missing);
                };
                let kind = if text.contains("/verb/") {
                    MemberKind::Verb
                } else {
                    MemberKind::Proc
                };
                self.lookup_type(SymbolId::of(if owner.is_empty() { "/" } else { owner }))
                    .and_then(|id| self.resolve(id, SymbolId::of(name), kind))
                    .map(|id| {
                        let node = &self.members[id.index()];
                        match &node.metadata.procedure {
                            Some(bytes) => M::Member {
                                owner: self.types[node.owner.index()].path,
                                name: node.name,
                                data: Arc::clone(&node.metadata),
                                fingerprint: xxhash_rust::xxh3::xxh3_128(
                                    &bytes.signature.canonical_bytes(),
                                ),
                            },
                            None => M::Unsupported(query),
                        }
                    })
                    .unwrap_or(M::Missing)
            }
            Q::Constant { owner, name } => self
                .lookup_type(owner)
                .and_then(|id| self.resolve(id, name, MemberKind::Var))
                .map(|id| {
                    let node = &self.members[id.index()];
                    if node.metadata.inherited_opaque.is_some() {
                        return M::Unsupported(query);
                    }
                    match &node.metadata.resolved_constant {
                        Some(bytes) => M::Member {
                            owner: self.types[node.owner.index()].path,
                            name: node.name,
                            data: Arc::clone(&node.metadata),
                            fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes.canonical_bytes()),
                        },
                        None => M::Unsupported(query),
                    }
                })
                .unwrap_or(M::Missing),
            Q::HasMemberVar { .. }
            | Q::DeclaredVarType { .. }
            | Q::VarStorage { .. }
            | Q::StaticVar { .. }
            | Q::UniqueStaticVar(_)
            | Q::HasMemberProc { .. } => {
                // Inventory queries certify their own positive/negative coverage.
                // A known instance field is authoritatively not a shared slot,
                // even while unrelated intrinsic member names remain unknown.
                return self.resolve_inventory(query);
            }
            Q::Resource(_)
            | Q::ResourceIn { .. }
            | Q::ProcedureStatic { .. }
            | Q::RuntimeType(_)
            | Q::PredefinedConstant(_) => M::Unsupported(query),
        };
        self.complete_answer(query, result)
    }
}

#[cfg(test)]
#[path = "resolver_method_tests.rs"]
mod method_tests;
