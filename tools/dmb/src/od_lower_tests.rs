use super::*;

#[derive(Default)]
struct MockResolver {
    strings: HashMap<u32, u32>,
    builtins: HashMap<u32, u32>,
    types: HashMap<u32, (u8, u32)>,
    modified_instances: HashMap<(u32, u32), u32>,
    reject_procs: bool,
}

impl MockResolver {
    fn with_string(mut self, source: u32, native: u32) -> Self {
        self.strings.insert(source, native);
        self
    }

    fn with_builtin(mut self, source: u32, native: u32) -> Self {
        self.builtins.insert(source, native);
        self
    }

    fn without_procs(mut self) -> Self {
        self.reject_procs = true;
        self
    }

    fn with_type(mut self, source: u32, tag: u8, native: u32) -> Self {
        self.types.insert(source, (tag, native));
        self
    }

    fn with_modified_instance(mut self, ty: u32, string: u32, instance: u32) -> Self {
        self.modified_instances.insert((ty, string), instance);
        self
    }
}

impl SymbolResolver for MockResolver {
    fn string(&self, old: u32) -> Option<u32> {
        self.strings.get(&old).copied()
    }

    fn proc_id(&self, old: u32) -> Option<u32> {
        (!self.reject_procs).then_some(old)
    }

    fn builtin_proc(&self, old: u32) -> Option<u32> {
        self.builtins.get(&old).copied()
    }

    fn type_id(&self, old: u32) -> Option<u32> {
        self.types
            .get(&old)
            .map(|(_, native)| *native)
            .or(Some(old))
    }

    fn type_tag(&self, old: u32) -> Option<u8> {
        self.types.get(&old).map(|(tag, _)| *tag).or(Some(32))
    }

    fn modified_instance(&self, old_type: u32, old_string: u32) -> Option<u32> {
        self.modified_instances
            .get(&(old_type, old_string))
            .copied()
    }
}
#[path = "od_lower_tests/suite_1.rs"]
mod suite_1;
#[path = "od_lower_tests/suite_2.rs"]
mod suite_2;
#[path = "od_lower_tests/suite_3.rs"]
mod suite_3;
#[path = "od_lower_tests/suite_4.rs"]
mod suite_4;
#[path = "od_lower_tests/suite_5.rs"]
mod suite_5;
#[path = "od_lower_tests/suite_6.rs"]
mod suite_6;
#[path = "od_lower_tests/suite_7.rs"]
mod suite_7;
