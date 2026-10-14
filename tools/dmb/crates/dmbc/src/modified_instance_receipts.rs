//! Compile-only native facts, independent of production descriptor admission.
use byond_dmb::dmb::Dmb;
use sha2::{Digest, Sha256};

fn root() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/phase1/native_modified_instances")
}
fn image(case: &str) -> Dmb {
    Dmb::from_bytes(&std::fs::read(root().join(format!("{case}.native.bin"))).unwrap()).unwrap()
}
fn modified_fields(image: &Dmb, name: &str) -> Vec<(u8, u32)> {
    // Builtin formal arguments share names such as a/b with our authored
    // defaults. Count every matching modified default, excluding unrelated
    // null/number argument records; expected cardinalities remain exact.
    image
        .variables
        .iter()
        .filter(|field| field.kind == 41 && image.string(field.name) == Some(name.as_bytes()))
        .map(|field| (field.kind, field.value))
        .collect()
}
fn assignment(field: u32, value: u32) -> Vec<u32> {
    vec![0x50, value, 0x34, 65500, 65486, field]
}

#[test]
fn modified_instance_receipts_bind_every_input_binary_and_native_diagnostic() {
    let receipt: serde_json::Value =
        serde_json::from_slice(&std::fs::read(root().join("receipt.json")).unwrap()).unwrap();
    assert_eq!(receipt["compiler"], "516.1687");
    let compiler_hash = "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0";
    assert_eq!(receipt["compiler_sha256"], compiler_hash);
    let compiler = std::path::Path::new("D:/Program Files (x86)/BYOND516/bin/dm.exe");
    if compiler.exists() {
        assert_eq!(
            format!("{:x}", Sha256::digest(std::fs::read(compiler).unwrap())),
            compiler_hash
        );
    }
    for (name, hash) in receipt["files"].as_object().unwrap() {
        assert_eq!(
            format!(
                "{:x}",
                Sha256::digest(std::fs::read(root().join(name)).unwrap())
            ),
            hash.as_str().unwrap(),
            "{name}"
        );
    }
    for (case, error) in [
        ("outer_field-corrected", "only_outer: undefined var"),
        ("outer_constant-corrected", "ONLY_OUTER: undefined var"),
        ("receiver_constant", "C: bad constant"),
        ("lexical_constant", "C: bad constant"),
    ] {
        let log = std::fs::read_to_string(root().join(format!("{case}.stdout.txt"))).unwrap();
        assert!(log.contains(error), "{case}");
        assert!(log.contains("1 error, 0 warnings"), "{case}");
        assert!(!root().join(format!("{case}.native.bin")).exists());
    }
}

#[test]
fn modified_instance_native_descriptors_deduplicate_and_preserve_repeated_writes() {
    let native = image("positive_final");
    assert_eq!(modified_fields(&native, "a"), vec![(41, 0), (41, 0)]);
    assert_eq!(modified_fields(&native, "b"), vec![(41, 0)]);
    assert_eq!(modified_fields(&native, "c"), vec![(41, 1)]);
    assert_eq!(modified_fields(&native, "d"), vec![(41, 1)]);
    assert_eq!(native.string(437), Some(b"amount".as_slice()));
    assert_eq!(native.string(438), Some(b"other".as_slice()));
    for (descriptor, initializer) in [(0, 70), (1, 69)] {
        let instance = &native.instances[descriptor];
        assert_eq!(
            (instance.kind, instance.class, instance.initializer),
            (9, 0, initializer)
        );
    }
    let mut one = assignment(437, 1);
    one.push(0);
    let mut two = assignment(437, 1);
    two.extend(assignment(438, 2));
    two.push(0);
    assert_eq!(native.proc_code_words(70).unwrap(), one);
    assert_eq!(native.proc_code_words(69).unwrap(), two);
    for path in [
        b"/datum/outer/proc/local".as_slice(),
        b"/proc/root_local".as_slice(),
    ] {
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path))
            .unwrap();
        assert_eq!(
            native.proc_code_words(id).unwrap(),
            vec![0x60, 41, 0, 0x34, 65498, 0, 0]
        );
    }
    let datum = image("datum_reordered");
    assert_eq!(modified_fields(&datum, "a"), vec![(41, 0)]);
    assert_eq!(modified_fields(&datum, "b"), vec![(41, 0)]);
    assert_eq!(modified_fields(&datum, "c"), vec![(41, 1)]);
    assert_eq!(
        (
            datum.instances[0].kind,
            datum.instances[0].class,
            datum.instances[0].initializer
        ),
        (32, 0, 68)
    );
    assert_eq!(datum.proc_code_words(68).unwrap(), two);
    let mut repeated = assignment(437, 1);
    repeated.extend(assignment(437, 2));
    repeated.push(0);
    assert_eq!(datum.proc_code_words(67).unwrap(), repeated);
}

#[test]
fn modified_instance_native_static_and_const_fields_use_instance_setter_encoding() {
    for case in ["static_field-corrected", "const_field-corrected"] {
        let native = image(case);
        assert_eq!(modified_fields(&native, "a"), vec![(41, 0)]);
        assert_eq!(
            (
                native.instances[0].kind,
                native.instances[0].class,
                native.instances[0].initializer
            ),
            (9, 0, 67)
        );
        let mut words = assignment(437, 1);
        words.push(0);
        assert_eq!(native.proc_code_words(67).unwrap(), words, "{case}");
        let log = std::fs::read_to_string(root().join(format!("{case}.stdout.txt"))).unwrap();
        assert!(log.contains("0 errors, 0 warnings"), "{case}");
    }
}

#[test]
fn const_storage_native_footer_and_class_records_allocate_shared_indexed_fields() {
    for (case, flags) in [("const_field-corrected", 3), ("static_field-corrected", 1)] {
        let native = image(case);
        assert_eq!(
            native.string(native.classes[0].initial_ids[0]),
            Some(b"/obj/base".as_slice())
        );
        let variables = native.classes[0].lists_and_procs[4] as usize;
        assert_eq!(native.lists[variables], vec![67, flags], "{case}");
        let field = &native.variables[67];
        assert_eq!(native.string(field.name), Some(b"amount".as_slice()));
        assert_eq!((field.kind, field.value), (42, 0));
        let footer = &native.lists[native.variable_footer as usize];
        let record = footer
            .chunks_exact(2)
            .filter(|row| row[0] == 67)
            .collect::<Vec<_>>();
        assert_eq!(record, vec![&[67, flags][..]], "{case}");
        assert_eq!(footer.len() % 2, 0);
        assert_eq!(&footer[footer.len() - 4..], &[67, flags, 68, 1]);
    }
}

#[test]
fn modified_resources_native_hash_bound_payload_equality_controls_descriptor_dedup() {
    let root = root().parent().unwrap().join("native_modified_resources");
    let receipt: serde_json::Value =
        serde_json::from_slice(&std::fs::read(root.join("receipt.json")).unwrap()).unwrap();
    assert_eq!(
        receipt["compiler_sha256"],
        "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
    );
    for (name, hash) in receipt["files"].as_object().unwrap() {
        assert_eq!(
            format!(
                "{:x}",
                Sha256::digest(std::fs::read(root.join(name)).unwrap())
            ),
            hash.as_str().unwrap(),
            "{name}"
        );
    }
    for (case, count) in [
        ("aliases", 1),
        ("same_payload-explicit", 1),
        ("different_payload-explicit", 2),
    ] {
        let directory = root.join(case);
        let native = Dmb::from_bytes(&std::fs::read(directory.join("probe.dmb")).unwrap()).unwrap();
        assert_eq!(native.resources.len(), count, "{case}");
        assert_eq!(modified_fields(&native, "a"), vec![(41, 0)]);
        assert_eq!(
            modified_fields(&native, "b"),
            vec![(41, if count == 1 { 0 } else { 1 })]
        );
        let bytes = std::fs::read(directory.join("probe.rsc")).unwrap();
        let entries = byond_dmb::rsc::read_all(&mut bytes.as_slice()).unwrap();
        let payloads = entries
            .iter()
            .map(|entry| match entry {
                byond_dmb::rsc::Entry::Named(resource) => resource.data.as_slice(),
                _ => panic!("opaque resource in positive control"),
            })
            .collect::<Vec<_>>();
        assert_eq!(payloads.len(), 2);
        assert_eq!(payloads[0] == payloads[1], count == 1, "{case}");
        let words = native
            .proc_code_words(native.instances[0].initializer as usize)
            .unwrap();
        assert_eq!(words, vec![0x60, 12, 0, 0x34, 65500, 65486, 437, 0]);
        if count == 2 {
            assert_eq!(
                native
                    .proc_code_words(native.instances[1].initializer as usize)
                    .unwrap(),
                vec![0x60, 12, 1, 0x34, 65500, 65486, 437, 0]
            );
        }
    }
}

#[test]
fn modified_instance_native_compound_values_preserve_list_and_nested_modes() {
    for (case, prefix) in [
        ("literal_list", vec![0x50, 1, 0x50, 2, 0x60, 9, 0, 0x1a, 3]),
        ("newlist", vec![0x60, 9, 0, 1, 0, 0x1a, 1]),
        ("typepath", vec![0x60, 9, 0]),
    ] {
        let native = image(case);
        let mut words = prefix;
        words.extend([0x34, 65500, 65486, 437, 0]);
        assert_eq!(native.proc_code_words(67).unwrap(), words, "{case}");
        assert_eq!(native.instances[0].initializer, 67);
    }
    let nested = image("nested");
    assert_eq!(nested.instances[0].initializer, 68);
    assert_eq!(nested.instances[1].initializer, 67);
    assert_eq!(
        nested.proc_code_words(67).unwrap(),
        vec![0x60, 41, 0, 0x34, 65500, 65486, 438, 0]
    );
    let mut inner = assignment(437, 2);
    inner.push(0);
    assert_eq!(nested.proc_code_words(68).unwrap(), inner);
}

#[test]
fn modified_instance_native_scalar_equivalence_shares_descriptor_identity() {
    let native = image("semantic_equivalence");
    for name in ["a", "b", "c"] {
        assert_eq!(modified_fields(&native, name), vec![(41, 0)]);
    }
    for name in ["d", "e"] {
        assert_eq!(modified_fields(&native, name), vec![(41, 1)]);
    }
    let mut numeric = assignment(437, 1);
    numeric.push(0);
    assert_eq!(native.proc_code_words(68).unwrap(), numeric);
    assert_eq!(
        native.proc_code_words(67).unwrap(),
        vec![0x60, 6, 51, 0x34, 65500, 65486, 438, 0]
    );
    assert_eq!(native.string(51), Some(b"x".as_slice()));
}

#[test]
fn native_returngrammar_receipts_reject_bare_and_preserve_grouped_modified_values() {
    let directory = root().parent().unwrap().join("native_modified_returns");
    let receipt: serde_json::Value =
        serde_json::from_slice(&std::fs::read(directory.join("receipt.json")).unwrap()).unwrap();
    assert_eq!(
        receipt["compiler_sha256"],
        "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
    );
    for (name, hash) in receipt["files"].as_object().unwrap() {
        assert_eq!(
            format!(
                "{:x}",
                Sha256::digest(std::fs::read(directory.join(name)).unwrap())
            ),
            hash.as_str().unwrap(),
            "{name}"
        );
    }
    for (case, diagnostic) in [
        ("bare", "probe.dme:5:error: amount: undefined var"),
        ("outer_visible", "probe.dme:7:error: amount: bad variable"),
    ] {
        let log = std::fs::read_to_string(directory.join(case).join("stdout.txt")).unwrap();
        assert!(log.contains(diagnostic), "{case}");
        assert!(log.contains("1 error, 0 warnings"));
        assert!(!directory.join(case).join("probe.dmb").exists());
    }
    let native =
        Dmb::from_bytes(&std::fs::read(directory.join("grouped/probe.dmb")).unwrap()).unwrap();
    assert_eq!(
        native.string(native.procs[0].strings[0]),
        Some(b"/proc/p".as_slice())
    );
    assert_eq!(
        native.proc_code_words(0).unwrap(),
        vec![0x60, 41, 0, 0x12, 0]
    );
    assert_eq!(
        (
            native.instances[0].kind,
            native.instances[0].class,
            native.instances[0].initializer
        ),
        (9, 0, 68)
    );
}
