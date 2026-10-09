//! One dependency-recording path shared by all semantic artifact consumers.
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
use std::{collections::BTreeMap, sync::Mutex};
/// Versions are immutable issuer facts. Missing/different receipts require every
/// original positive or negative answer to be checked exactly.
pub fn matching_domains<R: Resolver>(
    versions: &[(ReadDomain, u128)],
    resolver: &R,
) -> std::collections::BTreeSet<ReadDomain> {
    versions
        .iter()
        .filter_map(|&(domain, version)| {
            (resolver.domain_version(domain) == Some(version)).then_some(domain)
        })
        .collect()
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ResolverRead {
    pub domain: ReadDomain,
    pub query: ResolveQuery,
    pub answer: ResolvedMeaning,
}

pub struct RecordingResolver<'a, R: Resolver> {
    resolver: &'a R,
    reads: Mutex<BTreeMap<ResolveQuery, Vec<ResolverRead>>>,
    versions: Mutex<BTreeMap<ReadDomain, Option<u128>>>,
}
impl<'a, R: Resolver> RecordingResolver<'a, R> {
    pub fn new(resolver: &'a R) -> Self {
        Self {
            resolver,
            reads: Mutex::new(BTreeMap::new()),
            versions: Mutex::new(BTreeMap::new()),
        }
    }
    pub fn reads(&self) -> Vec<ResolverRead> {
        self.reads
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .values()
            .flatten()
            .cloned()
            .collect()
    }
    pub fn domain_receipts(&self) -> Vec<(ReadDomain, u128)> {
        self.versions
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .iter()
            .filter_map(|(&domain, &version)| version.map(|version| (domain, version)))
            .collect()
    }
    /// These reads are mandatory even for bodies that use no inherited names.
    pub fn record_occurrence(&self, identity: dm_ir::ProcedureIdentity) {
        self.resolve(ResolveQuery::Ancestry(identity.owner));
        self.resolve(ResolveQuery::OverrideChain {
            owner: identity.owner,
            name: identity.name,
            verb: identity.verb,
        });
    }
}
impl<R: Resolver> Resolver for RecordingResolver<'_, R> {
    fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
        self.resolver.domain_version(domain)
    }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.versions
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .entry(query.domain())
            .or_insert_with(|| self.resolver.domain_version(query.domain()));
        let answer = self.resolver.resolve(query);
        let mut reads = self.reads.lock().unwrap_or_else(|error| error.into_inner());
        let answers = reads.entry(query).or_default();
        if !answers.iter().any(|read| read.answer == answer) {
            answers.push(ResolverRead {
                domain: query.domain(),
                query,
                answer: answer.clone(),
            });
        }
        answer
    }
}
