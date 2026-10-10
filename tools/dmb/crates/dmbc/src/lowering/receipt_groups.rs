//! Procedure read leaves share storage only after full exact observation equality.
use crate::lowering_memo::ResolverRead;
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, SymbolId};
use dm_session::{Receipt, ReceiptAdmission, ReceiptGroupPool};

pub(super) type ProcedureReceipt = Receipt<ResolveQuery, ResolvedMeaning, ReadDomain>;
pub(super) type ProcedureGroups = ReceiptGroupPool<ResolveQuery, ResolvedMeaning, ReadDomain>;
pub(in crate::lowering) type RequestAdmission<'a, R> =
    ReceiptAdmission<'a, ResolveQuery, ResolvedMeaning, ReadDomain, R>;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Family {
    ProcedureStatic,
    Type,
    Parent,
    Ancestry,
    Var,
    HasMemberVar,
    DeclaredVarType,
    VarStorage,
    Proc,
    ProcedureValue,
    OverrideChain,
    DeclarationChain,
    Signature,
    GlobalVar,
    GlobalProc,
    MemberCallableName,
    Constant,
    Resource,
    RuntimeType,
    StaticVar,
    UniqueStaticVar,
    HasMemberProc,
    PredefinedConstant,
    ResourceIn,
    MethodProcedureValue,
}
fn family(query: ResolveQuery) -> (Family, Option<SymbolId>) {
    use ResolveQuery::*;
    match query {
        ProcedureStatic { procedure, .. } => (Family::ProcedureStatic, Some(procedure.owner)),
        Type(owner) => (Family::Type, Some(owner)),
        Parent(owner) => (Family::Parent, Some(owner)),
        Ancestry(owner) => (Family::Ancestry, Some(owner)),
        Var { owner, .. } => (Family::Var, Some(owner)),
        HasMemberVar { owner, .. } => (Family::HasMemberVar, Some(owner)),
        DeclaredVarType { owner, .. } => (Family::DeclaredVarType, Some(owner)),
        VarStorage { owner, .. } => (Family::VarStorage, Some(owner)),
        Proc { owner, .. } => (Family::Proc, Some(owner)),
        ProcedureValue { owner, .. } => (Family::ProcedureValue, Some(owner)),
        OverrideChain { owner, .. } => (Family::OverrideChain, Some(owner)),
        DeclarationChain { owner, .. } => (Family::DeclarationChain, Some(owner)),
        Signature(_) => (Family::Signature, None),
        GlobalVar(_) => (Family::GlobalVar, None),
        MemberCallableName(_) => (Family::MemberCallableName, None),
        GlobalProc(_) => (Family::GlobalProc, None),
        Constant { owner, .. } => (Family::Constant, Some(owner)),
        Resource(_) => (Family::Resource, None),
        RuntimeType(_) => (Family::RuntimeType, None),
        StaticVar { owner, .. } => (Family::StaticVar, Some(owner)),
        UniqueStaticVar(_) => (Family::UniqueStaticVar, None),
        HasMemberProc { owner, .. } => (Family::HasMemberProc, Some(owner)),
        PredefinedConstant(_) => (Family::PredefinedConstant, None),
        ResourceIn { .. } => (Family::ResourceIn, None),
        MethodProcedureValue { owner, .. } => (Family::MethodProcedureValue, Some(owner)),
    }
}
fn domain_family(domain: ReadDomain) -> std::mem::Discriminant<ReadDomain> {
    std::mem::discriminant(&domain)
}
pub(super) fn grouped(pool: &ProcedureGroups, reads: Vec<ResolverRead>) -> ProcedureReceipt {
    // The recorder is canonical. Unexpected noncanonical callers retain all
    // observations in ordinary flat storage, without issuing a grouped proof.
    if reads.windows(2).any(|pair| pair[0].query > pair[1].query) {
        return reads.into();
    }
    pool.intern_receipt(reads, |a, b| {
        family(a.query) == family(b.query) && domain_family(a.domain) == domain_family(b.domain)
    })
    .expect("canonical recorder receipt")
}

#[cfg(test)]
#[path = "receipt_groups_tests.rs"]
mod tests;
