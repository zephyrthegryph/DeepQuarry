use super::*;
fn row(line: usize, path: Arc<PathBuf>, traces: Arc<Vec<MacroExpansion>>) -> ExpandedOrigin {
    ExpandedOrigin {
        origin: super::super::Origin {
            output_line: line,
            path,
            source_line: 17,
        },
        output_span: Span::new(3, 8),
        source_span: Span::new(10, 20),
        region: 2,
        macro_expansions: traces,
    }
}

#[cfg(target_pointer_width = "64")]
#[test]
fn sequential_lines_widen_independently_for_each_large_coordinate() {
    for large_source_line in [true, false] {
        let path = Arc::new(PathBuf::from("included.dm"));
        let traces = Arc::new(Vec::new());
        let mut builder = OriginArenaBuilder::default();
        builder.push(row(1, path.clone(), traces.clone()));
        let mut second = row(2, path.clone(), traces.clone());
        if large_source_line {
            second.origin.source_line = usize::MAX;
        } else {
            second.output_span.end = usize::MAX;
        }
        builder.push(second);
        builder.push(row(3, path.clone(), traces.clone()));
        let arena = builder.finish();
        assert!(matches!(&arena.0.records, Records::Wide(_)));
        assert_eq!(
            arena
                .iter()
                .map(|view| view.origin.output_line)
                .collect::<Vec<_>>(),
            [1, 2, 3]
        );
        let view = arena.get(1).unwrap();
        assert_eq!(
            view.origin.source_line,
            if large_source_line { usize::MAX } else { 17 }
        );
        assert_eq!(
            view.output_span,
            Span::new(3, if large_source_line { 8 } else { usize::MAX })
        );
        assert_eq!(view.source_span, Span::new(10, 20));
        assert_eq!(view.region, 2);
        assert!(Arc::ptr_eq(view.origin.path, &path));
        assert!(Arc::ptr_eq(view.macro_expansions, &traces));
        assert_eq!(arena.get(0).unwrap().origin.source_line, 17);
        assert_eq!(arena.get(2).unwrap().output_span, Span::new(3, 8));
    }
}

#[test]
fn clearing_one_clone_preserves_other_owner_and_iterator_boundaries() {
    let path = Arc::new(PathBuf::from("same.dm"));
    let traces = Arc::new(Vec::new());
    let mut builder = OriginArenaBuilder::default();
    for line in 1..=3 {
        builder.push(row(line, path.clone(), traces.clone()));
    }
    let mut arena = builder.finish();
    let retained = arena.clone();
    arena.clear();
    assert!(arena.is_empty());
    assert!(arena.get(0).is_none());
    assert!(retained.get(retained.len()).is_none());
    assert!(retained.get(usize::MAX).is_none());
    assert!(Arc::ptr_eq(retained.get(0).unwrap().origin.path, &path));
    assert!(Arc::ptr_eq(
        retained.get(0).unwrap().macro_expansions,
        &traces
    ));
    let mut iter = (&retained).into_iter();
    assert_eq!(iter.len(), 3);
    assert_eq!(iter.next().unwrap().origin.output_line, 1);
    assert_eq!(iter.next_back().unwrap().origin.output_line, 3);
    assert_eq!(iter.len(), 1);
    assert_eq!(iter.next_back().unwrap().origin.output_line, 2);
    assert!(iter.next().is_none());
    assert!(iter.next_back().is_none());
    assert_eq!(retained.partition_point(|_| false), 0);
    assert_eq!(retained.partition_point(|_| true), 3);
}
