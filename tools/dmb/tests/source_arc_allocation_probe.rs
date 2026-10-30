//! STANDALONE TEST BINARY, never linked into production dmbc.
//! Compile with --cfg dmb_arc_probe and Cargo's actual OUT_DIR from the same
//! dmbc profile. No source/runtime endpoint accepts these test-only methods.
#[path = "../crates/dmbc/src/query_db/native_arc_allocation.rs"]
mod native_arc_allocation;
#[path = "../crates/dmbc/src/query_db/no_weak_arc_owner.rs"]
mod no_weak_arc_owner;
use native_arc_allocation::NativeArcAllocationPlan as Plan;
use std::{
    alloc::{GlobalAlloc, Layout, System},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
};
#[derive(Clone, Copy, Debug)]
struct Event {
    op: u8,
    size: usize,
    align: usize,
    new_size: usize,
}
const EMPTY: Event = Event {
    op: 0,
    size: 0,
    align: 0,
    new_size: 0,
};
#[derive(Clone, Copy, Debug)]
struct Events {
    rows: [Event; 64],
    len: usize,
    overflow: bool,
}
static ACTIVE: AtomicBool = AtomicBool::new(false);
static EVENTS: Mutex<Events> = Mutex::new(Events {
    rows: [EMPTY; 64],
    len: 0,
    overflow: false,
});
struct Recording;
#[global_allocator]
static ALLOCATOR: Recording = Recording;
fn record(op: u8, layout: Layout, new_size: usize) {
    if !ACTIVE.load(Ordering::Acquire) {
        return;
    }
    // Single-thread test; fixed storage, no formatting/heap growth in the hook.
    let mut events = EVENTS.lock().unwrap_or_else(|e| e.into_inner());
    let index = events.len;
    if index == events.rows.len() {
        events.overflow = true;
        return;
    }
    events.rows[index] = Event {
        op,
        size: layout.size(),
        align: layout.align(),
        new_size,
    };
    events.len += 1;
}
unsafe impl GlobalAlloc for Recording {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let p = unsafe { System.alloc(layout) };
        record(if p.is_null() { b'F' } else { b'A' }, layout, 0);
        p
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let p = unsafe { System.alloc_zeroed(layout) };
        record(if p.is_null() { b'F' } else { b'Z' }, layout, 0);
        p
    }
    unsafe fn dealloc(&self, p: *mut u8, layout: Layout) {
        unsafe { System.dealloc(p, layout) };
        record(b'D', layout, 0);
    }
    unsafe fn realloc(&self, p: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        let q = unsafe { System.realloc(p, layout, size) };
        record(if q.is_null() { b'F' } else { b'R' }, layout, size);
        q
    }
}
fn start() {
    assert!(!ACTIVE.load(Ordering::Acquire));
    *EVENTS.lock().unwrap() = Events {
        rows: [EMPTY; 64],
        len: 0,
        overflow: false,
    };
    ACTIVE.store(true, Ordering::Release);
}
fn stop() -> Events {
    ACTIVE.store(false, Ordering::Release);
    let events = *EVENTS.lock().unwrap();
    assert!(
        !events.overflow,
        "full transcript overflow; no rows discarded"
    );
    events
}
fn one(events: Events, op: u8, expected: Layout) {
    assert_eq!(
        events.len,
        1,
        "unexpected actual allocation transcript: {:?}",
        &events.rows[..events.len]
    );
    let row = events.rows[0];
    assert_eq!(row.op, op);
    assert_eq!(row.size, expected.size());
    assert_eq!(row.align, expected.align());
    assert_eq!(row.new_size, 0);
}
fn emit(events: Events) {
    print!("[");
    for (i, row) in events.rows[..events.len].iter().enumerate() {
        if i > 0 {
            print!(",");
        }
        print!(
            "{{\"op\":\"{}\",\"size\":{},\"align\":{},\"new_size\":{}}}",
            row.op as char, row.size, row.align, row.new_size
        );
    }
    print!("]");
}
fn check<T: ?Sized>(name: &str, value_layout: Layout, create: impl Fn() -> Arc<T>) {
    let expected = Plan::probe_candidate(value_layout)
        .expect("actual candidate profile")
        .layout();
    start();
    let owner = create();
    let creation = stop();
    one(creation, b'A', expected);
    let weak = Arc::downgrade(&owner);
    start();
    drop(owner);
    let strong_drop = stop();
    assert_eq!(
        strong_drop.len,
        0,
        "Weak must retain physical canonical allocation: {:?}",
        &strong_drop.rows[..strong_drop.len]
    );
    start();
    drop(weak);
    let weak_drop = stop();
    one(weak_drop, b'D', expected);
    let no_weak = create();
    start();
    drop(no_weak);
    let immediate = stop();
    one(immediate, b'D', expected);
    print!(
        "{{\"name\":{name:?},\"planned_size\":{},\"planned_align\":{},\"creation\":",
        expected.size(),
        expected.align()
    );
    emit(creation);
    print!(",\"last_strong_with_weak\":");
    emit(strong_drop);
    print!(",\"last_weak\":");
    emit(weak_drop);
    print!(",\"last_strong_without_weak\":");
    emit(immediate);
    print!("}}");
}
fn shared_lease_drop_order() {
    struct DropMarker(u8);
    impl Drop for DropMarker {
        fn drop(&mut self) {
            let _ = self.0;
            record(b'Q', Layout::new::<Self>(), 0);
        }
    }
    let expected = Plan::probe_candidate(Layout::new::<DropMarker>())
        .unwrap()
        .layout();
    start();
    let owner = no_weak_arc_owner::NoWeakArc::new(DropMarker(1));
    let creation = stop();
    one(creation, b'A', expected);
    let second = owner.clone();
    start();
    drop(owner);
    let nonlast = stop();
    assert_eq!(nonlast.len, 0);
    start();
    drop(second);
    let last = stop();
    assert_eq!(
        last.len,
        2,
        "complete actual self-lease transcript: {:?}",
        &last.rows[..last.len]
    );
    assert_eq!(
        (last.rows[0].op, last.rows[0].size, last.rows[0].align),
        (b'D', expected.size(), expected.align())
    );
    assert_eq!(
        (last.rows[1].op, last.rows[1].size, last.rows[1].align),
        (
            b'Q',
            Layout::new::<DropMarker>().size(),
            Layout::new::<DropMarker>().align()
        ),
        "quota/payload drop MUST follow physical Arc free"
    );
    print!("{{\"name\":\"source-shared-lease-drop-order\",\"planned_size\":{},\"planned_align\":{},\"creation\":",expected.size(),expected.align());
    emit(creation);
    print!(",\"nonlast_owner\":");
    emit(nonlast);
    print!(",\"last_owner\":");
    emit(last);
    print!("}}");
}

fn main() {
    // Warm the output machinery before ANY recording window, not by discarding
    // probe events. Every actual recorded allocation remains in the transcript.
    println!(
        "{{\"profile\":{:?},\"scope\":\"standalone-single-thread-test-only\",\"cases\":[",
        Plan::profile_description()
    );
    check("unit", Layout::new::<()>(), || Arc::new(()));
    print!(",");
    check("byte", Layout::new::<u8>(), || Arc::new(7u8));
    print!(",");
    check("word", Layout::new::<u64>(), || Arc::new(8u64));
    print!(",");
    check("sized64", Layout::new::<[u8; 64]>(), || Arc::new([2u8; 64]));
    print!(",");
    #[repr(align(4096))]
    struct High([u8; 3]);
    let _ = High([1; 3]).0;
    check("align4096", Layout::new::<High>(), || {
        Arc::new(High([3; 3]))
    });
    print!(",");
    check("empty-str", Layout::array::<u8>(0).unwrap(), || {
        Arc::<str>::from("")
    });
    print!(",");
    check("ascii-str", Layout::array::<u8>(7).unwrap(), || {
        Arc::<str>::from("abcdefg")
    });
    print!(",");
    let unicode = "\u{e9}\u{6f22}";
    check(
        "utf8-str",
        Layout::array::<u8>(unicode.len()).unwrap(),
        || Arc::<str>::from(unicode),
    );
    print!(",");
    shared_lease_drop_order();
    println!("],\"matched\":true,\"production_profile_approved\":false}}");
}
