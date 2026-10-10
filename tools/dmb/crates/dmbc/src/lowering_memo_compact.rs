//! Compact disk records retain executable words, never a live source issuer.
use crate::lowering_memo::{ReplayDecline, ResolverRead};
use dm_ir::{ProcedureIdentity, ReadDomain, ResolveQuery, Resolver, SymbolId};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::borrow::Cow;
pub(crate) const SCHEMA: u32 = 0x0206_0007;
const MAX_RECORD: usize = 8 * 1024 * 1024;
const MAX_ITEMS: usize = 65536;
#[cfg(test)]
#[path = "lowering_memo_compact_tests.rs"]
mod tests;
pub(crate) fn eligible(
    unit: &crate::lowering::LoweredUnit,
    bindings: crate::lowering::DiskReplayBindings<'_>,
) -> bool {
    if unit.abi.is_none()
        || unit.selected_references.is_some()
        || !unit.code.instances.is_empty()
        || !unit.code.modified_instances.is_empty()
    {
        return false;
    }
    if unit
        .source_helpers
        .iter()
        .any(|h| !h.code.instances.is_empty() || !h.code.modified_instances.is_empty())
    {
        return false;
    }
    let mut licensed = std::collections::BTreeSet::new();
    licensed.insert(dm_ir::SymRef::BuiltinGlobalVars);
    licensed.extend(
        unit.code
            .procedure
            .strings
            .iter()
            .map(|s| dm_ir::SymRef::String(s.id)),
    );
    licensed.extend(
        unit.code
            .slots
            .values()
            .map(|s| dm_ir::SymRef::VariableSlot(s.symbol)),
    );
    let mut valid = true;
    unit.code.procedure.code.for_each_reference(|reference| {
        valid &= match reference {
            dm_ir::SymRef::SourceFile(at) | dm_ir::SymRef::SourceLine(at) => {
                (at as usize) < unit.debug_origins.entries.len()
            }
            _ => {
                licensed.contains(&reference)
                    || bindings.source.contains(&reference)
                    || bindings.external.references.contains(&reference)
            }
        };
    });
    valid
        && unit.source_helpers.iter().all(|helper| {
            let mut licensed = std::collections::BTreeSet::from([dm_ir::SymRef::BuiltinGlobalVars]);
            licensed.extend(
                helper
                    .code
                    .procedure
                    .strings
                    .iter()
                    .map(|s| dm_ir::SymRef::String(s.id)),
            );
            licensed.extend(
                helper
                    .code
                    .slots
                    .values()
                    .map(|s| dm_ir::SymRef::VariableSlot(s.symbol)),
            );
            let mut valid = true;
            helper.code.procedure.code.for_each_reference(|reference| {
                valid &= match reference {
                    dm_ir::SymRef::SourceFile(at) | dm_ir::SymRef::SourceLine(at) => {
                        (at as usize) < helper.debug_origins.entries.len()
                    }
                    _ => {
                        licensed.contains(&reference)
                            || bindings.source.contains(&reference)
                            || bindings.external.references.contains(&reference)
                    }
                }
            });
            valid
        })
}

pub(crate) struct BoundedVec<T>(pub(crate) Vec<T>);
impl<T: Serialize> Serialize for BoundedVec<T> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        if self.0.len() > MAX_ITEMS {
            return Err(serde::ser::Error::custom("compact collection exceeds cap"));
        }
        self.0.serialize(serializer)
    }
}
impl<'de, T: Deserialize<'de>> Deserialize<'de> for BoundedVec<T> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct Visitor<T>(std::marker::PhantomData<T>);
        impl<'de, T: Deserialize<'de>> serde::de::Visitor<'de> for Visitor<T> {
            type Value = BoundedVec<T>;
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("bounded compact sequence")
            }
            fn visit_seq<A: serde::de::SeqAccess<'de>>(
                self,
                mut seq: A,
            ) -> Result<Self::Value, A::Error> {
                let hint = seq.size_hint().unwrap_or(0);
                if hint > MAX_ITEMS {
                    return Err(serde::de::Error::custom("compact collection exceeds cap"));
                }
                let mut values = Vec::with_capacity(hint.min(4096));
                while let Some(value) = seq.next_element()? {
                    if values.len() == MAX_ITEMS {
                        return Err(serde::de::Error::custom("compact collection exceeds cap"));
                    }
                    values.push(value);
                }
                Ok(BoundedVec(values))
            }
        }
        deserializer.deserialize_seq(Visitor(std::marker::PhantomData))
    }
}
#[derive(Serialize, Deserialize)]
pub(crate) struct ReadWire<'a> {
    pub(crate) query: ResolveQuery,
    #[serde(borrow)]
    pub(crate) answer: Cow<'a, [u8]>,
}
#[derive(Serialize, Deserialize)]
pub(crate) struct Payload<'a> {
    #[serde(borrow)]
    pub(crate) key: Cow<'a, [u8]>,
    pub(crate) identity: ProcedureIdentity,
    #[serde(borrow)]
    pub(crate) reads: BoundedVec<ReadWire<'a>>,
    pub(crate) versions: BoundedVec<(ReadDomain, u128)>,
    pub(crate) debug: BoundedVec<usize>,
    pub(crate) required_types: BoundedVec<SymbolId>,
    #[serde(borrow)]
    abi: Cow<'a, [u8]>,
    #[serde(borrow)]
    executable: crate::symbolic::procedure_artifact::disk::Encoded<'a>,
    #[serde(borrow)]
    helpers: BoundedVec<crate::symbolic::procedure_artifact::disk::HelperWire<'a>>,
}
pub(crate) fn encode(
    key: &[u8],
    reads: &[ResolverRead],
    versions: &[(ReadDomain, u128)],
    value: &crate::symbolic::PreparedContribution,
    debug: &[usize],
) -> Option<Vec<u8>> {
    if !value.modified_seeds().is_empty() {
        return None;
    }
    let artifact = value.shared_artifact();
    let requests = artifact.disk_type_requests();
    if requests != value.required_types() {
        return None;
    }
    let executable = artifact.disk_encoded()?;
    let identity = value.identity();
    let payload = Payload {
        key: Cow::Borrowed(key),
        identity: ProcedureIdentity {
            owner: identity.owner,
            name: identity.name,
            verb: identity.namespace == crate::lowering::Namespace::Verb,
            occurrence: identity.occurrence,
        },
        reads: BoundedVec(
            reads
                .iter()
                .map(|r| ReadWire {
                    query: r.query,
                    answer: Cow::Owned(r.answer.canonical_bytes()),
                })
                .collect(),
        ),
        versions: BoundedVec(
            versions
                .iter()
                .copied()
                .filter(|(d, _)| d.persistent_version())
                .collect(),
        ),
        debug: BoundedVec(debug.to_vec()),
        required_types: BoundedVec(value.required_types().to_vec()),
        abi: Cow::Owned(artifact.disk_abi()?),
        executable,
        helpers: BoundedVec(artifact.disk_helpers()?),
    };
    dm_wire::encode_bounded(SCHEMA, &payload, MAX_RECORD).ok()
}
pub(crate) fn decode(bytes: &[u8]) -> Result<Payload<'_>, String> {
    let value: Payload<'_> = dm_wire::decode_borrowed(SCHEMA, bytes, MAX_RECORD)?;
    crate::lowering_memo_wire::validate_versions(&value.versions.0)?;
    Ok(value)
}
impl Payload<'_> {
    pub(crate) fn changed_read<R: Resolver>(&self, host: &R) -> Option<ResolveQuery> {
        let matching = crate::lowering_memo::matching_domains(&self.versions.0, host);
        self.reads.0.iter().find_map(|r| {
            (!matching.contains(&r.query.domain())
                && host.resolve(r.query).canonical_bytes() != r.answer.as_ref())
            .then_some(r.query)
        })
    }
    pub(crate) fn promotion(&self) -> crate::lowering_memo_wire::ResidentPromotion {
        crate::lowering_memo_wire::ResidentPromotion {
            queries: self.reads.0.iter().map(|r| r.query).collect(),
            versions: self.versions.0.clone(),
            relative_debug: self.debug.0.clone(),
        }
    }
    pub(crate) fn rebind(
        self,
        context: crate::lowering_memo_wire::ProcedureReplayContext<'_>,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> Result<crate::symbolic::PreparedContribution, ReplayDecline> {
        let bindings = context.bindings.ok_or(ReplayDecline::ExecutableIssuer)?;
        prepared
            .require_production_abi()
            .map_err(|_| ReplayDecline::PreparedAbi)?;
        let abi = prepared.abi.as_ref().ok_or(ReplayDecline::PreparedAbi)?;
        if self.abi.as_ref() != abi.canonical_bytes() {
            return Err(ReplayDecline::PreparedAbi);
        }
        let debug =
            crate::lowering_memo::rebase_debug(context.frontend, context.body, &self.debug.0)
                .ok_or(ReplayDecline::DebugOrigins)?;
        let mut artifact = self
            .executable
            .restore(
                context.frontend,
                context.body,
                prepared,
                bindings,
                debug.entries.len(),
            )
            .ok_or(ReplayDecline::ExecutableIssuer)?;
        crate::symbolic::ReusableProcedureArtifact::disk_bind_helpers(
            &mut artifact,
            self.helpers.0,
            context.frontend,
            context.body,
            prepared,
            bindings,
        )
        .ok_or(ReplayDecline::ExecutableIssuer)?;
        let requests = artifact.disk_type_requests();
        if requests != self.required_types.0
            || requests
                .iter()
                .any(|id| context.frontend.snapshot.tree.symbols().text(*id).is_none())
        {
            return Err(ReplayDecline::ExecutableIssuer);
        }
        crate::symbolic::PreparedContribution::rebind_with_modified(
            &artifact,
            context.frontend,
            context.body,
            prepared,
            debug,
            &self.required_types.0,
            Vec::new(),
        )
        .ok_or(ReplayDecline::ExecutableIssuer)
    }
}
