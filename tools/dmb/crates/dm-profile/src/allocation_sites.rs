//! Sampled live-allocation attribution by call site (feature `allocation-sites`, diagnostics only).
//!
//! The counting allocator samples roughly one allocation per `SAMPLE_BYTES` requested bytes, captures
//! its call stack, and removes the sample when the pointer is freed or reallocated. `report` prints the
//! call sites holding the most sampled live bytes, scaled by the sampling weight. Sampling is
//! size-weighted: a sampled allocation stands for `max(size, SAMPLE_BYTES)` bytes.
use std::cell::Cell;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

const SAMPLE_BYTES: i64 = 256 * 1024;
const FILTER_BITS: usize = 1 << 26;

thread_local! {
    static UNTIL_SAMPLE: Cell<i64> = const { Cell::new(SAMPLE_BYTES) };
    static IN_HOOK: Cell<bool> = const { Cell::new(false) };
}

struct Site {
    stack: String,
    live: u64,
}
struct State {
    pointers: HashMap<usize, (u64, u64)>,
    sites: HashMap<u64, Site>,
}
static STATE: Mutex<Option<State>> = Mutex::new(None);
// A false positive only costs one lock acquisition on free; a false negative cannot occur.
static FILTER: [AtomicU64; FILTER_BITS / 64] = [const { AtomicU64::new(0) }; FILTER_BITS / 64];

fn slot(pointer: usize) -> (usize, u64) {
    let bit = ((pointer >> 4).wrapping_mul(0x9E37_79B9_7F4A_7C15) >> 38) & (FILTER_BITS - 1);
    (bit / 64, 1u64 << (bit % 64))
}

pub(crate) fn on_alloc(pointer: *mut u8, size: usize) {
    if IN_HOOK.try_with(Cell::get).unwrap_or(true) {
        return;
    }
    let sample = UNTIL_SAMPLE
        .try_with(|until| {
            let remaining = until.get() - size as i64;
            if remaining <= 0 {
                until.set(SAMPLE_BYTES);
                true
            } else {
                until.set(remaining);
                false
            }
        })
        .unwrap_or(false);
    if !sample {
        return;
    }
    let _ = IN_HOOK.try_with(|flag| flag.set(true));
    let weight = (size as i64).max(SAMPLE_BYTES) as u64;
    let stack = std::backtrace::Backtrace::force_capture().to_string();
    let key = xxhash_rust::xxh3::xxh3_64(stack.as_bytes());
    if let Ok(mut state) = STATE.lock() {
        let state = state.get_or_insert_with(|| State {
            pointers: HashMap::new(),
            sites: HashMap::new(),
        });
        state.pointers.insert(pointer as usize, (key, weight));
        let site = state
            .sites
            .entry(key)
            .or_insert_with(|| Site { stack, live: 0 });
        site.live += weight;
        let (word, mask) = slot(pointer as usize);
        FILTER[word].fetch_or(mask, Ordering::Relaxed);
    }
    let _ = IN_HOOK.try_with(|flag| flag.set(false));
}

pub(crate) fn on_free(pointer: *mut u8) {
    let (word, mask) = slot(pointer as usize);
    if FILTER[word].load(Ordering::Relaxed) & mask == 0 {
        return;
    }
    if IN_HOOK.try_with(Cell::get).unwrap_or(true) {
        return;
    }
    let _ = IN_HOOK.try_with(|flag| flag.set(true));
    if let Ok(mut state) = STATE.lock() {
        if let Some(state) = state.as_mut() {
            if let Some((key, weight)) = state.pointers.remove(&(pointer as usize)) {
                if let Some(site) = state.sites.get_mut(&key) {
                    site.live = site.live.saturating_sub(weight);
                }
            }
        }
    }
    let _ = IN_HOOK.try_with(|flag| flag.set(false));
}

/// Top `limit` call sites by sampled live bytes, as text (frames inside std/alloc/profile code elided).
pub fn report(limit: usize) -> String {
    let _ = IN_HOOK.try_with(|flag| flag.set(true));
    let mut out = String::new();
    if let Ok(state) = STATE.lock() {
        if let Some(state) = state.as_ref() {
            let total: u64 = state.sites.values().map(|site| site.live).sum();
            out.push_str(&format!("sampled live total {} MB\n", total / 1_000_000));
            let mut sites: Vec<_> = state.sites.values().filter(|site| site.live > 0).collect();
            sites.sort_by_key(|site| std::cmp::Reverse(site.live));
            for site in sites.into_iter().take(limit) {
                out.push_str(&format!("== {} MB\n", site.live / 1_000_000));
                let mut shown = 0;
                let mut lines = site.stack.lines().peekable();
                while let Some(line) = lines.next() {
                    let name = line.trim();
                    let location = lines.peek().map(|next| next.trim()).unwrap_or("");
                    if name.contains("dm_profile::")
                        || name.contains("alloc::")
                        || name.contains("std::")
                        || name.contains("core::")
                        || name.contains("__rust")
                        || name.contains("mimalloc")
                        || !name.chars().next().is_some_and(|c| c.is_ascii_digit())
                    {
                        continue;
                    }
                    out.push_str(&format!("   {name} {location}\n"));
                    shown += 1;
                    if shown >= 5 {
                        break;
                    }
                }
            }
        }
    }
    let _ = IN_HOOK.try_with(|flag| flag.set(false));
    out
}
