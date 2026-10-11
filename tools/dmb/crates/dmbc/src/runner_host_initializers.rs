//! One-shot facades use the SAME typed initializer stores as retained requests.
//! Disk transport is optional; unsupported portable recipes run these producers.
use super::*;
pub(super) fn one_shot(
    policy: u128,
    disk: Option<Arc<disk::LazyDisk>>,
    publishable: bool,
    engine: Option<&Arc<RetainedEngine>>,
) -> crate::lowering_memo::ProcedureMemo {
    let mut memo = match &disk {
        Some(disk) => {
            crate::lowering_memo::ProcedureMemo::with_lazy_disk_only(policy, Arc::clone(disk))
        }
        None => crate::lowering_memo::ProcedureMemo::new(policy),
    };
    memo.initializers =
        Some(crate::initializer_policy::InitializerArtifacts::default().for_request(publishable));
    memo.startup = Some(crate::startup::StartupArtifacts::default().for_request(publishable));
    let mut fragments = crate::initializer_lowering::InitializerFragments::default();
    let mut assemblies = crate::initializer_lowering::InitializerAssemblies::default();
    if let Some(disk) = disk {
        let owner = engine.map(|engine| engine.abi_engine_owner());
        let transport = crate::initializer_lowering::disk::Transport::new(
            Arc::clone(&disk),
            owner.clone(),
            policy,
            publishable,
        );
        fragments = fragments.with_disk_transport(Arc::clone(&transport));
        assemblies = assemblies.with_disk_transport(transport);
        if let Some(owner) = owner {
            memo.abi = Some(Arc::new(crate::driver_facts::AbiArtifacts::with_disk(
                owner, disk, policy,
            )));
        }
    }
    memo.initializer_fragments = Some(fragments.for_request(publishable));
    memo.initializer_assemblies = Some(assemblies.for_request(publishable));
    memo
}
