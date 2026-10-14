use super::*;
struct Memory(BTreeMap<PathBuf, String>);
impl SourceProvider for Memory {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.0.get(path).cloned().ok_or_else(|| "missing".into())
    }
}
fn fixture(files: &[(&str, &str)]) -> Memory {
    Memory(
        files
            .iter()
            .map(|(p, s)| (PathBuf::from(p), (*s).into()))
            .collect(),
    )
}

#[test]
fn large_macro_environment_uses_compact_leaf_cache() {
    let mut manifest = String::new();
    for index in 0..1000 {
        manifest.push_str(&format!("#define M{index} {index}\n"));
    }
    manifest.push_str("#include \"leaf.dm\"\n");
    let files = Memory(BTreeMap::from([
        (PathBuf::from("game.dme"), manifest),
        (PathBuf::from("leaf.dm"), "/datum/test\n".into()),
    ]));
    let mut cache = PreprocessCache::default();
    let output =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert!(output.diagnostics.is_empty());
    assert_eq!(output.text, "/datum/test\n");
    let entry = &cache.entries[Path::new("leaf.dm")][0];
    assert!(entry.macro_changes.is_empty());
    let replayed =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(replayed, output);
    assert_eq!(cache.hits, 1);
}

#[test]
fn large_macro_value_is_not_copied_into_leaf_cache() {
    let manifest = format!(
        "#define BIG {}\n#include \"leaf.dm\"\n",
        "x".repeat(64 * 1024 + 1)
    );
    let files = Memory(BTreeMap::from([
        (PathBuf::from("game.dme"), manifest),
        (PathBuf::from("leaf.dm"), "/datum/test\n".into()),
    ]));
    let mut cache = PreprocessCache::default();
    let output =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert!(output.diagnostics.is_empty());
    assert!(cache.entries[Path::new("leaf.dm")][0]
        .macro_changes
        .is_empty());
}

#[test]
fn leaf_cache_has_a_fixed_path_budget() {
    let mut files = BTreeMap::new();
    let mut manifest = String::new();
    for index in 0..=MAX_CACHED_PATHS {
        let name = format!("leaf_{index}.dm");
        manifest.push_str(&format!("#include \"{name}\"\n"));
        files.insert(PathBuf::from(name), "/datum/test\n".into());
    }
    files.insert(PathBuf::from("game.dme"), manifest);
    let mut cache = PreprocessCache::default();
    let output = preprocess_project_cached(
        Path::new("game.dme"),
        &Memory(files),
        &BTreeMap::new(),
        &mut cache,
    );
    assert!(output.diagnostics.is_empty());
    assert_eq!(cache.entries.len(), MAX_CACHED_PATHS);
}

#[test]
fn spaced_include_is_not_mistaken_for_leaf() {
    let files = fixture(&[
        ("game.dme", "#include \"parent.dm\"\n"),
        ("parent.dm", "# include \"child.dm\"\n"),
        ("child.dm", "/obj/child\n"),
    ]);
    let mut cache = PreprocessCache::default();
    let first =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    let second =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(first, second);
    assert!(cache.entries.contains_key(Path::new("parent.dm")));
    assert!(cache.entries.contains_key(Path::new("child.dm")));
}

#[test]
fn large_leaf_replays_within_unchanged_resident_budget() {
    let source = format!(
        "/obj/test\n{}",
        "  value = 7 // sizable leaf content\n".repeat(7000)
    );
    assert!(source.len() > 128 * 1024);
    let files = Memory(BTreeMap::from([
        (PathBuf::from("game.dme"), "#include \"leaf.dm\"\n".into()),
        (PathBuf::from("leaf.dm"), source),
    ]));
    let mut cache = PreprocessCache::default();
    let first =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    let second =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(first, second);
    assert_eq!(cache.hits, 1);
    assert!(cache.resident_bytes() <= MAX_CACHE_RESIDENT_BYTES);
}

#[test]
fn excessive_origin_records_are_not_retained() {
    let lines = "/obj/test\n".repeat(MAX_CACHED_ORIGINS + 1);
    let files = Memory(BTreeMap::from([
        (PathBuf::from("game.dme"), "#include \"leaf.dm\"\n".into()),
        (PathBuf::from("leaf.dm"), lines),
    ]));
    let mut cache = PreprocessCache::default();
    let output =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(output.origins.len(), MAX_CACHED_ORIGINS + 1);
    assert!(cache.entries.is_empty());
}

#[test]
fn resident_budget_evicts_cached_entries() {
    let files = fixture(&[
        ("game.dme", "#include \"a.dm\"\n#include \"b.dm\"\n"),
        ("a.dm", "/obj/a\n"),
        ("b.dm", "/obj/b\n"),
    ]);
    let mut cache = PreprocessCache::default();
    preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(cache.entries.len(), 2);
    let one_entry_budget =
        cache.entries[Path::new("b.dm")][0].resident_bytes() + Path::new("b.dm").as_os_str().len();
    cache.enforce_budget(one_entry_budget);
    assert_eq!(cache.entries.len(), 1);
    assert!(cache.entries.contains_key(Path::new("b.dm")));
    assert_eq!(cache.resident_bytes, one_entry_budget);
    cache.clear();
    assert_eq!(cache.resident_bytes, 0);
}

#[test]
fn resident_budget_drops_history_before_current_files() {
    let files = fixture(&[
        ("game.dme", "#include \"a.dm\"\n#include \"b.dm\"\n"),
        ("a.dm", "/obj/a\n"),
        ("b.dm", "/obj/b\n"),
    ]);
    let mut cache = PreprocessCache::default();
    preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    let current_budget = cache.resident_bytes;
    let historical = CachedUnit::from(DiskEntry::from(&cache.entries[Path::new("b.dm")][0]));
    cache.resident_bytes += historical.resident_bytes();
    cache
        .entries
        .get_mut(Path::new("b.dm"))
        .unwrap()
        .push(historical);
    cache.enforce_budget(current_budget);
    assert_eq!(cache.entries.len(), 2);
    assert!(cache.entries.values().all(|entries| entries.len() == 1));
    assert_eq!(cache.resident_bytes, current_budget);
}

#[test]
fn parallel_chunk_publication_replays_all_files() {
    let mut files = BTreeMap::new();
    let mut manifest = String::new();
    for index in 0..40 {
        let file = format!("leaf_{index}.dm");
        manifest.push_str(&format!("#include \"{file}\"\n"));
        files.insert(PathBuf::from(file), format!("/obj/leaf_{index}\n"));
    }
    files.insert(PathBuf::from("game.dme"), manifest);
    let files = Memory(files);
    let mut cache = PreprocessCache::default();
    let first =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    let directory = std::env::temp_dir().join(format!(
        "dm-preprocess-parallel-{}-{}",
        std::process::id(),
        CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    fs::create_dir_all(&directory).unwrap();
    let path = directory.join("cache.json");
    cache.save_incremental(&path).unwrap();
    let mut restored = PreprocessCache::load_incremental(&path);
    let replay = preprocess_project_cached(
        Path::new("game.dme"),
        &files,
        &BTreeMap::new(),
        &mut restored,
    );
    assert_eq!(first, replay);
    assert_eq!(restored.hits, 40);
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn file_and_line_macros_use_invocation_location() {
    let files = fixture(&[
            ("game.dme", "#include \"src/test.dm\"\n"),
            (
                "src/test.dm",
                "#define HERE __FILE__, __LINE__\n#ifdef __FILE__\n/obj/test\n  x = HERE\n#endif\n#if defined(__LINE__)\n  y = __LINE__\n#endif\n",
            ),
        ]);
    let mut cache = PreprocessCache::default();
    let output =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(
        output.text.contains("x = \"src/test.dm\", 4"),
        "{}",
        output.text
    );
    assert!(output.text.contains("y = 7"));
    let replay =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(output, replay);
    assert_eq!(cache.hits, 1);
}

#[test]
fn file_macro_strips_absolute_worktree_root() {
    let project = PathBuf::from("C:/worktree/project/game.dme");
    let source = PathBuf::from("C:/worktree/project/code/test.dm");
    let files = Memory(BTreeMap::from([
        (project.clone(), "#include \"code/test.dm\"\n".into()),
        (source, "/obj/test\n  file = __FILE__\n".into()),
    ]));
    let output = preprocess_project(&project, &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert_eq!(output.text, "/obj/test\n  file = \"code/test.dm\"\n");
}

#[test]
fn line_macro_uses_physical_invocation_line_after_continuation() {
    let files = fixture(&[
        ("game.dme", "#include \"leaf.dm\"\n"),
        (
            "leaf.dm",
            "#define HERE \\\n    __LINE__\n/obj/probe\n    var/probe_line = HERE\n",
        ),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output.text.contains("probe_line = 4"), "{}", output.text);
}

#[test]
fn leaf_disk_cache_replays_across_project_roots() {
    let first = PathBuf::from("C:/first/game.dme");
    let second = PathBuf::from("C:/second/game.dme");
    let first_leaf = PathBuf::from("C:/first/code/test.dm");
    let second_leaf = PathBuf::from("C:/second/code/test.dm");
    let files = Memory(BTreeMap::from([
        (first.clone(), "#include \"code/test.dm\"\n".into()),
        (second.clone(), "#include \"code/test.dm\"\n".into()),
        (first_leaf.clone(), "/obj/test\n  file = __FILE__\n".into()),
        (second_leaf.clone(), "/obj/test\n  file = __FILE__\n".into()),
    ]));
    let mut cache = PreprocessCache::default();
    let left = preprocess_project_cached(&first, &files, &BTreeMap::new(), &mut cache);
    let path = std::env::temp_dir().join(format!(
        "dm-preprocess-roots-test-{}-{}.json",
        std::process::id(),
        CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    cache.save(&path).unwrap();
    let mut restored = PreprocessCache::load(&path);
    let right = preprocess_project_cached(&second, &files, &BTreeMap::new(), &mut restored);
    assert_eq!(right.text, left.text);
    assert_eq!(right.text, "/obj/test\n  file = \"code/test.dm\"\n");
    assert_eq!(restored.hits, 1);
    assert_eq!(right.origins[0].path.as_path(), second_leaf.as_path());
    assert_eq!(right.units[0].path, second_leaf);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn conditional_macro_name_allows_trailing_comment() {
    let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            (
                "leaf.dm",
                "#define UNIT_TESTS 1\n#ifndef UNIT_TESTS // skipped\n/bad\n#endif\n#ifdef UNIT_TESTS // enabled\n/good\n#endif\n",
            ),
        ]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert_eq!(output.text, "/good\n");
}

#[test]
fn multiline_comments_calls_and_unnamed_variadics() {
    let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            ("leaf.dm", "/**\n * # docs\n */\n#define VALUES(...) list(__VA_ARGS__)\n/obj/test\n  values = VALUES(\n    1,\n    2\n  )\n"),
        ]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output.text.contains("list(1,2)"), "{}", output.text);
}

#[test]
fn continued_token_paste_is_not_a_directive() {
    let files = fixture(&[
        ("game.dme", "#include \"leaf.dm\"\n"),
        (
            "leaf.dm",
            "#define FIELD(X) /obj/test/var/\\\n  ##X = 1\nFIELD(value)\n",
        ),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(
        output.text.contains("/obj/test/var/value = 1"),
        "{}",
        output.text
    );
}

#[test]
fn includes_inside_expressions_and_skin_assets() {
    let files = fixture(&[
        ("game.dme", "#include \"leaf.dm\"\n#include \"skin.dmf\"\n"),
        (
            "leaf.dm",
            "/proc/test()\n  return list(\n    #include \"values.dm\"\n  )\n",
        ),
        ("values.dm", "1, 2\n"),
        ("skin.dmf", "elem \"x\"\n background-color = #fff\n"),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output.text.contains("1, 2"));
    assert!(!output.text.contains("background-color"));
    assert_eq!(output.skin_includes, [PathBuf::from("skin.dmf")]);
}

#[test]
fn continued_string_keeps_blank_physical_lines() {
    let files = fixture(&[
        ("game.dme", "#include \"leaf.dm\"\n"),
        ("leaf.dm", "/obj/test\n  desc = \"first\\\n\n  last\"\n"),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output.text.contains("first"));
    assert!(output.text.contains("last"));
}

#[test]
fn mixed_source_encoding_preserves_valid_unicode() {
    let mut bytes = "// \u{a7} ".as_bytes().to_vec();
    bytes.extend_from_slice(&[0x97, b' ', 0x93, b'x', 0x94]);
    assert_eq!(
        decode_source_bytes(&bytes),
        "// \u{a7} \u{2014} \u{201c}x\u{201d}"
    );
    assert_eq!(decode_source_bytes(b"\xef\xbb\xbf/obj/test"), "/obj/test");
}

#[test]
fn define_comments_do_not_enter_replacement() {
    let files = fixture(&[
            ("game.dme", "#include \"leaf.dm\"\n"),
            (
                "leaf.dm",
                "#define DECAY 0.8 // explained\n#define TEXT \"http://example.test\" // explained\n#define SUM 1/*gap*/+2\n/obj/test\n  a = DECAY + 1\n  b = TEXT\n  c = SUM\n",
            ),
        ]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output.text.contains("a = 0.8 + 1"), "{}", output.text);
    assert!(output.text.contains("b = \"http://example.test\""));
    assert!(output
        .text
        .lines()
        .any(|line| line.split_whitespace().collect::<String>() == "c=1+2"));
    assert_eq!(output.final_macros["DECAY"].replacement, "0.8");
}

#[test]
fn nested_function_macros_and_object_alias_calls_rescan_correctly() {
    let files = fixture(&[
        ("game.dme", "#include \"leaf.dm\"\n"),
        (
            "leaf.dm",
            r#"#define F(x) list(x)
#define ALIAS F
#define CLAMP(x,a,b) clamp(x,a,b)
#define span_small(x) ("<font>" + x + "</font>")
#define STRINGIFY(x) #x
/proc/test()
    var/a = F(F(1))
    var/b = ALIAS(2)
    var/c = CLAMP(CLAMP(1,2,3),4,5)
    var/d = span_small("[span_small("text")]")
    var/e = STRINGIFY(F(1))
"#,
        ),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output.text.contains("list(list(1))"), "{}", output.text);
    assert!(output.text.contains("list(2)"));
    assert!(output.text.contains("clamp(clamp(1,2,3),4,5)"));
    assert!(!output.text.contains("span_small("));
    assert!(output.text.contains("\"F(1)\""));
}

#[test]
fn function_macros_preserve_defined_operand_names() {
    let files = fixture(&[("game.dme", "#define PRESENT 0\n#define ALIAS UNDEFINED\n#define CHECK(x) defined(x)\n#define BARE(x) defined x\n#define WRAP(x) CHECK(x)\n#if CHECK(PRESENT) && CHECK(ALIAS) && !CHECK(MISSING) && BARE(PRESENT) && WRAP(PRESENT)\n/obj/selected\n#endif\n")]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output.text.contains("/obj/selected"), "{}", output.text);
}

#[test]
fn native_predefined_constructor_macros_keep_source_context_and_arity() {
    let files = fixture(&[("game.dme", "#include \"leaf.dm\"\n"), ("leaf.dm", "/proc/test(message)\n    return EXCEPTION(message)\n/proc/quote(message)\n    return REGEX_QUOTE(message)\n/proc/replacement(message)\n    return REGEX_QUOTE_REPLACEMENT(message)\n")]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(
        output
            .text
            .contains("new /exception(message, \"leaf.dm\", 2)"),
        "{}",
        output.text
    );
    assert!(output.text.contains("regex(message, 1)"));
    assert!(output.text.contains("regex(message, 2)"));
    let invalid = fixture(&[
        ("game.dme", "#include \"leaf.dm\"\n"),
        ("leaf.dm", "/proc/test()\n    return EXCEPTION(1, 2)\n"),
    ]);
    assert!(
        !preprocess_project(Path::new("game.dme"), &invalid, &BTreeMap::new())
            .diagnostics
            .is_empty()
    );
}

#[test]
fn assertion_macro_with_nested_interpolation_and_quoted_message_expands() {
    let files = fixture(&[
        ("game.dme", "#include \"leaf.dm\"\n"),
        (
            "leaf.dm",
            r#"#define TEST_ASSERT_EQUAL(a, b, message) do { var/lhs = ##a; var/rhs = ##b; if (lhs != rhs) { return Fail("Expected [isnull(lhs) ? "null" : lhs] to equal [isnull(rhs) ? "null" : rhs].[message ? " [message]" : ""]", __FILE__, __LINE__); } } while (FALSE)
/proc/check()
    TEST_ASSERT_EQUAL(expected, output, "TGUI_CREATE_MESSAGE didn't round trip properly")
"#,
        ),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output
        .text
        .contains("TGUI_CREATE_MESSAGE didn't round trip properly"));
}

#[test]
fn map_includes_follow_active_conditional_branches() {
    let files = fixture(&[("game.dme", "#define ENABLE 1\n#if ENABLE\n#include \"active.dmm\"\n#else\n#include \"dormant.dmm\"\n#endif\n")]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert!(output.diagnostics.is_empty());
    assert_eq!(output.map_includes, [PathBuf::from("active.dmm")]);
    assert!(output.text.is_empty());
}

#[test]
fn macro_dependency_closure_preserves_unrelated_files_and_tracks_undefined_names() {
    let mut files = fixture(&[
        (
            "game.dme",
            "#include \"defs.dm\"\n#include \"a.dm\"\n#include \"b.dm\"\n",
        ),
        (
            "defs.dm",
            "#define ALIAS VALUE\n#define VALUE 7\n#define OTHER 1\n",
        ),
        ("a.dm", "/proc/a()\n return ALIAS + FUTURE\n"),
        ("b.dm", "/proc/b()\n return OTHER\n"),
    ]);
    let mut cache = PreprocessCache::default();
    preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    files.0.insert(
        PathBuf::from("defs.dm"),
        "#define ALIAS VALUE\n#define VALUE 8\n#define OTHER 1\n".into(),
    );
    let changed =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(
        changed,
        preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new())
    );
    assert_eq!(
        cache.hits, 1,
        "unrelated OTHER consumer must reuse its expansion"
    );
    files.0.insert(
        PathBuf::from("defs.dm"),
        "#define ALIAS VALUE\n#define VALUE 8\n#define OTHER 1\n#define FUTURE 3\n".into(),
    );
    let changed =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(
        changed,
        preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new())
    );
    assert!(changed.text.contains("8 + 3"));
}

#[test]
fn dependency_fingerprint_supports_unicode_and_falls_back_for_spaced_paste() {
    let definition = Macro {
        parameters: None,
        variadic: false,
        replacement: "7".into(),
    };
    let macros = BTreeMap::from([("\u{00c5}NSWER".into(), definition)]);
    assert!(macro_dependencies("return \u{00c5}NSWER", &macros)
        .unwrap()
        .contains(&"\u{00c5}NSWER".to_string()));
    assert!(macro_dependencies("#define CAT(a,b) a # # b", &macros).is_none());
    let (_, pasted) = parse_define("PASTE(a,b) a##b").unwrap();
    let macros = BTreeMap::from([("PASTE".into(), pasted)]);
    assert!(macro_dependencies("PASTE(A,B)", &macros).is_none());
}

#[test]
fn nested_cache_replays_child_origins_macro_effects_and_rejects_child_edit() {
    let mut files = fixture(&[
        ("game.dme", "#include \"parent.dm\"\n#include \"tail.dm\"\n"),
        (
            "parent.dm",
            "#include \"child.dm\"\n/proc/parent()\n return CHILD\n",
        ),
        (
            "child.dm",
            "#define CHILD 7\n/proc/child()\n return CHILD\n",
        ),
        ("tail.dm", "/proc/tail()\n return CHILD\n"),
    ]);
    let mut cache = PreprocessCache::default();
    let first =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    let repeated =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(first, repeated);
    assert_eq!(cache.hits, 2, "parent subtree and tail replay once each");
    files.0.insert(
        PathBuf::from("child.dm"),
        "#define CHILD 9\n/proc/child()\n return CHILD\n".into(),
    );
    let changed =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(
        changed,
        preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new())
    );
    assert!(changed.text.contains("return 9"));
}

#[test]
fn changed_leaf_reuses_unchanged_include_expansions() {
    let mut files = fixture(&[
        (
            "game.dme",
            "#include \"a.dm\"\n#include \"b.dm\"\n#include \"c.dm\"\n",
        ),
        ("a.dm", "#define VALUE 7\n/obj/a\n  x = VALUE\n"),
        ("b.dm", "/obj/b\n  x = VALUE\n"),
        ("c.dm", "/obj/c\n  x = VALUE\n"),
    ]);
    let mut cache = PreprocessCache::default();
    let first =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(cache.misses, 3);
    files
        .0
        .insert(PathBuf::from("b.dm"), "/obj/b\n  x = VALUE + 1\n".into());
    let changed =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    let cold = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert_ne!(first.text, changed.text);
    assert_eq!(changed, cold);
    assert_eq!(cache.hits, 2);
    assert_eq!(cache.misses, 4);
}

#[test]
fn changed_macro_invalidates_later_include_expansions() {
    let mut files = fixture(&[
        ("game.dme", "#include \"a.dm\"\n#include \"b.dm\"\n"),
        ("a.dm", "#define VALUE 7\n"),
        ("b.dm", "/obj/b\n  x = VALUE\n"),
    ]);
    let mut cache = PreprocessCache::default();
    preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    files
        .0
        .insert(PathBuf::from("a.dm"), "#define VALUE 8\n".into());
    let changed =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert!(changed.text.contains("x = 8"));
    assert_eq!(cache.hits, 0);
    assert_eq!(
        changed,
        preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new())
    );
}

#[test]
fn cached_macro_delta_replays_define_and_undef() {
    let files = fixture(&[
        (
            "game.dme",
            "#define OLD 1\n#include \"a.dm\"\n#include \"b.dm\"\n",
        ),
        ("a.dm", "#undef OLD\n#define NEW 7\n#define NEW 8\n"),
        ("b.dm", "/obj/b\n  x = NEW\n"),
    ]);
    let mut cache = PreprocessCache::default();
    let first =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    let second =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(first, second);
    assert_eq!(cache.hits, 2);
    assert!(!second.final_macros.contains_key("OLD"));
    assert_eq!(second.final_macros["NEW"].replacement, "8");
    assert!(second.text.contains("x = 8"));
    assert_eq!(cache.entries[Path::new("a.dm")][0].macro_changes.len(), 2);
    let path = std::env::temp_dir().join(format!(
        "dm-preprocess-delta-test-{}-{}.json",
        std::process::id(),
        CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    cache.save(&path).unwrap();
    let mut restored = PreprocessCache::load(&path);
    let from_disk = preprocess_project_cached(
        Path::new("game.dme"),
        &files,
        &BTreeMap::new(),
        &mut restored,
    );
    assert_eq!(from_disk, first);
    assert_eq!(restored.hits, 2);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn directive_inside_open_macro_call_is_applied_in_order() {
    for (define, expect_b) in [("#define ON
", true), ("", false)] {
        let text = format!(
            "#define EVENT(kind, payload) emit(kind, payload)
{define}/proc/test()
	EVENT(1, list(
		\"a\" = 1,
#ifdef ON
		\"b\" = 2,
#endif
	))
	return 1
"
        );
        let files = fixture(&[("game.dme", "#include \"leaf.dm\"
"), ("leaf.dm", text.as_str())]);
        let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
        assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
        assert!(output.text.contains("emit(1, list("), "{}", output.text);
        assert_eq!(output.text.contains("\"b\" = 2"), expect_b, "{}", output.text);
        assert!(output.text.contains("return 1"), "{}", output.text);
    }
}

#[test]
fn open_macro_call_never_closed_still_reports_per_line() {
    let files = fixture(&[
        ("game.dme", "#include \"leaf.dm\"
"),
        ("leaf.dm", "#define EVENT(a) emit(a)
/proc/test()
	EVENT(1,
#ifdef NOPE
#endif
	return 2
"),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert_eq!(output.diagnostics.len(), 1, "{:?}", output.diagnostics);
    assert!(output.diagnostics[0].message.contains("missing )"));
    assert!(output.text.contains("return 2"), "{}", output.text);
}
