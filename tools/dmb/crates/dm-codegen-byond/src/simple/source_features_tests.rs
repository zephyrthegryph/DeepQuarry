use super::*;
use std::path::Path;

fn pinned(name: &str, family: &str) -> byond_dmb::dmb::Dmb {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/translation")
        .join(family);
    byond_dmb::dmb::Dmb::from_bytes(
        &std::fs::read(root.join(format!("{name}.native.bin"))).unwrap(),
    )
    .unwrap()
}
#[test]
fn cpu_source_context_matches_pinned_used_discarded_and_shadow_controls() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/translation/cpu_access");
    for name in [
        "world_cpu",
        "world_cpu_arg",
        "world_cpu_safe",
        "world_cpu_string",
        "local_cpu",
        "obj_cpu",
        "discard",
        "discard_dynamic",
        "discard_sum",
        "return_dynamic",
        "dead",
        "nameof",
        "issaved",
        "discard_initial",
        "return_computed",
        "discard_computed",
    ] {
        let file = if root.join(format!("{name}.dm")).exists() {
            root.join(format!("{name}.dm"))
        } else {
            root.join(format!("{name}.dme"))
        };
        let text = std::fs::read_to_string(file).unwrap();
        let ast = dm_syntax::parse(&text);
        let probe = ast
            .items
            .iter()
            .find(|item| item.header.starts_with("/proc/probe("))
            .unwrap();
        let mut bindings = LowerBindings {
            parameters: vec!["W".into(), "O".into()],
            ..Default::default()
        };
        if name == "world_cpu_arg" {
            bindings.parameter_types.insert("W".into(), "/world".into());
        }
        if name == "obj_cpu" {
            bindings.parameter_types.insert("O".into(), "/obj".into());
        }
        bindings.global_procs.insert(
            "receiver".into(),
            SymRef::Proc {
                owner: SymbolId::of("/"),
                name: SymbolId::of("receiver"),
                occurrence: 0,
            },
        );
        let result = compile_simple_proc_with_bindings(&probe.children, &bindings).unwrap();
        assert_eq!(
            result.source_features.world_cpu,
            pinned(name, "cpu_access").header.flags & 1 != 0,
            "{name}"
        );
    }
}
#[test]
fn graphics_fields_follow_actual_typed_ancestry_and_local_shadows() {
    for (source, owner, parent, expected) in [
        ("return icon", "/obj", None, true),
        ("return icon", "/obj/alias", Some("/datum"), false),
        ("var/icon = 1\nreturn icon", "/obj", None, false),
        ("return nameof(src.icon)", "/obj", None, true),
        ("return initial(src.icon)", "/obj", None, true),
        ("if(0) return src.icon", "/obj", None, true),
    ] {
        let text = format!(
            "/proc/probe()\n{}",
            source
                .lines()
                .map(|line| format!("    {line}\n"))
                .collect::<String>()
        );
        let ast = dm_syntax::parse(&text);
        let mut shared = SharedLowerBindings::default();
        if let Some(parent) = parent {
            shared.parent_types.insert(owner.into(), parent.into());
        }
        let bindings = LowerBindings {
            current_type_path: Some(owner.into()),
            fields: ["icon".into()].into_iter().collect(),
            shared: Some(Arc::new(shared)),
            ..Default::default()
        };
        let result = compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        assert_eq!(
            result.source_features.native_graphics, expected,
            "{source} {owner}"
        );
    }
}
