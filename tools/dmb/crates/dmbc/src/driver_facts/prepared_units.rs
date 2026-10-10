//! Producer-bound ABI coverage, without captured source contexts.
use super::*;
pub(crate) struct PreparedAbiUnits {
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
            entries: entries.into(),
            roster,
            members,
        }))
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
            entries: Arc::from([]),
            roster: None,
            members: Arc::new(BTreeMap::new()),
        })
    }
}
