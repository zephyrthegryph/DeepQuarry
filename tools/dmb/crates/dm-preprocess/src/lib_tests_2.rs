#[test]
fn source_digest_rejects_same_length_edits_and_obsolete_or_corrupt_cache() {
    let first_files = fixture(&[
        ("game.dme", "#include \"a.dm\"\n"),
        ("a.dm", "/obj/a\n  x = 7\n"),
    ]);
    let second_files = fixture(&[
        ("game.dme", "#include \"a.dm\"\n"),
        ("a.dm", "/obj/a\n  x = 8\n"),
    ]);
    let mut cache = PreprocessCache::default();
    let first = preprocess_project_cached(
        Path::new("game.dme"),
        &first_files,
        &BTreeMap::new(),
        &mut cache,
    );
    let path = std::env::temp_dir().join(format!(
        "dm-source-digest-{}-{}.json",
        std::process::id(),
        CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    cache.save(&path).unwrap();
    let bytes = fs::read(&path).unwrap();
    let mut restored = PreprocessCache::load(&path);
    let second = preprocess_project_cached(
        Path::new("game.dme"),
        &second_files,
        &BTreeMap::new(),
        &mut restored,
    );
    assert_eq!(restored.hits, 0);
    assert_eq!(restored.misses, 1);
    assert_ne!(first.text, second.text);
    assert!(second.text.contains("x = 8"));
    let mut file: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    file["version"] = serde_json::json!(7);
    fs::write(&path, serde_json::to_vec(&file).unwrap()).unwrap();
    assert!(PreprocessCache::load(&path).entries.is_empty());
    file["version"] = serde_json::json!(CACHE_FORMAT_VERSION);
    file["compiler_fingerprint"] = serde_json::json!("obsolete");
    fs::write(&path, serde_json::to_vec(&file).unwrap()).unwrap();
    assert!(PreprocessCache::load(&path).entries.is_empty());
    fs::write(&path, &bytes[..bytes.len() / 2]).unwrap();
    assert!(PreprocessCache::load(&path).entries.is_empty());
    fs::remove_file(path).unwrap();
}

#[test]
fn sharded_cache_is_lazy_rewrites_only_changed_chunks_and_checks_corruption() {
    let mut files = fixture(&[
        ("game.dme", "#include \"a.dm\"\n#include \"b.dm\"\n"),
        ("a.dm", "/proc/a()\n return 1\n"),
        ("b.dm", "/proc/b()\n return 2\n"),
    ]);
    let directory = std::env::temp_dir().join(format!(
        "dm-shards-{}-{}",
        std::process::id(),
        CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    fs::create_dir_all(&directory).unwrap();
    let path = directory.join("cache.json");
    let mut cache = PreprocessCache::default();
    preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    cache.save_incremental(&path).unwrap();
    let first_index: CacheIndex =
        serde_json::from_slice(&fs::read(path.with_extension("index.json")).unwrap()).unwrap();
    let b_key = first_index.entries[Path::new("b.dm")][0].clone();
    let b_path = path.with_extension("parts").join(&b_key);
    let b_time = fs::metadata(&b_path).unwrap().modified().unwrap();
    let mut restored = PreprocessCache::load_incremental(&path);
    assert!(restored.entries.is_empty(), "load decodes only the index");
    files
        .0
        .insert(PathBuf::from("a.dm"), "/proc/a()\n return 3\n".into());
    let changed = preprocess_project_cached(
        Path::new("game.dme"),
        &files,
        &BTreeMap::new(),
        &mut restored,
    );
    assert_eq!(
        changed,
        preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new())
    );
    assert_eq!(restored.hits, 1);
    restored.save_incremental(&path).unwrap();
    assert_eq!(fs::metadata(&b_path).unwrap().modified().unwrap(), b_time);
    fs::write(&b_path, b"corrupt").unwrap();
    let mut restarted = PreprocessCache::load_incremental(&path);
    let again = preprocess_project_cached(
        Path::new("game.dme"),
        &files,
        &BTreeMap::new(),
        &mut restarted,
    );
    assert_eq!(again, changed);
    assert_eq!(restarted.misses, 1);
    restarted.save_incremental(&path).unwrap();
    let mut index: CacheIndex =
        serde_json::from_slice(&fs::read(path.with_extension("index.json")).unwrap()).unwrap();
    let old = path
        .with_extension("parts")
        .join(&index.entries[Path::new("b.dm")][0]);
    let mut chunk: serde_json::Value = serde_json::from_slice(&fs::read(old).unwrap()).unwrap();
    chunk["unit_digests"][0] = serde_json::to_value([0u8; 32]).unwrap();
    let bytes = serde_json::to_vec(&chunk).unwrap();
    let changed_key = format!("{:x}", Sha256::digest(&bytes));
    fs::write(path.with_extension("parts").join(&changed_key), bytes).unwrap();
    index.entries.get_mut(Path::new("b.dm")).unwrap()[0] = changed_key;
    fs::write(
        path.with_extension("index.json"),
        serde_json::to_vec(&index).unwrap(),
    )
    .unwrap();
    let mut mismatched_digest = PreprocessCache::load_incremental(&path);
    let exact = preprocess_project_cached(
        Path::new("game.dme"),
        &files,
        &BTreeMap::new(),
        &mut mismatched_digest,
    );
    assert_eq!(exact, changed);
    assert_eq!(
        mismatched_digest.misses, 1,
        "a checksum-valid chunk with incorrect semantic content identity must be rejected"
    );
    fs::remove_dir_all(directory).unwrap();
}

#[test]
fn persisted_cache_replays_exact_leaf_expansion() {
    let files = fixture(&[
        ("game.dme", "#define VALUE 7\n#include \"a.dm\"\n"),
        ("a.dm", "/obj/a\n  x = VALUE\n"),
    ]);
    let mut cache = PreprocessCache::default();
    let original =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    let dir = std::env::temp_dir().join(format!("dm-preprocess-cache-test-{}", std::process::id()));
    let path = dir.join("cache.json");
    cache.save(&path).unwrap();
    let mut restored = PreprocessCache::load(&path);
    let replayed = preprocess_project_cached(
        Path::new("game.dme"),
        &files,
        &BTreeMap::new(),
        &mut restored,
    );
    assert_eq!(restored.hits, 1);
    assert_eq!(original, replayed);
    std::fs::remove_file(path).unwrap();
    std::fs::remove_dir(dir).unwrap();
}

#[test]
fn file_dirs_keep_active_order_through_leaf_disk_replay() {
    let files = fixture(&[
            ("game.dme", "#define FILE_DIR icons/gen\n#include \"leaf.dm\"\n#define FILE_DIR icons\n#if 0\n#define FILE_DIR ignored\n#endif\n"),
            ("leaf.dm", "#undef FILE_DIR\n#define FILE_DIR sound\n/obj/test\n"),
        ]);
    let mut cache = PreprocessCache::default();
    let original =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(
        original.file_dirs,
        [PathBuf::from("sound"), PathBuf::from("icons")]
    );
    let path = std::env::temp_dir().join(format!(
        "dm-file-dir-cache-{}-{}.json",
        std::process::id(),
        CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    cache.save(&path).unwrap();
    let mut replay = PreprocessCache::load(&path);
    let restored =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut replay);
    assert_eq!(replay.hits, 1);
    assert_eq!(restored.file_dirs, original.file_dirs);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn undef_file_dir_restores_previous_definition() {
    let files = fixture(&[("game.dme", "#define FILE_DIR first\n#define FILE_DIR second\n#undef FILE_DIR\n#ifdef FILE_DIR\n#include \"leaf.dm\"\n#endif\n"), ("leaf.dm", "/obj/active\n")]);
    let output = preprocess_project(Path::new("game.dme"), &files, &BTreeMap::new());
    assert_eq!(output.file_dirs, [PathBuf::from("first")]);
    assert_eq!(output.final_macros["FILE_DIR"].replacement, "first");
    assert!(output.text.contains("/obj/active"));
}

#[test]
fn cached_undef_file_dir_restores_previous_macro() {
    let files = fixture(&[
        (
            "game.dme",
            "#define FILE_DIR first\n#define FILE_DIR second\n#include \"leaf.dm\"\n",
        ),
        ("leaf.dm", "#undef FILE_DIR\n/obj/active\n"),
    ]);
    let mut cache = PreprocessCache::default();
    let first =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    let second =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(first, second);
    assert_eq!(second.final_macros["FILE_DIR"].replacement, "first");
    assert_eq!(second.file_dirs, [PathBuf::from("first")]);
    assert_eq!(cache.hits, 1);
}

#[test]
fn disk_cache_compacts_repeated_origin_paths() {
    let directory = "very_long_worktree_name_".repeat(8);
    let project = format!("{directory}/game.dme");
    let leaf = format!("{directory}/leaf.dm");
    let source = (0..1_000)
        .map(|index| format!("value = {index}\n"))
        .collect::<String>();
    let files = fixture(&[(&project, "#include \"leaf.dm\"\n"), (&leaf, &source)]);
    let mut cache = PreprocessCache::default();
    let original =
        preprocess_project_cached(Path::new(&project), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(original.origins.len(), 1_000);
    let path = std::env::temp_dir().join(format!(
        "dm-compact-origins-{}-{}.json",
        std::process::id(),
        CACHE_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    cache.save(&path).unwrap();
    assert!(std::fs::metadata(&path).unwrap().len() < 100_000);
    let mut restored = PreprocessCache::load(&path);
    let replayed =
        preprocess_project_cached(Path::new(&project), &files, &BTreeMap::new(), &mut restored);
    assert_eq!(restored.hits, 1);
    assert_eq!(replayed, original);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn include_order_and_macro_environment() {
    let fs = fixture(&[("game.dme", "#define NAME one\n#include \"a.dm\"\n#undef NAME\n#define NAME two\n#include \"a.dm\"\n"), ("a.dm", "/obj\n  name = NAME\n")]);
    let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
    assert_eq!(output.text, "/obj\n  name = one\n/obj\n  name = two\n");
    assert_eq!(output.origins.len(), 4);
    assert_eq!(
        output
            .units
            .iter()
            .filter(|u| u.path == Path::new("a.dm"))
            .count(),
        2
    );
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
}

#[test]
fn conditional_and_function_macro() {
    let fs = fixture(&[("game.dme", "#define FLAG 1\n#define SUM(a,b) (a+b)\n#if defined(FLAG)\n#include \"a.dm\"\n#else\n#include \"missing.dm\"\n#endif\n"), ("a.dm", "var/x = SUM(2, 3)\n")]);
    let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
    assert_eq!(output.text, "var/x = (2+3)\n");
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
}

#[test]
fn recursive_macro_names_are_disabled_without_copying_the_table() {
    let mut macros = BTreeMap::new();
    for directive in ["SELF SELF", "A B", "B A", "NEST(x) (x+x)"] {
        let (name, definition) = parse_define(directive).unwrap();
        macros.insert(name, definition);
    }
    let location = ExpandLocation {
        file_name: "probe.dm",
        line: 1,
    };
    assert_eq!(expand("SELF", &macros, 0, location).unwrap(), "SELF");
    assert_eq!(expand("A", &macros, 0, location).unwrap(), "A");
    assert_eq!(expand("NEST(2)", &macros, 0, location).unwrap(), "(2+2)");
    assert_eq!(
        expand("NEST(NEST(2))", &macros, 0, location).unwrap(),
        "((2+2)+(2+2))"
    );
}

#[test]
fn infinity_literal_and_raw_string_survive_macro_expansion() {
    let mut macros = BTreeMap::new();
    let (name, definition) = parse_define("INFINITY (1.#INF)").unwrap();
    macros.insert(name, definition);
    let (name, definition) = parse_define("VALUE 42").unwrap();
    macros.insert(name, definition);
    let location = ExpandLocation {
        file_name: "probe.dm",
        line: 1,
    };
    assert_eq!(
        expand("INFINITY", &macros, 0, location).unwrap(),
        "(1.#INF)"
    );
    assert_eq!(
        expand("@\"[VALUE]\\n\"", &macros, 0, location).unwrap(),
        "@\"[VALUE]\\n\""
    );
    assert!(expand("foo #BAD", &macros, 0, location).is_err());
}

#[test]
fn cycle_is_diagnosed_without_recursion() {
    let fs = fixture(&[
        ("game.dme", "#include \"a.dm\"\n"),
        ("a.dm", "#include \"a.dm\"\n"),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
    assert!(output
        .diagnostics
        .iter()
        .any(|d| d.message.contains("include cycle")));
}

#[test]
fn unsupported_condition_is_not_silent() {
    let fs = fixture(&[(
        "game.dme",
        "#if foo ? bar : baz\n#include \"a.dm\"\n#endif\n",
    )]);
    let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
    assert!(output
        .diagnostics
        .iter()
        .any(|d| d.message.contains("unsupported #if")));
}

#[test]
fn continued_macro_and_condition_precedence() {
    let fs = fixture(&[("game.dme", "#define FLAG 0x10\n#define ADD(a,b) ((a) + \\\n    (b))\n#if defined FLAG && ((FLAG >> 2) == 4) || 0\n#include \"a.dm\"\n#endif\n"),
            ("a.dm", "var/x = ADD(2, 3)\n")]);
    let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
    assert_eq!(output.text, "var/x = ((2) +     (3))\n");
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert_eq!(output.origins[0].source_line, 1);
}

#[test]
fn continued_source_line_origin_is_first_physical_line() {
    let fs = fixture(&[
        ("game.dme", "#include \"a.dm\"\n"),
        ("a.dm", "var/x = 1 \\\n + 2\nvar/y = 3\n"),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
    assert_eq!(output.origins[0].source_line, 1);
    assert_eq!(output.origins[1].source_line, 3);
}

#[test]
fn deepquarry_token_paste_and_variadic_macros() {
    let fs = fixture(&[("game.dme", "#define PROC_REF(X) (nameof(.proc/##X))\n#define ICON(I, state, rest...) new /datum/universal_icon(I, state, ##rest)\n#include \"a.dm\"\n"),
            ("a.dm", "var/a = PROC_REF(test)\nvar/b = ICON('a.dmi', \"on\")\nvar/c = ICON('a.dmi', \"on\", 3, 4)\n")]);
    let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert_eq!(output.text, "var/a = (nameof(.proc/test))\nvar/b = new /datum/universal_icon('a.dmi', \"on\")\nvar/c = new /datum/universal_icon('a.dmi', \"on\",3,4)\n");
}

#[test]
fn block_string_keeps_multiline_text_and_interpolation() {
    let fs = fixture(&[
        ("game.dme", "#define VALUE 9\n#include \"a.dm\"\n"),
        (
            "a.dm",
            "var/output = {\"First [VALUE]\nSecond [foo(\"inside\")]\"}\nvar/after = VALUE\n",
        ),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert!(output.text.contains("First [9]\nSecond [foo(\"inside\")]"));
    assert!(output.text.ends_with("var/after = 9\n"));
    assert_eq!(output.origins.len(), 3);
    assert_eq!(output.origins[1].source_line, 2);
    assert_eq!(output.origins[2].source_line, 3);
}

#[test]
fn diagnostic_kinds_distinguish_io_macros_and_conditions() {
    let fs = fixture(&[(
        "game.dme",
        "#include \"missing.dm\"\n#define BAD(x..., y) x\n#if x ? y : z\n#endif\n",
    )]);
    let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
    assert!(output
        .diagnostics
        .iter()
        .any(|d| d.kind == DiagnosticKind::Io));
    assert!(output
        .diagnostics
        .iter()
        .any(|d| d.kind == DiagnosticKind::Conditional));
    assert!(output
        .diagnostics
        .iter()
        .any(|d| d.kind == DiagnosticKind::Macro));
}

#[test]
fn stringify_arguments_and_expand_inside_interpolation() {
    let fs = fixture(&[
        (
            "game.dme",
            "#define NAMEOF(X) (#X || ##X)\n#define VALUE 7\n#include \"a.dm\"\n",
        ),
        (
            "a.dm",
            "var/a = NAMEOF(foo)\nvar/b = \"Value [VALUE] and [NAMEOF(bar)]\"\n",
        ),
    ]);
    let output = preprocess_project(Path::new("game.dme"), &fs, &BTreeMap::new());
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    assert_eq!(
        output.text,
        "var/a = (\"foo\" ||foo)\nvar/b = \"Value [7] and [(\"bar\" ||bar)]\"\n"
    );
}
#[test]
fn cached_dm_subtree_preserves_deferred_manifest_startup() {
    let files = fixture(&[
        ("game.dme", "#include \"parent.dm\"\n"),
        (
            "parent.dm",
            "#include \"startup.dme\"\n/proc/body()\n return 1\n",
        ),
        (
            "startup.dme",
            "/world/proc/_()\n var/static/_ = world.Genesis()\n",
        ),
    ]);
    let mut cache = PreprocessCache::default();
    let first =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    let repeated =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(first, repeated);
    assert!(repeated.text.contains("world.Genesis()"));
    assert_eq!(cache.hits, 1);
}

#[test]
fn included_dme_preserves_active_startup_dm_and_cache_replay() {
    let files = fixture(&[
            ("game.dme", "#define ENABLED 1\n#include \"startup.dme\"\n"),
            ("startup.dme", "#if ENABLED\n/world/proc/_()\n    var/static/_ = world.Genesis()\n#endif\n#if 0\n/proc/inactive()\n#endif\n"),
        ]);
    let mut cache = PreprocessCache::default();
    let first =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert!(first.diagnostics.is_empty());
    assert_eq!(
        first.text,
        "/world/proc/_()\n    var/static/_ = world.Genesis()\n"
    );
    let replay =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(first, replay);
    assert!(replay
        .origins
        .iter()
        .all(|origin| origin.path.as_path() == Path::new("startup.dme")));
}

#[test]
fn manifest_dm_is_deferred_but_macros_expand_at_encounter() {
    let files = fixture(&[
            ("game.dme", "#define VALUE 2\n#include \"startup.dme\"\n#include \"second.dme\"\n#include \"body.dm\"\n"),
            ("startup.dme", "/world/proc/_()\n    var/static/late = marker(VALUE)\n"),
            ("second.dme", "/proc/second()\n    var/static/second = marker(3)\n"),
            ("body.dm", "#define VALUE 4\n/proc/early()\n    var/static/early = marker(1)\n"),
        ]);
    let mut cache = PreprocessCache::default();
    let output =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert!(output.diagnostics.is_empty());
    assert_eq!(output.text, "/proc/early()\n    var/static/early = marker(1)\n/world/proc/_()\n    var/static/late = marker(2)\n/proc/second()\n    var/static/second = marker(3)\n");
    assert_eq!(
        output
            .origins
            .iter()
            .map(|origin| origin.output_line)
            .collect::<Vec<_>>(),
        (1..=6).collect::<Vec<_>>()
    );
    assert_eq!(output.origins[2].path.as_path(), Path::new("startup.dme"));
    let replay =
        preprocess_project_cached(Path::new("game.dme"), &files, &BTreeMap::new(), &mut cache);
    assert_eq!(output, replay);
}
