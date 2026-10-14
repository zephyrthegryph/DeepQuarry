//! Interim semantic equivalence for stable incremental numbering
//! (tools/dmb/doc/structural_change_set.md, addendum). Two DMBs are equal when
//! the structural comparator (classes and procedures paired by path, typed
//! operands resolved) reports nothing AND the runtime-observable orders match:
//! the class table order and, per class, the verb, proc, defining-var and
//! initialized-var list orders by name. Replace with `dmb-equiv` once merged.
use crate::compare::{compare_dmbs, CompareOptions};
use byond_dmb::dmb::Dmb;

fn text(dmb: &Dmb, id: u32) -> String {
    dmb.string(id)
        .map(|bytes| String::from_utf8_lossy(bytes).into_owned())
        .unwrap_or_else(|| format!("<string {id}>"))
}
fn list(dmb: &Dmb, id: u32) -> Vec<u32> {
    dmb.lists.get(id as usize).map(|words| words.to_vec()).unwrap_or_default()
}
fn proc_name(dmb: &Dmb, id: u32) -> String {
    dmb.procs
        .get(id as usize)
        .map(|proc_| text(dmb, proc_.strings[0]))
        .unwrap_or_else(|| format!("<proc {id}>"))
}
fn var_name(dmb: &Dmb, id: u32) -> String {
    dmb.variables
        .get(id as usize)
        .map(|variable| text(dmb, variable.name))
        .unwrap_or_else(|| format!("<var {id}>"))
}
/// Ordered member names of one class, by list.
fn class_orders(dmb: &Dmb, class: usize) -> Vec<(&'static str, Vec<String>)> {
    let record = &dmb.classes[class];
    let procs = |id: u32| list(dmb, id).into_iter().map(|proc_| proc_name(dmb, proc_)).collect();
    let pairs = |id: u32| {
        list(dmb, id)
            .chunks(2)
            .map(|pair| var_name(dmb, pair[0]))
            .collect()
    };
    vec![
        ("verbs", procs(record.verb_list_id())),
        ("procs", procs(record.proc_list_id())),
        ("defined vars", pairs(record.defining_variable_list_id())),
        (
            "initialized vars",
            dmb.class_initial_values(class)
                .unwrap_or_default()
                .into_iter()
                .map(|entry| var_name(dmb, entry.variable_id))
                .collect(),
        ),
    ]
}
/// Every difference found, up to `limit`; empty means equivalent.
pub fn semantic_differences(expected: &Dmb, actual: &Dmb, limit: usize) -> Vec<String> {
    let mut out: Vec<String> = compare_dmbs(
        expected,
        actual,
        &CompareOptions {
            max_discrepancies: limit,
            ..Default::default()
        },
    )
    .into_iter()
    .map(|d| format!("{} {}: expected {} actual {}", d.path, d.field, d.expected, d.actual))
    .collect();
    let order = |dmb: &Dmb| -> Vec<String> {
        dmb.classes.iter().map(|class| text(dmb, class.path_string_id())).collect()
    };
    let (left, right) = (order(expected), order(actual));
    if left != right {
        let at = left.iter().zip(&right).position(|(a, b)| a != b).unwrap_or(left.len().min(right.len()));
        out.push(format!(
            "class table order differs at {at}: expected {:?} actual {:?}",
            left.get(at),
            right.get(at)
        ));
        return out;
    }
    for class in 0..expected.classes.len() {
        if out.len() >= limit {
            break;
        }
        for ((name, a), (_, b)) in class_orders(expected, class).into_iter().zip(class_orders(actual, class)) {
            if a != b {
                out.push(format!("{} {name} order: expected {a:?} actual {b:?}", left[class]));
            }
        }
    }
    out
}
