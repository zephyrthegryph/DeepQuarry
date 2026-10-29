use super::*;
use crate::policy_inputs::HostCapture;
use dm_tree::frontend::build;
use std::sync::Arc;
struct Source(dm_preprocess::AcquiredSource);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("test requires actual acquired bytes".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(
        &self,
        _: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
fn capture(source: &'static str) -> (std::path::PathBuf, PolicyInputs) {
    let root = std::env::current_dir().unwrap().join("bare-call-sites");
    let provider = Source(dm_preprocess::AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let frontend = build(
        &root.join("code/probe.dm"),
        &provider,
        &Default::default(),
        1,
    )
    .unwrap();
    let extra = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, {
                let raw = f.text.replace("\r\n", "\n").replace('\r', "\n");
                if raw == f.text.as_str() {
                    f.text.clone()
                } else {
                    raw.into()
                }
            })
        })
        .collect::<Vec<_>>();
    (root, PolicyInputs::capture(&frontend, extra).unwrap())
}
#[test]
fn bare_calls_follow_calls_and_unreachable_siblings_have_exact_callee_origins() {
    let(root,input)=capture("/proc/probe(holder)\n    req_bool(1).next()\n    holder.req_bool(2)\n    global.req_bool(3)\n    return\n    req_bool(4)\n");
    let rows = named(&input, &root, &["req_bool"], || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.1).collect::<Vec<_>>(), [2, 6]);
}
#[test]
fn constructor_targets_are_not_calls_but_arguments_are() {
    let (root, input) = capture("/proc/probe()\n    new req_bool(\n        req_bool(1))\n");
    let rows = named(&input, &root, &["req_bool"], || Ok(())).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].1, 3);
}
#[test]
fn macro_call_and_all_nested_header_expressions_are_observed() {
    let(root,input)=capture("#define WRAPPED(x) req_bool(x)\n/proc/probe()\n    if(WRAPPED(1))\n        return\n    else if(req_bool(2))\n        return\n    for(var/i=req_bool(3);req_bool(4);req_bool(5))\n        return\n");
    let rows = named(&input, &root, &["req_bool"], || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.1).collect::<Vec<_>>(), [3, 5, 7]);
}
#[test]
fn scope_global_form_is_a_call_but_global_receiver_member_is_not() {
    let (root, input) = capture("/proc/probe()\n    ::req_bool(1)\n    global.req_bool(2)\n");
    assert_eq!(
        named(&input, &root, &["req_bool"], || Ok(()))
            .unwrap()
            .iter()
            .map(|row| row.1)
            .collect::<Vec<_>>(),
        [2]
    );
}
#[test]
fn cancellation_returns_no_partial_call_roster() {
    let (root, input) = capture("/proc/probe()\n    req_bool(1)\n");
    let mut checks = 0;
    assert!(named(&input, &root, &["req_bool"], || {
        checks += 1;
        if checks > 1 {
            Err("cancelled".into())
        } else {
            Ok(())
        }
    })
    .is_err());
}

#[test]
fn physical_argument_lines_survive_crlf_joining_without_text_search() {
    let (root, input) = capture(
        "/proc/probe()\r\n    new req_bool(\r\n        req_bool(1),\r\n        req_bool(2))\r\n",
    );
    let rows = named(&input, &root, &["req_bool"], || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|row| row.1).collect::<Vec<_>>(), [3, 4]);
}
#[test]
fn no_original_acquisition_proof_is_not_a_guessed_clean_call_roster() {
    struct Unproven;
    impl dm_preprocess::SourceProvider for Unproven {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/proc/probe()\n    req_bool(1)\n".into())
        }
    }
    let root = std::env::current_dir().unwrap().join("unproven-call-sites");
    let frontend = build(
        &root.join("code/probe.dm"),
        &Unproven,
        &Default::default(),
        1,
    )
    .unwrap();
    let extra = frontend
        .files
        .iter()
        .filter(|file| file.captured)
        .map(|file| {
            HostCapture::analyze_raw(
                Arc::clone(&file.path),
                PolicyRole::DmSource,
                file.text.clone(),
            )
        })
        .collect::<Vec<_>>();
    let inputs = PolicyInputs::capture(&frontend, extra).unwrap();
    assert!(named(&inputs, &root, &["req_bool"], || Ok(())).is_err());
}

#[test]
fn joined_macro_call_without_producer_line_proof_is_explicitly_unsupported() {
    let (root, input) = capture("#define ID(x) x\n/proc/probe()\n    ID(\n        req_bool(1))\n");
    assert!(
        named(&input, &root, &["req_bool"], || Ok(())).is_err(),
        "row-wide macro traces must not guess the physical argument line"
    );
}
