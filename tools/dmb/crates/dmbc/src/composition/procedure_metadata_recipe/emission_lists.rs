//! Exact current numeric list payloads on the existing immutable artifact owner.
use super::*;
pub(super) struct LocalList {
    first: u32,
    count: usize,
    words: Arc<Vec<u32>>,
}
pub(super) struct ArgumentList {
    first: u32,
    words: Arc<Vec<u32>>,
}
impl ProcedureMetadataRecipe {
    pub(super) fn release_emission_lists(&self) -> usize {
        let locals = self
            .locals
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        let arguments = self
            .arguments
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        let count = usize::from(locals.is_some()) + usize::from(arguments.is_some());
        drop(locals);
        drop(arguments);
        count
    }
    pub(crate) fn local_list(&self, first: u32, count: usize) -> Arc<Vec<u32>> {
        let mut current = self.locals.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(hit) = current
            .as_ref()
            .filter(|x| x.first == first && x.count == count)
        {
            return Arc::clone(&hit.words);
        }
        // The emitter has already admitted every current variable index.
        let words = Arc::new(
            (0..count)
                .map(|i| first + u32::try_from(i).expect("admitted local index"))
                .collect(),
        );
        *current = Some(LocalList {
            first,
            count,
            words: Arc::clone(&words),
        });
        words
    }
    pub(crate) fn argument_list(
        &self,
        first: u32,
        flags: &[u32],
        sources: Vec<u32>,
    ) -> Arc<Vec<u32>> {
        let mut current = self.arguments.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(hit) = current.as_ref().filter(|x| {
            x.first == first
                && x.words.len() / 4 == flags.len()
                && flags.len() == sources.len()
                && x.words
                    .chunks_exact(4)
                    .zip(flags.iter().zip(&sources))
                    .all(|(row, (&flag, &source))| row[0] == flag && row[1] == source)
        }) {
            return Arc::clone(&hit.words);
        }
        let words = Arc::new(
            flags
                .iter()
                .zip(&sources)
                .enumerate()
                .flat_map(|(i, (&flag, &source))| {
                    [
                        flag,
                        source,
                        first + u32::try_from(i).expect("admitted argument index"),
                        0,
                    ]
                })
                .collect(),
        );
        *current = Some(ArgumentList {
            first,
            words: Arc::clone(&words),
        });
        words
    }
    pub(super) fn census_emission_lists(&self, census: &mut crate::heap_census::HeapCensus) {
        let name = "procedure_metadata.emission_lists";
        if let Some(local) = self
            .locals
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
        {
            if census.arc_object(name, &local.words) {
                census.vec_payload(name, &local.words);
            }
        }
        if let Some(args) = self
            .arguments
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
        {
            if census.arc_object(name, &args.words) {
                census.vec_payload(name, &args.words);
            }
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pressure_release_rebuilds_exact_lists_and_keeps_symbolic_recipe() {
        let mut symbols = SymbolTable::default();
        let identity = UnitIdentity {
            owner: symbols.intern("/").unwrap(),
            name: symbols.intern("run").unwrap(),
            namespace: Namespace::Proc,
            occurrence: 0,
        };
        let recipe = ProcedureMetadataRecipe::capture(identity, &symbols, None).unwrap();
        let path = recipe.path(&symbols, true).unwrap();
        let locals = recipe.local_list(9, 2);
        let arguments = recipe.argument_list(20, &[1, 4], vec![0x40, 0x340]);
        let old_locals = Arc::downgrade(&locals);
        let old_arguments = Arc::downgrade(&arguments);
        let expected_locals = locals.as_ref().clone();
        let expected_arguments = arguments.as_ref().clone();
        drop(locals);
        drop(arguments);
        assert_eq!(recipe.release_numeric_caches(), 2);
        assert!(old_locals.upgrade().is_none());
        assert!(old_arguments.upgrade().is_none());
        assert_eq!(recipe.release_numeric_caches(), 0);
        assert!(Arc::ptr_eq(&path, &recipe.path(&symbols, true).unwrap()));
        assert_eq!(*recipe.local_list(9, 2), expected_locals);
        assert_eq!(
            *recipe.argument_list(20, &[1, 4], vec![0x40, 0x340]),
            expected_arguments
        );
        assert_eq!(
            recipe.argument_list(30, &[2], vec![0x440]).as_slice(),
            &[2, 0x440, 30, 0]
        );
    }
    #[test]
    fn exact_numeric_inputs_reuse_and_each_dependency_invalidates() {
        let mut symbols = SymbolTable::default();
        let identity = UnitIdentity {
            owner: symbols.intern("/").unwrap(),
            name: symbols.intern("run").unwrap(),
            namespace: Namespace::Proc,
            occurrence: 0,
        };
        let recipe = ProcedureMetadataRecipe::capture(identity, &symbols, None).unwrap();
        let locals = recipe.local_list(9, 2);
        assert_eq!(&**locals, &[9, 10]);
        assert!(Arc::ptr_eq(&locals, &recipe.local_list(9, 2)));
        assert!(!Arc::ptr_eq(&locals, &recipe.local_list(10, 2)));
        assert!(recipe.local_list(0, 0).is_empty());
        let args = recipe.argument_list(20, &[1, 4], vec![0x40, 0x340]);
        assert_eq!(&**args, &[1, 0x40, 20, 0, 4, 0x340, 21, 0]);
        assert!(Arc::ptr_eq(
            &args,
            &recipe.argument_list(20, &[1, 4], vec![0x40, 0x340])
        ));
        assert!(!Arc::ptr_eq(
            &args,
            &recipe.argument_list(21, &[1, 4], vec![0x40, 0x340])
        ));
        let changed = recipe.argument_list(20, &[2, 4], vec![0x40, 0x340]);
        assert_eq!(changed[0], 2);
        let changed = recipe.argument_list(20, &[1, 4], vec![0x40, 0x440]);
        assert_eq!(changed[5], 0x440);
        assert!(recipe.argument_list(0, &[], vec![]).is_empty());
    }
}
