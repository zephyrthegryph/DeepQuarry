use super::*;
#[test]
fn issued_candidate_view_matches_ordered_capture_and_stops_at_winner() {
    let plan = DirectivePlan { project_dir: "game".into(), file_dirs: vec!["early".into(), "late".into()], ..Default::default() };
    let expanded = ExpandedRegions { text: "/proc/p()\n    return 'asset.txt'\n".into(), ..Default::default() };
    let demand = discover_demand(&plan, &expanded, &[], &[]).unwrap();
    let literal = &demand.literals[0];
    let mut paths = Vec::new();
    demand.visit_candidates(literal, |path| { paths.push(path.to_owned()); true }).unwrap();
    assert_eq!(paths, vec![PathBuf::from("game/asset.txt"), PathBuf::from("game/late/asset.txt"), PathBuf::from("game/early/asset.txt")]);
    let mut stopped = Vec::new();
    demand.visit_candidates(literal, |path| { stopped.push(path.to_owned()); stopped.len() < 2 }).unwrap();
    assert_eq!(stopped, paths[..2]);
    struct Provider;
    impl CaptureProvider for Provider {
        fn read_candidate(&self, path: &Path) -> io::Result<Option<SharedBytes>> {
            Ok((path == Path::new("game/late/asset.txt")).then(|| SharedBytes::from(b"winner" as &[u8])))
        }
    }
    let policy = CapturePolicy { certified_raw_extensions: BTreeSet::from(["txt".into()]) };
    let captured = capture_discovered(demand.clone(), CaptureConfig { policy: &policy, encoded: &[], additional: &[] }, &Provider).unwrap();
    assert_eq!(captured.observations.iter().map(|row| row.path.clone()).collect::<Vec<_>>(), stopped);
    let foreign = LiteralRequest { path: "foreign.txt".into(), span: Span::new(0, 1) };
    assert!(demand.visit_candidates(&foreign, |_| true).is_err());
}
