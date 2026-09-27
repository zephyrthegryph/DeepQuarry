//! The one domain registry instance (`rust_architecture.md` §5). The table
//! and its trait are `vg_core::registry`; this module only keeps the
//! instance on BYOND's main thread and offers the three calls every bind
//! uses.

use std::cell::RefCell;

use vg_core::registry::{DomainRegistry, Registry};

thread_local! {
    static DOMAINS: RefCell<Registry> = RefCell::new(Registry::new());
}

/// Registers (or replaces) a host under a numeric id (a generated
/// `VG_DOMAIN_*`/`REACT_DOMAIN_*` define, or a world kind's
/// `vg_core::registry::world_kind_domain`).
pub fn register_domain(id: u32, domain: Box<dyn DomainRegistry>) {
    DOMAINS.with_borrow_mut(|d| d.register(id, domain));
}

/// Runs `f` against the registered host `id`, if any.
pub fn with_domain<T>(
    id: u32,
    f: impl FnOnce(&mut (dyn DomainRegistry + 'static)) -> T,
) -> Option<T> {
    DOMAINS.with_borrow_mut(|d| d.get_mut(id).map(f))
}

/// Runs `f` against every registered host, `(id, host)`.
pub fn for_each(mut f: impl FnMut(u32, &mut (dyn DomainRegistry + 'static))) {
    DOMAINS.with_borrow_mut(|domains| {
        for (id, host) in domains.iter_mut() {
            f(id, host);
        }
    });
}
