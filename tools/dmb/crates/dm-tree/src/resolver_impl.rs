use super::*;

impl dm_ir::Resolver for SemanticTree {
    fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
        if let dm_ir::ReadDomain::OwnerHierarchy(owner) = domain {
            let base = self.owner_hierarchy.get(&owner)?;
            // Two states of the current completeness gate are disjoint, while
            // the exact retained ancestor receipt owns the process-local token.
            return Some((base << 1) | u128::from(self.inventory.hierarchy_certified));
        }
        if let dm_ir::ReadDomain::OwnerCallable(query) = domain {
            let selection = match query {
                dm_ir::ResolveQuery::Signature(path) => {
                    if matches!(
                        dm_ir::Resolver::resolve(self, query),
                        dm_ir::ResolvedMeaning::Unsupported(_)
                    ) {
                        return None;
                    }
                    self.signature_selection(path)?
                }
                dm_ir::ResolveQuery::HasMemberProc { owner, name } => {
                    return self
                        .owner_certificate_issuer
                        .as_ref()
                        .and_then(|issuer| issuer.demanded_presence(self, owner, name));
                }
                dm_ir::ResolveQuery::Proc { owner, name, verb }
                | dm_ir::ResolveQuery::ProcedureValue {
                    owner, name, verb, ..
                }
                | dm_ir::ResolveQuery::MethodProcedureValue { owner, name, verb } => {
                    (owner, name, verb)
                }
                dm_ir::ResolveQuery::GlobalProc(name) => (SymbolId::of("/"), name, false),
                dm_ir::ResolveQuery::OverrideChain { owner, .. } => {
                    return self.owner_callables.get(&owner).copied()
                }
                _ => return None,
            };
            // Root-local name receipts already have no ancestor dependency.
            if selection.0 == SymbolId::of("/") {
                if let Some(token) = self.owner_callable_selections.get(&selection) {
                    return Some(*token);
                }
            }
            if let Some(issuer) = &self.owner_certificate_issuer {
                if let Some(token) = issuer.demanded_selection(self, selection) {
                    return Some(token);
                }
            }
            return self
                .owner_callable_selections
                .get(&selection)
                .copied()
                .or_else(|| self.owner_callables.get(&selection.0).copied());
        }
        if let dm_ir::ReadDomain::OwnerVariable(query) = domain {
            let (owner, name) = match query {
                dm_ir::ResolveQuery::HasMemberVar { owner, name }
                | dm_ir::ResolveQuery::DeclaredVarType { owner, name }
                | dm_ir::ResolveQuery::VarStorage { owner, name }
                | dm_ir::ResolveQuery::StaticVar { owner, name } => (owner, name),
                _ => return None,
            };
            if let Some(token) = self.owner_variable_selections.get(&(owner, name)) {
                return Some(*token);
            }
            return self
                .owner_certificate_issuer
                .as_ref()
                .and_then(|issuer| issuer.demanded_variable(self, owner, name));
        }
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
                    let mut bytes = if matches!(query, Q::Proc { .. } | Q::GlobalProc(_)) {
                        Vec::new()
                    } else {
                        node.content.to_le_bytes().to_vec()
                    };
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
                let Some((owner, name, verb)) = self.signature_selection(path) else {
                    return self.complete_answer(query, M::Missing);
                };
                let kind = if verb {
                    MemberKind::Verb
                } else {
                    MemberKind::Proc
                };
                self.lookup_type(owner)
                    .and_then(|id| self.resolve(id, name, kind))
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

impl SemanticTree {
    // Both semantic resolution and receipt selection decode the same issued
    // current spelling. A symbol hash alone is never a procedure path proof.
    fn signature_selection(&self, path: SymbolId) -> Option<(SymbolId, SymbolId, bool)> {
        let text = self.symbols.text(path)?;
        let (owner, name) = text
            .rsplit_once("/proc/")
            .or_else(|| text.rsplit_once("/verb/"))?;
        Some((
            SymbolId::of(if owner.is_empty() { "/" } else { owner }),
            SymbolId::of(name),
            text.contains("/verb/"),
        ))
    }
}
