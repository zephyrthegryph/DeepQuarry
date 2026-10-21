//! Whole-stage early cutoff on the general path (doc/incremental_core.md, migration plan).
//!
//! A stage's output is a query value: when every input it read equals the input of a retained
//! earlier output, that output is the answer and the stage does not run. Inputs are compared as
//! versions, never as edit kinds: the answer table's version (`QueryDb::answers_version`: tree,
//! answer world, resource searches), the expanded program outside procedure bodies with every
//! source position (`declaration_inputs`), and the stage's own configuration. A request that
//! reuses a stage keeps the claims its earlier output holds in the stage's stores (the request
//! does not publish those stores), so nothing it reused is released.
//!
//! The retained products follow the session's publication protocol: a request reads the last
//! successfully published products and its own become visible only when it publishes.
use std::sync::{Arc, Mutex};

/// Products of the initializer stage (initializer lowering, class projection, declaration
/// warnings and modified-instance default seeds).
pub(crate) struct InitializerProducts {
    pub key: u128,
    pub units: Vec<crate::initializer_lowering::LoweredInitializerUnit>,
    pub projection: crate::class_projection::ClassProjection,
    /// Initializer and callable warnings (local warnings are per body and always recomputed).
    pub warnings: Vec<crate::initializer_policy::warnings::InitializerWarning>,
    pub modified_defaults: Vec<(
        dm_ir::SymRef,
        dm_codegen_byond::lower_resolver::CapturedModifiedInstance,
        crate::debug_sources::DebugOrigins,
    )>,
}

#[derive(Clone, Default)]
struct Products {
    /// The answer table's version when the request that left these products published: every
    /// answer its stages read is still the same exactly when the current version equals it.
    answers: Option<u128>,
    initializers: Option<Arc<InitializerProducts>>,
}
type Pending = Arc<Mutex<Products>>;

/// Session owner of the last published stage products.
pub(crate) struct StageProducts {
    publication: Arc<dm_session::ArtifactPublication<Pending>>,
}
impl Default for StageProducts {
    fn default() -> Self {
        Self {
            publication: Arc::new(Default::default()),
        }
    }
}
impl StageProducts {
    pub(crate) fn for_request(&self, publishable: bool) -> Arc<StageAttempt> {
        let previous = self
            .publication
            .with_published(|products| {
                products.lock().unwrap_or_else(|error| error.into_inner()).clone()
            })
            .unwrap_or_default();
        let current: Pending = Default::default();
        let attempt = if publishable {
            self.publication.begin(Arc::clone(&current))
        } else {
            self.publication.begin_ephemeral(Arc::clone(&current))
        };
        Arc::new(StageAttempt {
            previous,
            current,
            attempt,
        })
    }
}

/// One request's view: the products it may reuse and the products it leaves behind.
pub(crate) struct StageAttempt {
    previous: Products,
    current: Pending,
    attempt: dm_session::ArtifactAttempt<Pending>,
}
impl StageAttempt {
    /// The retained initializer products, when their inputs other than answers had version
    /// `key` and the answer table now has the version it had when they were published.
    pub(crate) fn initializers(
        &self,
        key: u128,
        answers: Option<u128>,
    ) -> Option<Arc<InitializerProducts>> {
        if answers.is_none() || self.previous.answers != answers {
            return None;
        }
        self.previous
            .initializers
            .as_ref()
            .filter(|products| products.key == key)
            .cloned()
    }
    pub(crate) fn keep_initializers(&self, products: Arc<InitializerProducts>) {
        self.current
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .initializers = Some(products);
    }
    /// Called only after the request published successfully, with the answer table's version
    /// at that point.
    pub(crate) fn publish_successful(&self, answers: Option<u128>) -> bool {
        self.current
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .answers = answers;
        self.attempt.publish_successful()
    }
}

/// Version of everything a declaration-level stage reads from the frontend: the file roster,
/// the expanded text outside procedure bodies (declarations, initializer expressions) and every
/// expanded line's source position (region, file, line), which fixes the debug line and the
/// warning location of each declaration. Body text is excluded, so an edit inside a body that
/// moves no line keeps the version; any line shift changes it.
pub(crate) fn declaration_inputs(
    frontend: &dm_tree::frontend::ColdFrontend,
    executor: &dm_exec::BuildExecutor,
) -> u128 {
    use xxhash_rust::xxh3::Xxh3;
    let _timer = dm_profile::detail_timer("stage_reuse.declaration_inputs");
    let text = frontend.expanded.text.as_str().as_bytes();
    let mut spans: Vec<(usize, usize)> = frontend
        .bodies
        .iter()
        .map(|body| {
            let span = body.expanded_span.range();
            let start = span.start.min(text.len());
            (start, span.end.min(text.len()).max(start))
        })
        .collect();
    spans.sort_unstable();
    let mut outside = Xxh3::new();
    outside.update(b"dm-declaration-inputs-v1\0");
    for file in frontend.files.iter() {
        outside.update(file.path.as_os_str().as_encoded_bytes());
        outside.update(&[0, u8::from(file.captured)]);
    }
    let mut through = 0usize;
    for (start, end) in spans {
        if start >= through {
            outside.update(&((start - through) as u64).to_le_bytes());
            outside.update(&text[through..start]);
        }
        outside.update(b"\0body\0");
        through = through.max(end);
    }
    outside.update(&text[through.min(text.len())..]);
    // Positions: one row per expanded origin, without byte offsets (an edit inside a body that
    // keeps its line count moves bytes, not lines). Paths are hashed once per distinct owner.
    let origins = &frontend.expanded.origins;
    const CHUNK: usize = 16 * 1024;
    let starts: Vec<usize> = (0..origins.len()).step_by(CHUNK).collect();
    let positions: Vec<u128> = executor.install(|| {
        use rayon::prelude::*;
        starts
            .par_iter()
            .map(|&start| {
                let end = (start + CHUNK).min(origins.len());
                let mut paths: std::collections::HashMap<usize, u64> = Default::default();
                let mut rows = Vec::with_capacity((end - start) * 32);
                for index in start..end {
                    let Some(origin) = origins.get(index) else {
                        break;
                    };
                    let path = *paths
                        .entry(Arc::as_ptr(origin.origin.path) as usize)
                        .or_insert_with(|| {
                            xxhash_rust::xxh3::xxh3_64(
                                origin.origin.path.as_os_str().as_encoded_bytes(),
                            )
                        });
                    rows.extend_from_slice(&(origin.region as u64).to_le_bytes());
                    rows.extend_from_slice(&path.to_le_bytes());
                    rows.extend_from_slice(&(origin.origin.output_line as u64).to_le_bytes());
                    rows.extend_from_slice(&(origin.origin.source_line as u64).to_le_bytes());
                }
                xxhash_rust::xxh3::xxh3_128(&rows)
            })
            .collect()
    });
    outside.update(&(origins.len() as u64).to_le_bytes());
    for chunk in positions {
        outside.update(&chunk.to_le_bytes());
    }
    outside.digest128()
}
