//! Native compile-only evidence: decoded ABI literals, not inferred SDK values.
#[test]
fn native_sdk_macro_values_match_hash_bound_binary_receipts() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/phase1/native_sdk_macros");
    let receipt: serde_json::Value =
        serde_json::from_slice(&std::fs::read(root.join("receipt.json")).unwrap()).unwrap();
    let image =
        byond_dmb::dmb::Dmb::from_bytes(&std::fs::read(root.join("positive.native.bin")).unwrap())
            .unwrap();
    for entry in receipt["initial_macros"].as_array().unwrap() {
        let name = entry["name"].as_str().unwrap();
        for (prefix, key) in [("/proc/", "root_words"), ("/datum/proc/", "datum_words")] {
            let path = format!("{prefix}probe_{name}");
            let id = image
                .procs
                .iter()
                .position(|proc| image.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let expected: Vec<u32> = entry[key]
                .as_array()
                .unwrap()
                .iter()
                .map(|word| word.as_u64().unwrap() as u32)
                .collect();
            assert_eq!(image.proc_code_words(id).unwrap(), expected, "{path}");
            if entry["kind"] == "text" {
                assert_eq!(
                    image.string(expected[2]),
                    Some(entry["value"].as_str().unwrap().as_bytes()),
                    "{path}"
                );
            }
        }
        let path = format!("/proc/macro_{name}");
        let id = image
            .procs
            .iter()
            .position(|proc| image.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            image.proc_code_words(id).unwrap(),
            vec![0x50, 1, 0x12, 0],
            "{name}"
        );
    }
    let id = image
        .procs
        .iter()
        .position(|proc| image.string(proc.strings[0]) == Some(b"/proc/macro_DM_VERSION"))
        .unwrap();
    assert_eq!(image.proc_code_words(id).unwrap(), vec![0x50, 0, 0x12, 0]);
}

#[test]
fn native_negative_macro_precedence_matches_fresh_scalar_ast() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/phase1/native_sdk_macros");
    let receipt: serde_json::Value =
        serde_json::from_slice(&std::fs::read(root.join("receipt.json")).unwrap()).unwrap();
    let image = byond_dmb::dmb::Dmb::from_bytes(
        &std::fs::read(root.join("precedence.native.bin")).unwrap(),
    )
    .unwrap();
    let plan = dm_preprocess::regions::plan_regions(
        &root.join("precedence.dme"),
        &dm_preprocess::FileSystem,
        &std::collections::BTreeMap::new(),
    );
    let expanded = dm_preprocess::regions::expand_regions_text(&plan, 2);
    assert!(expanded.diagnostics.is_empty());
    let parsed = dm_syntax::parse(&expanded.text);
    assert!(parsed.diagnostics.is_empty());
    for entry in receipt["precedence"].as_array().unwrap() {
        let path = entry["path"].as_str().unwrap();
        let id = image
            .procs
            .iter()
            .position(|proc| image.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected: Vec<u32> = entry["words"]
            .as_array()
            .unwrap()
            .iter()
            .map(|word| word.as_u64().unwrap() as u32)
            .collect();
        assert_eq!(image.proc_code_words(id).unwrap(), expected, "{path}");
        let header = format!("{path}()");
        let item = parsed
            .items
            .iter()
            .find(|item| item.header == header)
            .unwrap();
        let expression =
            dm_syntax::parse_expression(item.children[0].header.strip_prefix("return ").unwrap());
        assert!(expression.diagnostics.is_empty(), "{path}");
        let value = dm_tree::constants::evaluate_expr_with_resources(
            expression.expr.as_ref().unwrap(),
            |_| None,
            |_| None,
            |_| None,
            |_| None,
        );
        let Some(dm_tree::constants::Constant::Number(value)) = value else {
            panic!("{path}: scalar value unavailable");
        };
        assert_eq!(
            value.to_bits(),
            entry["number_bits"].as_u64().unwrap() as u32,
            "{path}"
        );
    }
}
