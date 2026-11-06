//! Current-build projections only. File IDs and include ancestry never cross builds.
use super::*;
use std::cell::OnceCell;

type ProjectedStack = (Arc<Box<[MacroExpansion]>>, Arc<[Span]>);
#[derive(Default)]
pub(super) struct CurrentSourceProjection {
    stacks: RefCell<HashMap<usize, ProjectedStack>>,
    chains: RefCell<HashMap<usize, Arc<[usize]>>>,
    empty: OnceCell<Arc<[Span]>>,
}
impl Mapping<'_> {
    pub(super) fn expansion_stack(
        &self,
        trace: &Arc<Box<[MacroExpansion]>>,
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
                // Definition paths are project-relative (equal in every worktree); files are keyed by their full path.
                let file = if definition.path.is_relative() {
                    self.by_path.get(&self.plan.project_dir.join(definition.path.as_ref()))
                } else {
                    self.by_path.get(definition.path.as_ref())
                };
                file.map(|file| (*file, definition))
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
        }].into_boxed_slice());
        let first_paths = HashMap::from([(path.as_ref().clone(), FileId(1))]);
        let second_paths = HashMap::from([(path.as_ref().clone(), FileId(2))]);
        let mapping = Mapping {
            projection: Default::default(),
            plan: frontend.plan.source_geometry(),
            expanded: &frontend.expanded,
            files: &frontend.files,
            by_path: &first_paths,
            hints: Default::default(),
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
        let empty = mapping.expansion_stack(&Arc::default()).unwrap();
        assert!(Arc::ptr_eq(
            &empty,
            &mapping.expansion_stack(&Arc::default()).unwrap()
        ));
        let current = Mapping {
            projection: Default::default(),
            plan: frontend.plan.source_geometry(),
            expanded: &frontend.expanded,
            files: &frontend.files,
            by_path: &second_paths,
            hints: Default::default(),
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
            plan: frontend.plan.source_geometry(),
            expanded: &frontend.expanded,
            files: &frontend.files,
            by_path: &paths,
            hints: Default::default(),
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
        }].into_boxed_slice());
        assert!(mapping.expansion_stack(&trace).is_err());
        assert!(mapping.projection.stacks.borrow().is_empty());
        assert!(mapping.expansion_stack(&trace).is_err());
    }
}

impl Mapping<'_>{
 /// The SAME projection cache and source_location_in producer, with actual
 /// include-chain/cache growth funded before the fatal report can retain it.
 pub(super) fn output_for_retained_report(&self,offset:usize,a:&dm_syntax::SettingAdmission<'_>,credit:&mut dm_syntax::SettingRootLease)->std::io::Result<SourceLocation>{
  let poll=||{let result=a.checkpoint();if let Some(error)=a.take_operational_error(){return Err(error)}result};poll()?;
  let origin=self.origin(offset).ok_or(std::io::ErrorKind::InvalidInput)?;let region=self.plan.regions.get(origin.region).ok_or(std::io::ErrorKind::InvalidInput)?;let occurrence=region.occurrence;let row=self.plan.occurrences.get(occurrence).ok_or(std::io::ErrorKind::InvalidInput)?;
  let cached=self.projection.chains.borrow().get(&occurrence).cloned();
  let chain=match cached{Some(chain)=>chain,None=>{
   let mut count=1usize;let mut at=occurrence;while let Some(parent)=self.plan.occurrences.get(at).ok_or(std::io::ErrorKind::InvalidInput)?.parent{poll()?;count=count.checked_add(1).ok_or(std::io::ErrorKind::OutOfMemory)?;if count>self.plan.occurrences.len(){return Err(std::io::ErrorKind::InvalidData.into())}at=parent;}
   let peak=count.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<usize>())).and_then(|n|n.checked_add(2*std::mem::size_of::<usize>())).ok_or(std::io::ErrorKind::OutOfMemory)?;a.grow(credit,peak).map_err(|error|a.take_operational_error().unwrap_or(error))?;
   let mut chain=Vec::new();chain.try_reserve_exact(count).map_err(|error|std::io::Error::new(std::io::ErrorKind::OutOfMemory,error))?;if chain.capacity()>count.checked_mul(2).ok_or(std::io::ErrorKind::OutOfMemory)?{return Err(std::io::ErrorKind::OutOfMemory.into())}let mut at=occurrence;loop{poll()?;chain.push(at);match self.plan.occurrences.get(at).ok_or(std::io::ErrorKind::InvalidInput)?.parent{Some(parent)=>at=parent,None=>break}}chain.reverse();let chain:Arc<[usize]>=chain.into();
   let mut cache=self.projection.chains.borrow_mut();if cache.len()==cache.capacity(){let target=cache.capacity().max(2).checked_mul(2).ok_or(std::io::ErrorKind::OutOfMemory)?;let unit=std::mem::size_of::<(usize,Arc<[usize]>)>()+2*std::mem::size_of::<usize>();let peak=target.checked_mul(4).and_then(|n|n.checked_mul(unit)).ok_or(std::io::ErrorKind::OutOfMemory)?;a.grow(credit,peak).map_err(|error|a.take_operational_error().unwrap_or(error))?;let extra=target-cache.len();cache.try_reserve(extra).map_err(|error|std::io::Error::new(std::io::ErrorKind::OutOfMemory,error))?;if cache.capacity()>target.checked_mul(4).ok_or(std::io::ErrorKind::OutOfMemory)?{return Err(std::io::ErrorKind::OutOfMemory.into())}}
   cache.insert(occurrence,Arc::clone(&chain));chain
  }};
  source_export_mapping::source_location_in(self.file_of(origin.origin.path).ok_or(std::io::ErrorKind::InvalidInput)?,origin,&row.path,&row.semantic_path,region.encounter_ordinal,occurrence,chain).ok_or_else(||std::io::ErrorKind::InvalidInput.into())
 }
}
