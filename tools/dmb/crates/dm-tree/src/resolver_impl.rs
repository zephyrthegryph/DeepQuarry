use super::*;

impl dm_ir::Resolver for SemanticTree {
    fn source_owner(&self) -> Option<*const ()> {
        Some(std::ptr::from_ref(self).cast())
    }

    fn observes_reads(&self) -> bool {
        false
    }

    /// The declarations' identity: every answer of the tree is a function of it.
    fn answer_world(&self) -> Option<u128> {
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
                        fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes).into(),
                    }
                })
                .unwrap_or(M::Missing)
        };
        let result = match query {
            Q::CheckerIntrinsicCallable {
                profile,
                owner,
                name,
                verb,
            } => {
                return self.resolve_checker_builtin(
                    query,
                    profile,
                    owner,
                    name,
                    if verb {
                        MemberKind::Verb
                    } else {
                        MemberKind::Proc
                    },
                    true,
                )
            }
            Q::CheckerBuiltinVar {
                profile,
                owner,
                name,
            } => {
                return self.resolve_checker_builtin(
                    query,
                    profile,
                    owner,
                    name,
                    MemberKind::Var,
                    false,
                )
            }
            Q::CheckerBuiltinProc {
                profile,
                owner,
                name,
                verb,
            } => {
                return self.resolve_checker_builtin(
                    query,
                    profile,
                    owner,
                    name,
                    if verb {
                        MemberKind::Verb
                    } else {
                        MemberKind::Proc
                    },
                    false,
                )
            }
            Q::CertifiedHierarchy { kind, path } => {
                return self
                    .certified_hierarchy()
                    .map(|view| view.answer(kind, path))
                    .unwrap_or(M::Unsupported(query));
            }
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
                if let Some(paths) = self.owner_ancestry.get(&path) {
                    return self.complete_answer(query, M::Symbols(Arc::clone(paths)));
                }
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
                M::Symbols(paths.into())
            }
            Q::SourceVarDeclaration { owner, name } => {
                return self.source_var_declaration(owner, name, query)
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
            Q::MemberCallableVerbName(name) => {
                let flags = self
                    .member_callable_name_storage()
                    .get(&name)
                    .copied()
                    .unwrap_or(0);
                return match flags {
                    flags if flags & 1 != 0 => M::Presence(false),
                    flags if flags & 2 != 0 => M::Presence(true),
                    _ => M::Unsupported(query),
                };
            }
            Q::MemberCallableName(name) => {
                return if self.source_member_callable_name(name) == Some(true) {
                    M::Presence(true)
                } else {
                    M::Unsupported(query)
                };
            }
            Q::GlobalVar(name) => member(root, name, MemberKind::Var),
            Q::GlobalProc(name) => member(root, name, MemberKind::Proc),
            Q::DeclarationChain { owner, name, verb } => {
                self.source_declaration_chain(owner, name, verb, query)
            }
            Q::SourceDeclarationChain { owner, name, verb } => {
                return self.source_declaration_chain(owner, name, verb, query)
            }
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
                                        fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes).into(),
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
                                )
                                .into(),
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
                            fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes.canonical_bytes())
                                .into(),
                        },
                        None => M::Unsupported(query),
                    }
                })
                .unwrap_or(M::Missing),
            Q::IntrinsicCallable { .. }
            | Q::IntrinsicCallableName(_)
            | Q::HasMemberVar { .. }
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

impl SemanticTree {
    fn source_declaration_chain(&self,owner:SymbolId,name:SymbolId,verb:bool,query:dm_ir::ResolveQuery)->dm_ir::ResolvedMeaning {
        self.source_declaration_chain_using(owner,name,verb,query,None).expect("ordinary native declaration chain allocation failed")
    }
    fn source_declaration_chain_using(&self,owner:SymbolId,name:SymbolId,verb:bool,query:dm_ir::ResolveQuery,mut work:Option<&mut dyn dm_ir::CanonicalWork>)->std::io::Result<dm_ir::ResolvedMeaning> {
        use dm_ir::ResolvedMeaning as M;
        let kind=if verb{MemberKind::Verb}else{MemberKind::Proc};
        let identity=|id:MemberId|->Option<dm_ir::ProcedureIdentity>{let node=self.member(id)?;Some(dm_ir::ProcedureIdentity{owner:self.types[node.owner.index()].path,name:node.name,verb:node.kind==MemberKind::Verb,occurrence:self.member_occurrence(id)?})};
        let Some(head)=self.lookup_type(owner).and_then(|id|self.resolve(id,name,kind))else{return Ok(M::Missing)};
        let mut count=0usize;
        for _ in self.override_chain_iter(head){if let Some(work)=&mut work{work.poll()?;}count=count.checked_add(1).filter(|n|*n<=self.members().len()).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,"native declaration chain is cyclic"))?;}
        let bound=count.checked_mul(4).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native declaration chain capacity overflow"))?;
        if let Some(work)=&mut work{work.reserve(bound.checked_mul(std::mem::size_of::<M>()+std::mem::size_of::<dm_ir::ProcedureIdentity>()).and_then(|n|n.checked_add(256)).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native declaration chain allocation geometry overflow"))?)?;}
        let mut rows=Vec::new();rows.try_reserve_exact(count).map_err(|e|std::io::Error::new(std::io::ErrorKind::OutOfMemory,e))?;
        if rows.capacity()>bound{return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native declaration chain allocator exposed excess capacity"))}
        for id in self.override_chain_iter(head){
            if let Some(work)=&mut work{work.poll()?;}
            let Some(node)=self.member(id)else{return Ok(M::Unsupported(query))};
            let Some(actual_identity)=identity(id)else{return Ok(M::Unsupported(query))};
            let previous=match node.previous{Some(previous)=>{let Some(previous)=identity(previous)else{return Ok(M::Unsupported(query))};Some(Box::new(previous))},None=>None};
            rows.push(M::Declaration{identity:actual_identity,definition:match node.definition{DefinitionMode::Declare=>dm_ir::ProcedureDefinition::Declare,DefinitionMode::Override=>dm_ir::ProcedureDefinition::Override,DefinitionMode::Reopen=>dm_ir::ProcedureDefinition::Reopen,DefinitionMode::Implicit=>dm_ir::ProcedureDefinition::Implicit},previous,data:Arc::clone(&node.metadata)});
        }
        Ok(M::Members(rows.into()))
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
impl SemanticTree {
    /// Exact captured source formals; runtime-only fields and default-value
    /// overrides never fabricate an authored declaration or declared type.
    pub fn source_formal_variable_member(
        &self,
        owner: SymbolId,
        name: SymbolId,
    ) -> Result<Option<crate::MemberId>, &'static str> {
        let ty = self
            .lookup_type(owner)
            .ok_or("formal variable owner unavailable")?;
        let Some(mut id) = self.resolve(ty, name, MemberKind::Var) else {
            return Ok(None);
        };
        loop {
            let node = self
                .member(id)
                .ok_or("formal variable member unavailable")?;
            if node.kind != MemberKind::Var {
                return Err("formal variable kind unavailable");
            }
            match node.definition {
                DefinitionMode::Declare => {
                    if self.member_occurrence(id).is_none()
                        || node.metadata.inherited_opaque.is_some()
                    {
                        return Err("formal variable lacks exact authored source");
                    }
                    return Ok(Some(id));
                }
                DefinitionMode::Override => (),
                _ => return Err("formal variable definition mode unavailable"),
            }
            let Some(previous) = node.previous else {
                return Ok(None);
            };
            id = previous;
        }
    }
    fn source_var_declaration(&self,owner:SymbolId,name:SymbolId,query:dm_ir::ResolveQuery)->dm_ir::ResolvedMeaning {
        self.source_var_declaration_using(owner,name,query,&mut|data|Ok(xxhash_rust::xxh3::xxh3_128(&data.canonical_bytes()).into()))
            .expect("ordinary native source declaration encoding failed")
    }
    fn source_var_declaration_using(&self,owner:SymbolId,name:SymbolId,query:dm_ir::ResolveQuery,fingerprint:&mut dyn FnMut(&MemberMetadata)->std::io::Result<dm_ir::PackedU128>)->std::io::Result<dm_ir::ResolvedMeaning> {
        use dm_ir::ResolvedMeaning as M;
        Ok(match self.source_formal_variable_member(owner, name) {
            Ok(Some(id)) => {
                let node = self
                    .member(id)
                    .expect("formal selection issued this native member");
                let data = std::sync::Arc::clone(&node.metadata);
                M::Member {
                    owner: self.types[node.owner.index()].path,
                    name,
                    fingerprint: fingerprint(&data)?,
                    data,
                }
            }
            Ok(None) => M::Missing,
            Err(_) => M::Unsupported(query),
        })
    }
}

#[cfg(test)]
#[path = "source_var_declaration_tests.rs"]
mod source_var_declaration_tests;

impl SemanticTree {
    /// Same native resolver selection, with demand-owned canonical allocation.
    /// This changes neither source provenance nor unsupported-query semantics.
    pub fn resolve_with_canonical_work(&self,query:dm_ir::ResolveQuery,work:&mut dyn dm_ir::CanonicalWork)->std::io::Result<dm_ir::ResolvedMeaning> {
        use dm_ir::ResolveQuery as Q;
        work.poll()?;
        match query {
            Q::SourceVarDeclaration{owner,name}=>self.source_var_declaration_using(owner,name,query,&mut|data|Ok(xxhash_rust::xxh3::xxh3_128(&data.canonical_bytes_using(work)?).into())),
            Q::CheckerBuiltinVar{profile,owner,name}=>self.resolve_checker_builtin_admitted(query,profile,owner,name,MemberKind::Var,false,work),
            Q::CheckerBuiltinProc{profile,owner,name,verb}=>self.resolve_checker_builtin_admitted(query,profile,owner,name,if verb{MemberKind::Verb}else{MemberKind::Proc},false,work),
            Q::SourceDeclarationChain{owner,name,verb}=>self.source_declaration_chain_using(owner,name,verb,query,Some(work)),
            Q::Type(_)=>Ok(dm_ir::Resolver::resolve(self,query)),
            Q::Ancestry(path)=>{
                if !self.owner_ancestry.contains_key(&path){let mut next=self.lookup_type(path);let mut count=0usize;while let Some(id)=next{work.poll()?;count=count.checked_add(1).filter(|n|*n<=self.types().len()).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidData,"native ancestry allocation geometry is cyclic"))?;next=self.parent(id);}work.reserve(count.checked_mul(8*std::mem::size_of::<SymbolId>()).and_then(|n|n.checked_add(256)).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native ancestry allocation geometry overflow"))?)?;}
                Ok(dm_ir::Resolver::resolve(self,query))
            },
            _=>Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"native admitted structural resolver query has not been issued")),
        }
    }
}
