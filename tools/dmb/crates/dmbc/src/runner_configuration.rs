//! Exact session configuration construction shared by request admission.
use std::{collections::BTreeMap, io, path::Path};
pub(super) fn session(
    project: &Path,
    defines: &BTreeMap<String, String>,
    compiler: u128,
    engine: u128,
    bootstrap: bool,
) -> io::Result<crate::session::Configuration> {
    crate::session::Configuration::new(
        project
            .parent()
            .ok_or_else(|| io::Error::other("manifest parent missing"))?,
        project,
        defines.clone(),
        compiler,
        engine,
        xxhash_rust::xxh3::xxh3_128(if bootstrap {
            b"native-session-v1-bootstrap"
        } else {
            b"native-session-v1-template"
        }),
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn extraction_preserves_complete_session_configuration() {
        let root = std::env::current_dir().unwrap();
        let project = root.join("fixture.dme");
        let defines = BTreeMap::from([("MODE".into(), "1".into())]);
        for bootstrap in [false, true] {
            let expected = crate::session::Configuration::new(
                &root,
                &project,
                defines.clone(),
                11,
                22,
                xxhash_rust::xxh3::xxh3_128(if bootstrap {
                    b"native-session-v1-bootstrap"
                } else {
                    b"native-session-v1-template"
                }),
            )
            .unwrap();
            assert_eq!(
                session(&project, &defines, 11, 22, bootstrap).unwrap(),
                expected
            );
        }
    }
}
