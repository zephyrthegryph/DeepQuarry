use byond_dmb::dmb::Dmb;
use std::collections::{BTreeSet, HashSet};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("usage: export_test_types FILE.dmb")?;
    let image = Dmb::from_bytes(&std::fs::read(path)?)?;
    let base = image.classes.iter().position(|class| image.string(class.path_string_id()) == Some(b"/datum/unit_test".as_slice())).ok_or("missing unit test base")? as u32;
    let mut paths = BTreeSet::new();
    for (id, class) in image.classes.iter().enumerate() {
        if id as u32 == base { continue; }
        let mut at = class.parent_class_id();
        let mut seen = HashSet::new();
        while at != 0xffff && seen.insert(at) {
            if at == base {
                paths.insert(String::from_utf8(image.string(class.path_string_id()).ok_or("invalid class path")?.to_vec())?);
                break;
            }
            at = image.classes.get(at as usize).ok_or("invalid class parent")?.parent_class_id();
        }
    }
    for path in paths { println!("{path}"); }
    Ok(())
}