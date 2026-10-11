//! Flat, bounded transport of exact semantic value trees.
use crate::{ProcedureIdentity, SemanticValue, SymbolId};
use serde::{Deserialize, Deserializer, Serialize};
use std::sync::Arc;
const MAX_ITEMS: usize = 65_536;
const MAX_DEPTH: usize = 64;
#[derive(Clone, Debug)]
struct Limited<T>(Vec<T>);
impl<T: Serialize> Serialize for Limited<T> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.0.serialize(serializer)
    }
}
impl<'de, T: Deserialize<'de>> Deserialize<'de> for Limited<T> {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct Visitor<T>(std::marker::PhantomData<T>);
        impl<'de, T: Deserialize<'de>> serde::de::Visitor<'de> for Visitor<T> {
            type Value = Limited<T>;
            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("bounded portable value sequence")
            }
            fn visit_seq<A: serde::de::SeqAccess<'de>>(
                self,
                mut seq: A,
            ) -> Result<Self::Value, A::Error> {
                if seq.size_hint().is_some_and(|n| n > MAX_ITEMS) {
                    return Err(serde::de::Error::custom(
                        "portable value sequence exceeds bound",
                    ));
                }
                let mut out = Vec::new();
                while let Some(item) = seq.next_element()? {
                    if out.len() == MAX_ITEMS {
                        return Err(serde::de::Error::custom(
                            "portable value sequence exceeds bound",
                        ));
                    }
                    out.push(item);
                }
                Ok(Limited(out))
            }
        }
        d.deserialize_seq(Visitor(std::marker::PhantomData))
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
enum Node {
    Null,
    NumberBits(u32),
    Text(Limited<u8>),
    Type(SymbolId),
    Procedure(ProcedureIdentity),
    Resource(SymbolId),
    List(Limited<(Option<u32>, u32)>),
}
#[derive(Clone, Debug, Serialize)]
pub struct PortableValue {
    nodes: Limited<Node>,
}
impl<'de> Deserialize<'de> for PortableValue {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        struct Wire {
            nodes: Limited<Node>,
        }
        let wire = Wire::deserialize(d)?;
        let value = Self { nodes: wire.nodes };
        if !value.valid() {
            return Err(serde::de::Error::custom(
                "malformed portable semantic value tree",
            ));
        }
        Ok(value)
    }
}
impl PortableValue {
    fn valid(&self) -> bool {
        if self.nodes.0.is_empty() || self.nodes.0.len() > MAX_ITEMS {
            return false;
        }
        let mut parents = vec![0u8; self.nodes.0.len()];
        let mut depths = vec![1usize; self.nodes.0.len()];
        let mut bytes = 0usize;
        for (index, node) in self.nodes.0.iter().enumerate() {
            match node {
                Node::Text(text) => {
                    bytes = match bytes.checked_add(text.0.len()) {
                        Some(n) => n,
                        None => return false,
                    };
                    if bytes > MAX_ITEMS {
                        return false;
                    }
                }
                Node::List(entries) => {
                    for child in entries
                        .0
                        .iter()
                        .flat_map(|(key, value)| key.iter().chain(std::iter::once(value)))
                    {
                        let child = *child as usize;
                        if child >= index || parents[child] != 0 {
                            return false;
                        }
                        parents[child] = 1;
                        depths[index] = depths[index].max(depths[child] + 1);
                        if depths[index] > MAX_DEPTH {
                            return false;
                        }
                    }
                }
                _ => {}
            }
        }
        parents[..parents.len() - 1].iter().all(|n| *n == 1) && parents[parents.len() - 1] == 0
    }
    pub fn capture(value: &SemanticValue) -> Option<Self> {
        fn push(
            value: &SemanticValue,
            depth: usize,
            nodes: &mut Vec<Node>,
            bytes: &mut usize,
        ) -> Option<u32> {
            if depth > MAX_DEPTH || nodes.len() >= MAX_ITEMS {
                return None;
            }
            let node = match value {
                SemanticValue::Null => Node::Null,
                SemanticValue::NumberBits(v) => Node::NumberBits(*v),
                SemanticValue::Text(v) => {
                    *bytes = bytes.checked_add(v.len())?;
                    if *bytes > MAX_ITEMS {
                        return None;
                    }
                    Node::Text(Limited(v.to_vec()))
                }
                SemanticValue::Type(v) => Node::Type(*v),
                SemanticValue::Procedure(v) => Node::Procedure(*v),
                SemanticValue::Resource(v) => Node::Resource(*v),
                SemanticValue::ModifiedInstance(_) => return None,
                SemanticValue::List(entries) => {
                    if entries.len() > MAX_ITEMS {
                        return None;
                    }
                    let mut output = Vec::with_capacity(entries.len());
                    for (key, value) in entries.iter() {
                        let key = match key {
                            Some(key) => Some(push(key, depth + 1, nodes, bytes)?),
                            None => None,
                        };
                        let value = push(value, depth + 1, nodes, bytes)?;
                        output.push((key, value));
                    }
                    Node::List(Limited(output))
                }
            };
            if nodes.len() >= MAX_ITEMS {
                return None;
            }
            let index = nodes.len() as u32;
            nodes.push(node);
            Some(index)
        }
        let mut nodes = Vec::new();
        push(value, 1, &mut nodes, &mut 0)?;
        let result = Self {
            nodes: Limited(nodes),
        };
        result.valid().then_some(result)
    }
    /// Construction/deserialization validates one bounded tree. Taking child
    /// values once preserves order without exponential copies of aliased nodes.
    pub fn restore(&self) -> SemanticValue {
        let mut values: Vec<Option<SemanticValue>> = Vec::with_capacity(self.nodes.0.len());
        for node in &self.nodes.0 {
            let value = match node {
                Node::Null => SemanticValue::Null,
                Node::NumberBits(v) => SemanticValue::NumberBits(*v),
                Node::Text(v) => SemanticValue::Text(Arc::from(v.0.as_slice())),
                Node::Type(v) => SemanticValue::Type(*v),
                Node::Procedure(v) => SemanticValue::Procedure(*v),
                Node::Resource(v) => SemanticValue::Resource(*v),
                Node::List(entries) => SemanticValue::List(
                    entries
                        .0
                        .iter()
                        .map(|(key, value)| {
                            (
                                key.map(|index| {
                                    values[index as usize]
                                        .take()
                                        .expect("validated unique child")
                                }),
                                values[*value as usize]
                                    .take()
                                    .expect("validated unique child"),
                            )
                        })
                        .collect(),
                ),
            };
            values.push(Some(value));
        }
        values.pop().flatten().expect("validated nonempty tree")
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn portable_values_preserve_list_order_keys_and_exact_number_text_bits() {
        let value = SemanticValue::List(Arc::from([
            (
                Some(SemanticValue::Text(Arc::from(&b"key"[..]))),
                SemanticValue::NumberBits(0x80000000),
            ),
            (
                None,
                SemanticValue::List(Arc::from([(None, SemanticValue::Null)])),
            ),
        ]));
        let portable = PortableValue::capture(&value).unwrap();
        assert_eq!(portable.restore(), value);
        assert_eq!(
            portable.restore().canonical_bytes(),
            value.canonical_bytes()
        );
    }
    #[test]
    fn portable_value_bounds_and_duplicate_child_references_decline() {
        let mut deep = SemanticValue::Null;
        for _ in 0..MAX_DEPTH {
            deep = SemanticValue::List(Arc::from([(None, deep)]));
        }
        assert!(PortableValue::capture(&deep).is_none());
        let duplicate = PortableValue {
            nodes: Limited(vec![
                Node::Null,
                Node::List(Limited(vec![(None, 0), (None, 0)])),
            ]),
        };
        assert!(!duplicate.valid());
        let encoded = serde_json::to_vec(&duplicate).unwrap();
        assert!(serde_json::from_slice::<PortableValue>(&encoded).is_err());
        let missing = PortableValue {
            nodes: Limited(vec![Node::Null, Node::Null]),
        };
        assert!(!missing.valid());
        let encoded = serde_json::to_vec(&missing).unwrap();
        assert!(serde_json::from_slice::<PortableValue>(&encoded).is_err());
    }
}
