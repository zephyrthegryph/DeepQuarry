//! Current-build projections only. File IDs and include ancestry never cross builds.
use super::*;
use std::cell::OnceCell;

type ProjectedStack = (Arc<Vec<MacroExpansion>>, Arc<[Span]>);
#[derive(Default)]
pub(super) struct CurrentSourceProjection {
    stacks: RefCell<HashMap<usize, ProjectedStack>>,
    chains: RefCell<HashMap<usize, Arc<[usize]>>>,
    empty: OnceCell<Arc<[Span]>>,
}
impl Mapping<'_> {
    pub(super) fn expansion_stack(
        &self,
        trace: &Arc<Vec<MacroExpansion>>,
    ) -> Result<Arc<[Span]>, Vec<Diagnostic>> {
        if trace.is_empty() {
            return Ok(Arc::clone(
                self.projection.empty.get_or_init(|| Arc::from([])),
            ));
        }
        let key = Arc::as_ptr(trace) as usize;
        if let Some((_, stack)) = self.projection.stacks.borrow().get(&key) {
            return Ok(Arc::clone(stack));
        }
        // Exact original projection order and missing-path behavior. Failed
        // projections are not installed, so the original error remains current.
        let stack: Arc<[Span]> = trace
            .iter()
            .filter_map(|expansion| expansion.definition.as_ref())
            .filter_map(|definition| {
                self.by_path
                    .get(definition.path.as_ref())
                    .map(|file| (*file, definition))
            })
            .map(|(file, definition)| source_span(file, definition.source_span))
            .collect::<Result<Vec<_>, _>>()?
            .into();
        // Retain the trace Arc so an allocation address cannot be reused while
        // this projection exists, including diagnostic/custom caller traces.
        self.projection
            .stacks
            .borrow_mut()
            .insert(key, (Arc::clone(trace), Arc::clone(&stack)));
        Ok(stack)
    }
    pub(super) fn include_chain(&self, occurrence: usize) -> Arc<[usize]> {
        if let Some(chain) = self.projection.chains.borrow().get(&occurrence) {
            return Arc::clone(chain);
        }
        let chain: Arc<[usize]> = self.chain(occurrence).into();
        self.projection
            .chains
            .borrow_mut()
            .insert(occurrence, Arc::clone(&chain));
        chain
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    struct Source;
    impl SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/proc/a()\n    return 1\n/proc/b()\n    return 2\n".into())
        }
    }
    #[test]
    fn current_projection_shares_trace_and_chain_backing_but_rebinds_file_ids() {
        let frontend = build(Path::new("project.dme"), &Source, &BTreeMap::new(), 1).unwrap();
        assert!(Arc::ptr_eq(
            &frontend.bodies[0].source.include_chain,
            &frontend.bodies[1].source.include_chain
        ));
        let path = Arc::new(PathBuf::from("definition.dm"));
        let trace = Arc::new(vec![MacroExpansion {
            name: Arc::from("VALUE"),
            invocation_span: dm_syntax::Span::new(0, 1),
            replacement_chain: Arc::from([]),
            definition: Some(dm_preprocess::regions::DefinitionOrigin {
                path: path.clone(),
                source_span: dm_syntax::Span::new(3, 7),
                source_line: 1,
            }),
        }]);
        let first_paths = HashMap::from([(path.as_ref().clone(), FileId(1))]);
        let second_paths = HashMap::from([(path.as_ref().clone(), FileId(2))]);
        let mapping = Mapping {
            projection: Default::default(),
            plan: &frontend.plan,
            expanded: &frontend.expanded,
            files: &frontend.files,
            by_path: &first_paths,
        };
        let first = mapping.expansion_stack(&trace).unwrap();
        let same = mapping.expansion_stack(&trace).unwrap();
        assert!(Arc::ptr_eq(&first, &same));
        assert_eq!(
            first[0],
            Span {
                file: FileId(1),
                start: 3,
                end: 7
            }
        );
        let empty = mapping.expansion_stack(&Arc::new(Vec::new())).unwrap();
        assert!(Arc::ptr_eq(
            &empty,
            &mapping.expansion_stack(&Arc::new(Vec::new())).unwrap()
        ));
        let current = Mapping {
            projection: Default::default(),
            plan: &frontend.plan,
            expanded: &frontend.expanded,
            files: &frontend.files,
            by_path: &second_paths,
        };
        let rebound = current.expansion_stack(&trace).unwrap();
        assert_eq!(rebound[0].file, FileId(2));
        assert!(!Arc::ptr_eq(&first, &rebound));
    }
    #[test]
    fn invalid_current_definition_span_never_installs_projected_stack() {
        let frontend = build(Path::new("project.dme"), &Source, &BTreeMap::new(), 1).unwrap();
        let path = Arc::new(PathBuf::from("definition.dm"));
        let paths = HashMap::from([(path.as_ref().clone(), FileId(0))]);
        let mapping = Mapping {
            projection: Default::default(),
            plan: &frontend.plan,
            expanded: &frontend.expanded,
            files: &frontend.files,
            by_path: &paths,
        };
        let trace = Arc::new(vec![MacroExpansion {
            name: Arc::from("VALUE"),
            invocation_span: dm_syntax::Span::new(0, 1),
            replacement_chain: Arc::from([]),
            definition: Some(dm_preprocess::regions::DefinitionOrigin {
                path,
                source_span: dm_syntax::Span::new(0, usize::MAX),
                source_line: 1,
            }),
        }]);
        assert!(mapping.expansion_stack(&trace).is_err());
        assert!(mapping.projection.stacks.borrow().is_empty());
        assert!(mapping.expansion_stack(&trace).is_err());
    }
}
