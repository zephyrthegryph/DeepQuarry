//! Counters for the view's hot paths (`DQ_MODEL_PROFILE=1`): calls and summed wall time per path, printed at the end of a run with the
//! CPU account (`crate::util::cpu_account_report`). Off, a counter costs one relaxed load.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::OnceLock;

pub const STMTS: usize = 0;
pub const CHAIN: usize = 1;
pub const LITERAL: usize = 2;
pub const SITE_HIT: usize = 3;
pub const SITE_MISS: usize = 4;
pub const PROC_DEFS: usize = 5;
pub const VAR_DECL: usize = 6;
pub const PROC_RESOLVE: usize = 7;
const NAMES: [&str; 8] = ["stmts", "chain", "literal", "site hit", "site miss", "proc definitions", "var declaration", "proc resolve"];

static CALLS: [AtomicU64; 8] = [const { AtomicU64::new(0) }; 8];
static NANOS: [AtomicU64; 8] = [const { AtomicU64::new(0) }; 8];

pub fn on() -> bool {
    static ON: OnceLock<bool> = OnceLock::new();
    static CACHED: AtomicBool = AtomicBool::new(false);
    if CACHED.load(Ordering::Relaxed) {
        return true;
    }
    let on = *ON.get_or_init(|| dq_hostio::var_os("DQ_MODEL_PROFILE").is_some());
    if on {
        CACHED.store(true, Ordering::Relaxed);
    }
    on
}

/// Times `f` under counter `k` when profiling is on.
#[inline]
pub fn time<R>(k: usize, f: impl FnOnce() -> R) -> R {
    if !on() {
        return f();
    }
    let t = std::time::Instant::now();
    let r = f();
    CALLS[k].fetch_add(1, Ordering::Relaxed);
    NANOS[k].fetch_add(t.elapsed().as_nanos() as u64, Ordering::Relaxed);
    r
}

/// Counts one event under `k` (no timing).
#[inline]
pub fn count(k: usize) {
    if on() {
        CALLS[k].fetch_add(1, Ordering::Relaxed);
    }
}

pub fn report() {
    if !on() {
        return;
    }
    for (i, name) in NAMES.iter().enumerate() {
        let calls = CALLS[i].load(Ordering::Relaxed);
        let ms = NANOS[i].load(Ordering::Relaxed) / 1_000_000;
        eprintln!("MODEL {name:<18} {calls:>12} calls {ms:>9} ms (summed over threads)");
    }
}
