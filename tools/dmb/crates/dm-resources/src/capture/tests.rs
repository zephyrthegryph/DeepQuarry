use super::*;
#[test]
fn discovered_capture_preserves_search_reads_order_payloads_and_configuration() {
    let files = [
        ("game/late/map.txt", b"map" as &[u8]),
        ("game/source.txt", b"source" as &[u8]),
        ("game/extra.txt", b"extra" as &[u8]),
        ("game/extra2.txt", b"extra2" as &[u8]),
    ];
    let ordinary = memory(&files);
    let reused = memory(&files);
    let source = expanded("/proc/p()\n    return 'source.txt'\n");
    let plan = plan();
    let policy = policy();
    let extras = [
        LiteralRequest {
            path: "map.txt".into(),
            span: Span::new(1, 9),
        },
        LiteralRequest {
            path: "source.txt".into(),
            span: Span::new(10, 22),
        },
    ];
    let additional = [
        ResourceRequest {
            archive_name: "extra.txt".into(),
            disk_path: PathBuf::from("game/extra.txt"),
        },
        ResourceRequest {
            archive_name: "extra2.txt".into(),
            disk_path: PathBuf::from("game/extra2.txt"),
        },
    ];
    let config = || CaptureConfig {
        policy: &policy,
        encoded: &[],
        additional: &additional,
    };
    let before =
        capture_expanded_with_literals(&plan, &source, config(), &extras, &ordinary).unwrap();
    let demand = discover_demand(&plan, &source, &extras, &additional).unwrap();
    let after = capture_discovered(demand, config(), &reused).unwrap();
    assert_eq!(*ordinary.reads.borrow(), *reused.reads.borrow());
    assert_eq!(before.context.bytes(), after.context.bytes());
    assert_eq!(before.lookups, after.lookups);
    assert_eq!(before.observations, after.observations);
    assert_eq!(before.literals, after.literals);
    assert_eq!(before.source_literal_count, after.source_literal_count);
    assert_eq!(before.resources.fingerprint, after.resources.fingerprint);
    assert_eq!(
        before
            .resources
            .inputs
            .iter()
            .map(|v| (
                &v.archive_name,
                &v.disk_path,
                v.named.asset_bytes().unwrap()
            ))
            .collect::<Vec<_>>(),
        after
            .resources
            .inputs
            .iter()
            .map(|v| (
                &v.archive_name,
                &v.disk_path,
                v.named.asset_bytes().unwrap()
            ))
            .collect::<Vec<_>>()
    );
    let mut demand = discover_demand(&plan, &source, &extras, &additional).unwrap();
    demand.additional.reverse();
    let untouched = memory(&files);
    assert!(capture_discovered(demand, config(), &untouched).is_err());
    assert!(untouched.reads.borrow().is_empty());
    let mut demand = discover_demand(&plan, &source, &extras, &additional).unwrap();
    demand.context = CapturedSearchContext::new(b"unrelated context".as_slice());
    assert!(capture_discovered(demand, config(), &untouched).is_err());
    assert!(untouched.reads.borrow().is_empty());
}
use std::cell::RefCell;
struct Memory {
    files: HashMap<PathBuf, Arc<[u8]>>,
    reads: RefCell<Vec<PathBuf>>,
}
impl CaptureProvider for Memory {
    fn read_candidate(&self, path: &Path) -> io::Result<Option<Arc<[u8]>>> {
        self.reads.borrow_mut().push(path.to_owned());
        Ok(self.files.get(path).cloned())
    }
}
fn memory(files: &[(&str, &[u8])]) -> Memory {
    Memory {
        files: files
            .iter()
            .map(|(name, bytes)| (PathBuf::from(name), Arc::from(*bytes)))
            .collect(),
        reads: RefCell::new(vec![]),
    }
}
fn plan() -> DirectivePlan {
    DirectivePlan {
        project_dir: PathBuf::from("game"),
        file_dirs: vec![PathBuf::from("early"), PathBuf::from("late")],
        ..Default::default()
    }
}
fn expanded(source: &str) -> ExpandedRegions {
    ExpandedRegions {
        text: source.into(),
        ..Default::default()
    }
}
fn policy() -> CapturePolicy {
    CapturePolicy {
        certified_raw_extensions: BTreeSet::from(["txt".into()]),
    }
}
#[test]
fn extra_map_literals_share_the_qualified_search_and_dedup_ledger() {
    let provider = memory(&[
        ("game/late/map.txt", b"map"),
        ("game/source.txt", b"source"),
    ]);
    let raw = policy();
    let extra = [
        LiteralRequest {
            path: "map.txt".into(),
            span: Span::new(8, 17),
        },
        LiteralRequest {
            path: "source.txt".into(),
            span: Span::new(18, 30),
        },
    ];
    let output = capture_expanded_with_literals(
        &plan(),
        &expanded("/proc/p()\n    return 'source.txt'\n"),
        CaptureConfig {
            policy: &raw,
            encoded: &[],
            additional: &[],
        },
        &extra,
        &provider,
    )
    .unwrap();
    assert_eq!(output.lookups.len(), 2);
    assert_eq!(output.resources.inputs.len(), 2);
    assert_eq!(output.resources.inputs[0].archive_name, "source.txt");
    assert_eq!(
        output.resources.inputs[1].disk_path,
        PathBuf::from("game/late/map.txt")
    );
    output.require_complete().unwrap();
}
#[test]
fn grammar_discovers_only_resource_tokens_and_parsed_interpolation() {
    let source="/proc/p()\n    // 'comment.txt'\n    var/a = @\"['raw.txt']\"\n    var/b = \"plain 'text.txt' [icon('embedded.txt')] [\"nested [file('deep.txt')]\"]\"\n    return 'direct.txt'\n";
    let found = discover_literals(source).unwrap();
    assert_eq!(
        found
            .iter()
            .map(|literal| literal.path.as_str())
            .collect::<Vec<_>>(),
        ["embedded.txt", "deep.txt", "direct.txt"]
    );
    for literal in &found {
        assert_eq!(&source[literal.span.range()], format!("'{}'", literal.path));
    }
}
#[test]
fn interpolation_resource_discovery_is_independent_of_expression_grammar() {
    let source = "/proc/p()\n    return \"[pick(1;'asset.txt',1;null)] [\"nested [pick(1;'deep.txt',1;null)]\"] plain 'ignored.txt'\"\n";
    let found = discover_literals(source).unwrap();
    assert_eq!(
        found
            .iter()
            .map(|literal| literal.path.as_str())
            .collect::<Vec<_>>(),
        ["asset.txt", "deep.txt"]
    );
    for literal in found {
        assert_eq!(&source[literal.span.range()], format!("'{}'", literal.path));
    }
    assert!(discover_literals("\"unterminated [file('x.txt')\"").is_err());
}
#[test]
fn terminal_roots_use_project_then_reverse_stack_and_record_negatives() {
    let provider = memory(&[
        ("game/late/found.txt", b"late"),
        ("game/early/found.txt", b"early"),
        ("game/direct.txt", b"direct"),
        ("game/late/direct.txt", b"shadowed"),
    ]);
    let source = expanded(
        "/proc/p()\n    return list('found.txt','direct.txt','missing.txt','found.txt')\n",
    );
    let policy = policy();
    let captured = capture_expanded(
        &plan(),
        &source,
        CaptureConfig {
            policy: &policy,
            encoded: &[],
            additional: &[],
        },
        &provider,
    )
    .unwrap();
    assert_eq!(
        captured
            .resources
            .inputs
            .iter()
            .map(|input| input.archive_name.as_str())
            .collect::<Vec<_>>(),
        ["found.txt", "direct.txt"]
    );
    assert_eq!(
        captured.resources.inputs[0].named.asset_bytes().unwrap(),
        b"late"
    );
    assert_eq!(captured.lookups.len(), 3);
    assert_eq!(
        captured.lookups[2].outcome,
        CapturedResourceOutcome::Missing
    );
    assert_eq!(
        provider.reads.borrow().as_slice(),
        [
            PathBuf::from("game/found.txt"),
            PathBuf::from("game/late/found.txt"),
            PathBuf::from("game/direct.txt"),
            PathBuf::from("game/missing.txt"),
            PathBuf::from("game/late/missing.txt"),
            PathBuf::from("game/early/missing.txt")
        ]
    );
    assert!(matches!(
        captured.observations[0].outcome,
        CandidateOutcome::Missing
    ));
}
#[test]
fn unknown_transformation_is_unsupported_not_raw_or_missing() {
    let provider = memory(&[("game/picture.png", b"not silently raw")]);
    let policy = CapturePolicy::default();
    let captured = capture_expanded(
        &plan(),
        &expanded("/proc/p()\n    return 'picture.png'\n"),
        CaptureConfig {
            policy: &policy,
            encoded: &[],
            additional: &[],
        },
        &provider,
    )
    .unwrap();
    assert_eq!(
        captured.lookups[0].outcome,
        CapturedResourceOutcome::Unsupported
    );
    assert!(captured.resources.inputs.is_empty());
    assert!(captured.require_complete().is_err());
}
#[test]
fn encoded_record_requires_current_source_digest_and_retains_encoded_bytes() {
    let provider = memory(&[("game/picture.png", b"source")]);
    let named = byond_dmb::rsc::NamedResource::from_data(
        6,
        b"picture.png".to_vec(),
        b"encoded".to_vec(),
        0,
        0,
    )
    .unwrap();
    let mut encoded = [EncodedResourceInput {
        input: ResourceInput {
            archive_name: "picture.png".into(),
            disk_path: PathBuf::from("game/picture.png"),
            content_digest: Sha256::digest(b"encoded").into(),
            named: named.into(),
        },
        source_digest: Sha256::digest(b"source").into(),
    }];
    let policy = CapturePolicy::default();
    let source = expanded("/proc/p()\n    return 'picture.png'\n");
    let result = capture_expanded(
        &plan(),
        &source,
        CaptureConfig {
            policy: &policy,
            encoded: &encoded,
            additional: &[],
        },
        &provider,
    )
    .unwrap();
    assert_eq!(
        result.resources.inputs[0].named.asset_bytes().unwrap(),
        b"encoded"
    );
    encoded[0].source_digest = [0; 32];
    assert!(matches!(
        capture_expanded(
            &plan(),
            &source,
            CaptureConfig {
                policy: &policy,
                encoded: &encoded,
                additional: &[]
            },
            &provider
        ),
        Err(CaptureError::Invalid(_))
    ));
    encoded[0].source_digest = Sha256::digest(b"source").into();
    encoded[0].input.named.id ^= 1;
    assert!(matches!(
        capture_expanded(
            &plan(),
            &source,
            CaptureConfig {
                policy: &policy,
                encoded: &encoded,
                additional: &[],
            },
            &provider
        ),
        Err(CaptureError::Invalid(_))
    ));
}
#[test]
fn candidate_io_failure_never_becomes_a_negative_lookup() {
    struct Denied;
    impl CaptureProvider for Denied {
        fn read_candidate(&self, _: &Path) -> io::Result<Option<Arc<[u8]>>> {
            Err(io::Error::new(io::ErrorKind::PermissionDenied, "denied"))
        }
    }
    let policy = policy();
    assert!(
        matches!(capture_expanded(&plan(),&expanded("/proc/p()\n    return 'x.txt'\n"),CaptureConfig {policy:&policy,encoded:&[],additional:&[]},&Denied),Err(CaptureError::Io {source,..}) if source.kind()==io::ErrorKind::PermissionDenied)
    );
}
#[path = "tests/capture_digest_tests.rs"]
mod digest_reuse;
#[path = "tests/capture_literal_visit_tests.rs"]
mod literal_visit;

#[test]
fn raw_capture_retains_the_provider_payload_allocation() {
    struct Shared(Arc<[u8]>);
    impl CaptureProvider for Shared {
        fn read_candidate(&self, path: &Path) -> io::Result<Option<Arc<[u8]>>> {
            Ok((path == Path::new("game/a.txt")).then(|| Arc::clone(&self.0)))
        }
    }
    let provider = Shared(Arc::from(&b"captured payload"[..]));
    let captured = capture_expanded(
        &plan(),
        &expanded("/proc/p()\n    return 'a.txt'\n"),
        CaptureConfig {
            policy: &policy(),
            encoded: &[],
            additional: &[],
        },
        &provider,
    )
    .unwrap();
    assert_eq!(captured.resources.inputs.len(), 1);
    assert!(Arc::ptr_eq(
        &provider.0,
        captured.resources.inputs[0].named.shared_data()
    ));
}
