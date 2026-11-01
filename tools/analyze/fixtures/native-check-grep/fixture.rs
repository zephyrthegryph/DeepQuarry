//! Exact initial filesystem bytes shared by actual native and immutable old policy tests.
pub fn files(case:&str)->Result<&'static[(&'static str,&'static[u8])],&'static str>{match case{
"basic"|"lossy"=>Ok(&[
 ("deepquarry.dme",include_bytes!("basic/deepquarry.dme")),
 ("code/probe.dm",include_bytes!("basic/code/probe.dm")),
 ("code/raw.dm",include_bytes!("basic/code/raw.dm")),
 ("code/exempt/extra.dm",include_bytes!("basic/code/exempt/extra.dm")),
 ("maps/probe.dmm",include_bytes!("basic/maps/probe.dmm")),
 ("tgui/probe.jsx",include_bytes!("basic/tgui/probe.jsx")),
 ("tgui/.hidden/skip.jsx",include_bytes!("basic/tgui/.hidden/skip.jsx")),
 ("tgui/packages/tgui/interfaces/Probe.tsx",include_bytes!("basic/tgui/packages/tgui/interfaces/Probe.tsx")),
 ("dependencies.sh",include_bytes!("basic/dependencies.sh")),
 ("html/changelogs/example.yml",include_bytes!("basic/html/changelogs/example.yml")),
 ("config/example/config.txt",include_bytes!("basic/config/example/config.txt")),
 ("code/__defines/verdigris/_bindings_types.dm",include_bytes!("basic/code/__defines/verdigris/_bindings_types.dm")),
 ("code/__defines/verdigris/_bindings.dm",include_bytes!("basic/code/__defines/verdigris/_bindings.dm")),
 (".gitignore",include_bytes!("basic/.gitignore")),
 ("code/ignored.dm",include_bytes!("basic/code/ignored.dm")),
 ("tools/ci/lint_scopes.toml",include_bytes!("basic/tools/ci/lint_scopes.toml")),
]),
"configured"=>Ok(&[
 ("deepquarry.dme",include_bytes!("configured/deepquarry.dme")),
 ("code/probe.dm",include_bytes!("configured/code/probe.dm")),
 ("code/raw.dm",include_bytes!("configured/code/raw.dm")),
 ("code/exempt/extra.dm",include_bytes!("configured/code/exempt/extra.dm")),
 ("maps/probe.dmm",include_bytes!("configured/maps/probe.dmm")),
 ("tgui/probe.jsx",include_bytes!("configured/tgui/probe.jsx")),
 ("tgui/.hidden/skip.jsx",include_bytes!("configured/tgui/.hidden/skip.jsx")),
 ("tgui/packages/tgui/interfaces/Probe.tsx",include_bytes!("configured/tgui/packages/tgui/interfaces/Probe.tsx")),
 ("dependencies.sh",include_bytes!("configured/dependencies.sh")),
 ("html/changelogs/example.yml",include_bytes!("configured/html/changelogs/example.yml")),
 ("config/example/config.txt",include_bytes!("configured/config/example/config.txt")),
 ("code/__defines/verdigris/_bindings_types.dm",include_bytes!("configured/code/__defines/verdigris/_bindings_types.dm")),
 ("code/__defines/verdigris/_bindings.dm",include_bytes!("configured/code/__defines/verdigris/_bindings.dm")),
 (".gitignore",include_bytes!("configured/.gitignore")),
 ("code/ignored.dm",include_bytes!("configured/code/ignored.dm")),
 ("tools/ci/lint_scopes.toml",include_bytes!("configured/tools/ci/lint_scopes.toml")),
]),
_=>Err("expected basic, configured or lossy check_grep fixture"),}}

/// Exact shared initial bytes for the uncompiled-invalid-UTF8 control. These
/// bytes are source data, never native answers; the compiled manifest is unchanged.
pub fn source_bytes<'a>(case:&str,relative:&str,original:&'a[u8])->std::borrow::Cow<'a,[u8]>{
 if case!="lossy"{return std::borrow::Cow::Borrowed(original)}
 if matches!(relative,"code/__defines/verdigris/_bindings_types.dm"|"code/__defines/verdigris/_bindings.dm"|".gitignore"|"dependencies.sh"){let mut bytes=original.to_vec();bytes.extend_from_slice(b"\r\n// invalid uncompiled source byte: \xff\r");return std::borrow::Cow::Owned(bytes)}
 if relative=="code/raw.dm"{let mut bytes=original.to_vec();bytes.extend_from_slice(b"/proc/dynamic_control()\n    consume(init_fixture_seed)\n    cached = get_fixture_query_probe()\n#define FIXTURE_BINDING 2\n");return std::borrow::Cow::Owned(bytes)}
 std::borrow::Cow::Borrowed(original)
}
