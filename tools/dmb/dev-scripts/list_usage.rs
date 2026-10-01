//! Read-only list allocation census. Does not infer runtime record reachability.
use byond_dmb::dmb::Dmb;
use std::collections::{HashMap, HashSet};

fn main() {
    for path in std::env::args().skip(1) {
        let dmb = Dmb::from_bytes(&std::fs::read(&path).unwrap()).unwrap();
        let mut referenced = HashSet::new();
        let mut mark = |id: u32| {
            if id != 0xffff {
                assert!((id as usize) < dmb.lists.len());
                referenced.insert(id as usize);
            }
        };
        for class in &dmb.classes {
            for id in [
                class.verb_list_id(),
                class.proc_list_id(),
                class.initialized_variable_list_id(),
                class.defining_variable_list_id(),
                class.overriding_variable_list_id(),
            ] {
                mark(id);
            }
        }
        for proc in &dmb.procs {
            for id in proc.code_locals_args {
                mark(id);
            }
        }
        for run in &dmb.grid {
            mark(run.contents);
        }
        mark(dmb.world.proc_list_id());
        mark(dmb.variable_footer);
        let mut unique = HashMap::new();
        let mut live_unique = HashSet::new();
        let mut unreferenced_words = 0usize;
        for (index, list) in dmb.lists.iter().enumerate() {
            *unique.entry(list).or_insert(0usize) += 1;
            if referenced.contains(&index) {
                live_unique.insert(list);
            } else {
                unreferenced_words += list.len();
            }
        }
        println!("{path}: lists={} referenced={} unreferenced={} unreferenced_words={} unique_word_arrays={} referenced_unique_word_arrays={} savefile_version={}",
            dmb.lists.len(), referenced.len(), dmb.lists.len() - referenced.len(),
            unreferenced_words, unique.len(), live_unique.len(), dmb.world.savefile_byond_version);
    }
}
