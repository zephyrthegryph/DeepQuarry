use byond_dmb::dmb::Dmb;
use std::collections::{BTreeMap, BTreeSet};
fn tokens(d: &Dmb) -> BTreeMap<String, u32> {
    let mut out = BTreeMap::new();
    for (i, c) in d.classes.iter().enumerate() {
        let p = String::from_utf8_lossy(d.string(c.path_string_id()).unwrap_or_default());
        if p.is_empty() {
            continue;
        }
        for (id, _) in d.class_variable_declarations(i).unwrap_or_default() {
            let v = &d.variables[id as usize];
            if v.kind == 62 {
                out.insert(
                    format!(
                        "{p}|decl|{}",
                        String::from_utf8_lossy(d.string(v.name).unwrap())
                    ),
                    v.value,
                );
            }
        }
        let mut occ = BTreeMap::new();
        for v in d.class_initial_values(i).unwrap_or_default() {
            if v.value.tag() == 62 {
                let n = d.string(d.variables[v.variable_id as usize].name).unwrap();
                let at = occ.entry(n).or_insert(0);
                out.insert(
                    format!("{p}|init|{}|{at}", String::from_utf8_lossy(n)),
                    v.value.id(),
                );
                *at += 1;
            }
        }
    }
    let mut owners = BTreeMap::<u32, Vec<String>>::new();
    for (i, c) in d.classes.iter().enumerate() {
        let path = String::from_utf8_lossy(d.string(c.path_string_id()).unwrap_or_default());
        for (id, flags) in d.class_variable_declarations(i).unwrap_or_default() {
            if flags & 1 != 0 {
                owners.entry(id).or_default().push(path.to_string());
            }
        }
    }
    for paths in owners.values_mut() {
        paths.sort();
    }
    let mut occ = BTreeMap::new();
    for p in d.lists[d.variable_footer as usize].chunks_exact(2) {
        let v = &d.variables[p[0] as usize];
        if v.kind == 62 {
            let n = d.string(v.name).unwrap();
            let at = occ.entry(n).or_insert(0);
            out.insert(
                if let Some(paths) = owners.get(&p[0]) {
                    format!("global|owners:{paths:?}|{}", String::from_utf8_lossy(n))
                } else {
                    format!("global|{}|{at}", String::from_utf8_lossy(n))
                },
                v.value,
            );
            if !owners.contains_key(&p[0]) {
                *at += 1;
            }
        }
    }
    out
}
fn main() {
    let a: Vec<_> = std::env::args().collect();
    if a.len() != 3 {
        eprintln!("usage: initializer_identity_audit NATIVE.dmb TRANSLATED.dmb");
        std::process::exit(2);
    }
    let n = tokens(&Dmb::from_bytes(&std::fs::read(&a[1]).unwrap()).unwrap());
    let t = tokens(&Dmb::from_bytes(&std::fs::read(&a[2]).unwrap()).unwrap());
    let mut split = BTreeMap::<u32, BTreeSet<u32>>::new();
    let mut merge = BTreeMap::<u32, BTreeSet<u32>>::new();
    let mut paired = 0;
    for (k, &v) in &n {
        if let Some(&w) = t.get(k) {
            paired += 1;
            split.entry(v).or_default().insert(w);
            merge.entry(w).or_default().insert(v);
        }
    }
    println!("native_keys={} actual_keys={} paired={paired} missing_native={} missing_actual={} split_groups={} merged_groups={}",n.len(),t.len(),t.keys().filter(|k|!n.contains_key(*k)).count(),n.keys().filter(|k|!t.contains_key(*k)).count(),split.values().filter(|v|v.len()>1).count(),merge.values().filter(|v|v.len()>1).count());
    for (k, &v) in &n {
        if let Some(&w) = t.get(k) {
            if split[&v].len() > 1 || merge[&w].len() > 1 {
                println!("{k} native={v} translated={w}");
            }
        } else {
            println!("MISSING {k}");
        }
    }
    if paired != n.len()
        || paired != t.len()
        || split.values().any(|values| values.len() > 1)
        || merge.values().any(|values| values.len() > 1)
    {
        std::process::exit(1);
    }
}
