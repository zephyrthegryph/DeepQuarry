//! Read-only fixture type availability and class metadata comparison.
use byond_dmb::dmb::Dmb;
use std::{collections::BTreeMap, env, fs};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = env::args().collect();
    let native = Dmb::from_bytes(&fs::read(&args[1])?)?;
    let actual = Dmb::from_bytes(&fs::read(&args[2])?)?;
    let fixture: serde_json::Value = serde_json::from_slice(&fs::read(&args[3])?)?;
    let classes = |dmb: &Dmb| {
        dmb.classes
            .iter()
            .enumerate()
            .filter_map(|(i, c)| {
                dmb.string(c.path_string_id())
                    .map(|p| (String::from_utf8_lossy(p).into_owned(), i))
            })
            .collect::<BTreeMap<_, _>>()
    };
    let nc = classes(&native);
    let ac = classes(&actual);
    let mut missing = 0;
    for path in fixture["storage"]
        .as_object()
        .ok_or("missing storage fixture")?
        .keys()
    {
        match (nc.get(path), ac.get(path)) {
            (Some(_), None) => {
                println!("RUST_MISSING {path}");
                missing += 1;
            }
            (None, Some(_)) => println!("NATIVE_MISSING {path}"),
            (None, None) => println!("BOTH_MISSING {path}"),
            (Some(n), Some(a)) => {
                let n = &native.classes[*n];
                let a = &actual.classes[*a];
                if n.flags != a.flags {
                    println!("FLAGS {path} native={:x} rust={:x}", n.flags, a.flags);
                }
            }
        }
    }
    for path in [
        "/obj/item/storage/dicecup/loaded",
        "/obj/item/storage/wallet/random",
    ] {
        let n = nc[path];
        let a = ac[path];
        println!(
            "HEADER {path} flags={:x}/{:x} layer={:x}/{:x}",
            native.classes[n].flags,
            actual.classes[a].flags,
            native.classes[n].layer_bits,
            actual.classes[a].layer_bits
        );
        for name in ["plane", "vis_flags"] {
            let get = |dmb: &Dmb, id| {
                dmb.class_builtin_overrides(id)
                    .unwrap()
                    .into_iter()
                    .find(|value| dmb.string(value.name_string_id) == Some(name.as_bytes()))
                    .map(|value| value.value.number_bits())
            };
            let nv = get(&native, n);
            let av = get(&actual, a);
            println!("DEFAULT {path}.{name} native={nv:?} rust={av:?}");
            if nv != av {
                return Err(format!("default mismatch {path}.{name}").into());
            }
        }
    }
    println!(
        "storage_holders={} rust_missing={missing}",
        fixture["storage"].as_object().unwrap().len()
    );
    Ok(())
}
