//! Producer-bound ABI coverage, without captured source contexts.
use super::*;
pub(crate) struct PreparedAbiUnits {
    selected: Option<Arc<[Arc<super::abi_artifacts::UnitArtifact>]>>,
    entries: Arc<[(MemberId, crate::procedure_policy::PreparedUnit)]>,
    roster: Option<Arc<dm_tree::frontend::CallableAbiRoster>>,
    members: Arc<BTreeMap<UnitIdentity, MemberId>>,
}
impl PreparedAbiUnits {
    pub(super) fn issue(
        frontend: &ColdFrontend,
        members: Arc<BTreeMap<UnitIdentity, MemberId>>,
        entries: Vec<(MemberId, crate::procedure_policy::PreparedUnit)>,
        complete: bool,
    ) -> Result<Arc<Self>, AbiError> {
        let callable = frontend.callable_roster().map_err(AbiError::unsupported)?;
        let roster = if complete {
            if entries.len() != callable.members().len() || members.len() != entries.len() {
                return Err(AbiError::unsupported(
                    "prepared ABI batch does not cover all bodies",
                ));
            }
            for (ordinal, (member, unit)) in entries.iter().enumerate() {
                unit.require_production_abi()?;
                if !unit.executable_body.is_empty() {
                    return Err(AbiError::invariant(
                        "prepared ABI owner retains executable syntax",
                    ));
                }
                if callable.members().get(ordinal) != Some(member) {
                    return Err(AbiError::unsupported("prepared ABI member order differs"));
                }
                let identity = callable
                    .identity(ordinal)
                    .ok_or_else(|| AbiError::invariant("callable identity missing"))?;
                let identity = UnitIdentity {
                    owner: identity.owner,
                    name: identity.name,
                    namespace: if identity.verb {
                        Namespace::Verb
                    } else {
                        Namespace::Proc
                    },
                    occurrence: identity.occurrence,
                };
                if members.get(&identity) != Some(member) {
                    return Err(AbiError::unsupported(
                        "issued callable index differs from frontend",
                    ));
                }
            }
            Some(
                callable
                    .abi()
                    .ok_or_else(|| AbiError::unsupported("complete callable ABI roster missing"))?
                    .clone(),
            )
        } else {
            None
        };
        Ok(Arc::new(Self {
            selected: None,
            entries: entries.into(),
            roster,
            members,
        }))
    }
    /// Rebind an admitted symbolic batch to the exact current issued member map.
    /// Semantic receipt admission precedes this call; no old arena ID is copied.
    pub(super) fn rebind(
        frontend: &ColdFrontend,
        members: Arc<BTreeMap<UnitIdentity, MemberId>>,
        graph: &Arc<dm_tree::frontend::CallableAbiGraph>,
        units: &[(
            dm_ir::ProcedureIdentity,
            Arc<super::abi_artifacts::UnitArtifact>,
        )],
    ) -> Result<Arc<Self>, AbiError> {
        let callable = frontend.callable_roster().map_err(AbiError::unsupported)?;
        let current = callable
            .abi()
            .ok_or_else(|| AbiError::unsupported("current ABI graph missing"))?;
        if !(Arc::ptr_eq(current.graph(), graph) || current.graph() == graph)
            || units.len() != current.entries().len()
        {
            return Err(AbiError::unsupported(
                "symbolic ABI graph differs from current binding",
            ));
        }
        let mut entries = Vec::with_capacity(units.len());
        for (entry, (identity, unit)) in current.entries().iter().zip(units) {
            if entry.identity != *identity {
                return Err(AbiError::unsupported("symbolic ABI unit order differs"));
            }
            entries.push((
                entry.member,
                crate::procedure_policy::PreparedUnit {
                    canonical: unit.canonical.clone(),
                    inputs: unit.inputs.clone(),
                    abi: Some(unit.abi.clone()),
                    executable_body: Vec::new(),
                },
            ));
        }
        Self::issue(frontend, members, entries, true)
            .map(|owner| Self::certify_selected(owner, units.iter().cloned()))
    }
    /// Only a successful current producer pass supplies these selected owners.
    /// Storage enumeration or equal-output guesses cannot issue this proof.
    fn certify_selected(
        mut owner: Arc<Self>,
        selected: impl Iterator<
            Item = (
                dm_ir::ProcedureIdentity,
                Arc<super::abi_artifacts::UnitArtifact>,
            ),
        >,
    ) -> Arc<Self> {
        let Some(roster) = &owner.roster else {
            return owner;
        };
        let selected: Vec<_> = selected.collect();
        if selected.len() != owner.entries.len() || selected.len() != roster.entries().len() {
            return owner;
        }
        let exact = roster
            .entries()
            .iter()
            .zip(owner.entries.iter())
            .zip(&selected)
            .all(|((entry, (_, prepared)), (identity, artifact))| {
                entry.identity == *identity
                    && Arc::ptr_eq(&prepared.inputs, &artifact.inputs)
                    && prepared
                        .abi
                        .as_ref()
                        .is_some_and(|abi| Arc::ptr_eq(abi, &artifact.abi))
            });
        if !exact {
            return owner;
        }
        if let Some(current) = Arc::get_mut(&mut owner) {
            current.selected = Some(
                selected
                    .into_iter()
                    .map(|(_, unit)| unit)
                    .collect::<Vec<_>>()
                    .into(),
            );
        }
        owner
    }
    pub(crate) fn selected(
        &self,
        ordinal: usize,
    ) -> Option<&Arc<super::abi_artifacts::UnitArtifact>> {
        self.selected.as_ref()?.get(ordinal)
    }
    pub(crate) fn selected_storage(
        &self,
    ) -> Option<&Arc<[Arc<super::abi_artifacts::UnitArtifact>]>> {
        self.selected.as_ref()
    }
    pub(super) fn members(&self) -> &Arc<BTreeMap<UnitIdentity, MemberId>> {
        &self.members
    }
    pub(crate) fn entries(&self) -> &[(MemberId, crate::procedure_policy::PreparedUnit)] {
        &self.entries
    }
    pub(super) fn admit(
        &self,
        frontend: &ColdFrontend,
        members: &Arc<BTreeMap<UnitIdentity, MemberId>>,
    ) -> Result<(), AbiError> {
        let current = frontend.callable_roster().map_err(AbiError::unsupported)?;
        let current = current
            .abi()
            .ok_or_else(|| AbiError::unsupported("current callable ABI roster missing"))?;
        let issued = self
            .roster
            .as_ref()
            .ok_or_else(|| AbiError::unsupported("prepared ABI coverage not issued"))?;
        if !(Arc::ptr_eq(current, issued) || current == issued)
            || !(Arc::ptr_eq(members, &self.members) || members == &self.members)
        {
            return Err(AbiError::unsupported(
                "prepared ABI roster differs from current frontend",
            ));
        }
        Ok(())
    }
    pub(crate) fn visit_storage(
        &self,
        mut visit: impl FnMut(
            &Arc<[(MemberId, crate::procedure_policy::PreparedUnit)]>,
            Option<&Arc<dm_tree::frontend::CallableAbiRoster>>,
            &Arc<BTreeMap<UnitIdentity, MemberId>>,
        ),
    ) {
        visit(&self.entries, self.roster.as_ref(), &self.members);
    }
    #[cfg(test)]
    pub(super) fn failed_empty() -> Arc<Self> {
        Arc::new(Self {
            selected: None,
            entries: Arc::from([]),
            roster: None,
            members: Arc::new(BTreeMap::new()),
        })
    }
}

/// Freeze the actual chosen current per-unit artifacts while the successful
/// producer still owns its capture, before batch::remember consumes it.
pub(super) fn certify_capture(
    owner: Arc<PreparedAbiUnits>,
    capture: Option<&super::abi_artifacts::batch::Capture>,
) -> Arc<PreparedAbiUnits> {
    let Some(capture) = capture else {
        return owner;
    };
    let capture = capture.lock().unwrap_or_else(|error| error.into_inner());
    let Some(roster) = &owner.roster else {
        return owner;
    };
    let selected: Option<Vec<_>> = roster
        .entries()
        .iter()
        .map(|entry| {
            let identity = UnitIdentity {
                owner: entry.identity.owner,
                name: entry.identity.name,
                namespace: if entry.identity.verb {
                    Namespace::Verb
                } else {
                    Namespace::Proc
                },
                occurrence: entry.identity.occurrence,
            };
            let (artifact, _) = capture.get(&identity)?;
            Some((entry.identity, Arc::clone(artifact)))
        })
        .collect();
    let Some(selected) = selected else {
        return owner;
    };
    PreparedAbiUnits::certify_selected(owner, selected.into_iter())
}
