//! Client script is a world StringID or an ordered resource reference, never
//! ordinary class-variable declaration flags or generated initializer bytecode.
use dm_ir::{SemanticValue, SymbolId};
use std::sync::Arc;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Script {
    Text(Arc<[u8]>),
    Resource(SymbolId),
}

pub fn project(value: &SemanticValue) -> Result<Script, String> {
    match value {
        SemanticValue::Text(bytes) => Ok(Script::Text(bytes.clone())),
        SemanticValue::Resource(symbol) => Ok(Script::Resource(*symbol)),
        _ => Err("client.script must be authored constant text or a resource file".into()),
    }
}

pub trait Bindings {
    fn string(&mut self, dmb: &mut byond_dmb::dmb::Dmb, bytes: &[u8]) -> Result<u32, String>;
    fn resource(&self, symbol: SymbolId) -> Result<u32, String>;
}

/// Included DMS references, if supported by the capture policy, precede the
/// final explicit file. Omitted settings retain captured engine state.
pub fn apply(
    dmb: &mut byond_dmb::dmb::Dmb,
    script: &Script,
    bindings: &mut dyn Bindings,
) -> Result<(), String> {
    match script {
        Script::Text(bytes) => dmb.world.client_script = bindings.string(dmb, bytes)?,
        Script::Resource(symbol) => {
            dmb.world.client_script = byond_dmb::ids::NONE;
            dmb.world.client_script_files.push(bindings.resource(*symbol)?);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use byond_dmb::dmb::Dmb;
    struct CapturedBindings {
        strings: crate::composition::StringIndex,
        resource: u32,
    }
    impl Bindings for CapturedBindings {
        fn string(&mut self, dmb: &mut Dmb, bytes: &[u8]) -> Result<u32, String> {
            self.strings.intern(dmb, bytes).map_err(|error| format!("{error:?}"))
        }
        fn resource(&self, _: SymbolId) -> Result<u32, String> { Ok(self.resource) }
    }
    #[test]
    fn native_inline_and_resource_script_use_separate_wire_domains() {
        let expected = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/client_header_probe/script_inline.native.bin"
        )).unwrap();
        let mut actual = expected.clone();
        actual.world.client_script = byond_dmb::ids::NONE;
        let mut bindings = CapturedBindings {
            strings: crate::composition::StringIndex::build(&actual).unwrap(), resource: 0,
        };
        apply(&mut actual, &Script::Text(Arc::from(
            b"<STYLE>BODY {font: monospace}</STYLE>".as_slice()
        )), &mut bindings).unwrap();
        assert_eq!(actual.world.client_script, expected.world.client_script);
        assert_eq!(actual.world.client_script_files, expected.world.client_script_files);

        let expected = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/client_header_probe/script_file.native.bin"
        )).unwrap();
        let mut actual = expected.clone();
        actual.world.client_script_files.clear();
        bindings.resource = expected.world.client_script_files[0];
        apply(&mut actual, &Script::Resource(SymbolId::of("example.dms")), &mut bindings).unwrap();
        assert_eq!(actual.world.client_script, expected.world.client_script);
        assert_eq!(actual.world.client_script_files, expected.world.client_script_files);
        assert!(project(&SemanticValue::Null).is_err());
    }
}
