//! Pure offline map and DMI tooling. This crate does not link to BYOND or Verdigris.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::Path;

pub mod sprite;
pub mod network;
pub mod render;

#[cfg(target_arch = "wasm32")]
mod browser_api {
    use super::network;
    use std::alloc::{alloc, dealloc, Layout};

    #[no_mangle]
    pub extern "C" fn mapcore_alloc(len: usize) -> *mut u8 {
        unsafe { alloc(Layout::array::<u8>(len.max(1)).unwrap()) }
    }

    #[no_mangle]
    pub unsafe extern "C" fn mapcore_free(ptr: *mut u8, len: usize) {
        if !ptr.is_null() {
            dealloc(ptr, Layout::array::<u8>(len.max(1)).unwrap());
        }
    }

    #[no_mangle]
    pub unsafe extern "C" fn mapcore_route(ptr: *const u8, len: usize) -> *mut u8 {
        let input = std::slice::from_raw_parts(ptr, len);
        let result = serde_json::from_slice(input)
            .map_err(|error| error.to_string())
            .and_then(network::route);
        let output = match result {
            Ok(diff) => serde_json::to_vec(&diff).unwrap(),
            Err(error) => serde_json::to_vec(&serde_json::json!({"error": error})).unwrap(),
        };
        let total = output.len() + 4;
        let result = mapcore_alloc(total);
        if result.is_null() { return result; }
        std::ptr::copy_nonoverlapping((output.len() as u32).to_le_bytes().as_ptr(), result, 4);
        std::ptr::copy_nonoverlapping(output.as_ptr(), result.add(4), output.len());
        result
    }
}

pub type Position = (u32, u32, u32);

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Map {
    pub size: Position,
    pub key_length: usize,
    pub dictionary: BTreeMap<String, Vec<String>>,
    pub grid: BTreeMap<Position, String>,
}

impl Map {
    pub fn read(path: impl AsRef<Path>) -> Result<Self, String> {
        let source = fs::read_to_string(path).map_err(|e| e.to_string())?;
        Self::parse(&source)
    }

    pub fn parse(source: &str) -> Result<Self, String> {
        let mut dictionary = BTreeMap::new();
        let mut grid = BTreeMap::new();
        let mut size = (0, 0, 0);
        let mut key_length = 0;
        let mut lines = source.lines().peekable();
        while let Some(line) = lines.next() {
            let line = line.trim();
            if line.starts_with('"') && line.contains(" = (") {
                let end = line[1..].find('"').ok_or("Invalid tile key")? + 1;
                let key = &line[1..end];
                if key_length == 0 {
                    key_length = key.len();
                }
                if key.len() != key_length {
                    return Err("Mixed key lengths".into());
                }
                let mut body = String::new();
                let mut depth = 1i32;
                let mut quoted = false;
                let mut escaped = false;
                for ch in line[end + 1..]
                    .split_once(" = (")
                    .ok_or("Invalid tile definition")?
                    .1
                    .chars()
                {
                    if ch == ')' && depth == 1 && !quoted {
                        depth = 0;
                        break;
                    }
                    body.push(ch);
                    match ch {
                        '"' if !escaped => quoted = !quoted,
                        '(' if !quoted => depth += 1,
                        ')' if !quoted => depth -= 1,
                        _ => {}
                    }
                    escaped = ch == '\\' && !escaped;
                }
                while depth > 0 {
                    let next = lines.next().ok_or("Unclosed tile definition")?;
                    body.push('\n');
                    for ch in next.chars() {
                        if ch == ')' && depth == 1 && !quoted {
                            depth = 0;
                            break;
                        }
                        body.push(ch);
                        match ch {
                            '"' if !escaped => quoted = !quoted,
                            '(' if !quoted => depth += 1,
                            ')' if !quoted => depth -= 1,
                            _ => {}
                        }
                        escaped = ch == '\\' && !escaped;
                    }
                }
                let atoms = split_atoms(&body)?;
                if atoms.iter().filter(|a| a.starts_with("/turf/")).count() != 1
                    || atoms.iter().filter(|a| a.starts_with("/area/")).count() != 1
                {
                    return Err(format!("Tile key {key} must have one turf and one area"));
                }
                dictionary.insert(key.to_owned(), atoms);
            } else if line.starts_with('(') && line.contains(" = {\"") {
                let end = line.find(')').ok_or("Invalid grid block")?;
                let coordinates: Vec<u32> = line[1..end]
                    .split(',')
                    .map(str::trim)
                    .map(str::parse)
                    .collect::<Result<_, _>>()
                    .map_err(|_| "Invalid grid coordinates")?;
                if coordinates.len() != 3 {
                    return Err("Grid coordinates need x,y,z".into());
                }
                let (x0, y0, z) = (coordinates[0], coordinates[1], coordinates[2]);
                let mut rows = Vec::new();
                let rest = line.split_once("= {\"").unwrap().1;
                if !rest.is_empty() {
                    rows.push(rest.to_owned());
                }
                loop {
                    let row = lines.next().ok_or("Unclosed grid block")?.trim();
                    if row == "\"}" {
                        break;
                    }
                    if let Some(prefix) = row.strip_suffix("\"}") {
                        if !prefix.is_empty() {
                            rows.push(prefix.to_owned());
                        }
                        break;
                    }
                    if !row.is_empty() {
                        rows.push(row.to_owned());
                    }
                }
                if rows.is_empty() {
                    return Err("Empty grid block".into());
                }
                let width = rows[0].len() / key_length;
                for (row_index, row) in rows.iter().enumerate() {
                    if row.len() != width * key_length {
                        return Err("Grid row has uneven keys".into());
                    }
                    for column in 0..width {
                        let key = row[column * key_length..(column + 1) * key_length].to_owned();
                        let position = (
                            x0 + column as u32,
                            y0 + rows.len() as u32 - row_index as u32 - 1,
                            z,
                        );
                        grid.insert(position, key);
                        size.0 = size.0.max(position.0);
                        size.1 = size.1.max(position.1);
                        size.2 = size.2.max(position.2);
                    }
                }
            }
        }
        if dictionary.is_empty() || grid.is_empty() {
            return Err("Map has no tiles or grid".into());
        }
        if grid.values().any(|key| !dictionary.contains_key(key)) {
            return Err("Grid references an undefined key".into());
        }
        Ok(Self {
            size,
            key_length,
            dictionary,
            grid,
        })
    }

    pub fn tile(&self, position: Position) -> Option<&[String]> {
        self.grid
            .get(&position)
            .and_then(|key| self.dictionary.get(key))
            .map(Vec::as_slice)
    }

    pub fn set_tile(&mut self, position: Position, atoms: Vec<String>) -> Result<(), String> {
        if !self.grid.contains_key(&position) {
            return Err("Position outside map".into());
        }
        if atoms.iter().filter(|a| a.starts_with("/turf/")).count() != 1
            || atoms.iter().filter(|a| a.starts_with("/area/")).count() != 1
        {
            return Err("A tile needs one turf and one area".into());
        }
        let key = self
            .dictionary
            .iter()
            .find(|(_, value)| **value == atoms)
            .map(|(key, _)| key.clone())
            .unwrap_or_else(|| {
                let mut number = 0;
                loop {
                    let candidate = key_from_number(number, self.key_length);
                    if !self.dictionary.contains_key(&candidate) {
                        self.dictionary.insert(candidate.clone(), atoms.clone());
                        break candidate;
                    }
                    number += 1;
                }
            });
        self.grid.insert(position, key);
        Ok(())
    }

    pub fn write_tgm(&self) -> Result<String, String> {
        let mut output = "//MAP CONVERTED BY dmm2tgm.py THIS HEADER COMMENT PREVENTS RECONVERSION, DO NOT REMOVE\n".to_owned();
        for (key, atoms) in &self.dictionary {
            output.push_str(&format!("\"{key}\" = (\n"));
            for (index, atom) in atoms.iter().enumerate() {
                output.push_str(&format_atom(atom));
                output.push_str(if index + 1 == atoms.len() {
                    ")\n"
                } else {
                    ",\n"
                });
            }
        }
        for z in 1..=self.size.2 {
            output.push('\n');
            for x in 1..=self.size.0 {
                output.push_str(&format!("({x},1,{z}) = {{\"\n"));
                for y in (1..=self.size.1).rev() {
                    output.push_str(self.grid.get(&(x, y, z)).ok_or("Map grid is incomplete")?);
                    output.push('\n');
                }
                output.push_str("\"}\n");
            }
        }
        Ok(output)
    }

    pub fn used_atom_paths(&self) -> HashMap<String, usize> {
        let mut result = HashMap::new();
        for key in self.grid.values() {
            if let Some(atoms) = self.dictionary.get(key) {
                for atom in atoms {
                    let base = atom.split('{').next().unwrap_or(atom).to_owned();
                    *result.entry(base).or_insert(0) += 1;
                }
            }
        }
        result
    }
}

fn key_from_number(mut value: usize, len: usize) -> String {
    let chars = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    let mut key = vec![b'a'; len];
    for slot in key.iter_mut().rev() {
        *slot = chars[value % chars.len()];
        value /= chars.len();
    }
    String::from_utf8(key).unwrap()
}

fn split_atoms(body: &str) -> Result<Vec<String>, String> {
    let mut atoms = Vec::new();
    let mut current = String::new();
    let (mut braces, mut parens, mut quoted, mut escaped) = (0i32, 0i32, false, false);
    for ch in body.chars() {
        match ch {
            '"' if !escaped => quoted = !quoted,
            '{' if !quoted => braces += 1,
            '}' if !quoted => braces -= 1,
            '(' if !quoted => parens += 1,
            ')' if !quoted => parens -= 1,
            ',' if !quoted && braces == 0 && parens == 0 => {
                let atom = compact_atom(&current);
                if !atom.is_empty() {
                    atoms.push(atom);
                }
                current.clear();
                continue;
            }
            _ => {}
        }
        current.push(ch);
        escaped = ch == '\\' && !escaped;
    }
    if braces != 0 || parens != 0 || quoted {
        return Err("Unbalanced atom value".into());
    }
    let atom = compact_atom(&current);
    if !atom.is_empty() {
        atoms.push(atom);
    }
    Ok(atoms)
}

fn compact_atom(atom: &str) -> String {
    let atom = atom.trim();
    if let Some((path, edits)) = atom.split_once('{') {
        let edits = split_edits(edits.trim_end_matches('}')).join("; ");
        format!("{}{{{}}}", path.trim(), edits)
    } else {
        atom.to_owned()
    }
}

fn format_atom(atom: &str) -> String {
    if let Some((path, edits)) = atom.split_once('{') {
        let edits = split_edits(edits.trim_end_matches('}')).join(";\n\t");
        format!("{}{{\n\t{}\n\t}}", path.trim(), edits)
    } else {
        atom.to_owned()
    }
}

fn split_edits(source: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut value = String::new();
    let (mut quoted, mut escaped, mut parens) = (false, false, 0i32);
    for ch in source.chars() {
        match ch {
            '"' if !escaped => quoted = !quoted,
            '(' if !quoted => parens += 1,
            ')' if !quoted => parens -= 1,
            ';' if !quoted && parens == 0 => {
                if !value.trim().is_empty() {
                    parts.push(value.trim().to_owned());
                }
                value.clear();
                continue;
            }
            _ => {}
        }
        value.push(ch);
        escaped = ch == '\\' && !escaped;
    }
    if !value.trim().is_empty() {
        parts.push(value.trim().to_owned());
    }
    parts
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixture_round_trip() {
        let fixture =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../maps/templates/unit_tests.dmm");
        let map = Map::read(fixture).unwrap();
        let output = map.write_tgm().unwrap();
        let reread = Map::parse(&output).unwrap();
        assert_eq!(map.size, reread.size);
        assert_eq!(map.grid, reread.grid);
        assert_eq!(map.dictionary, reread.dictionary);
    }

    #[test]
    fn variable_strings_keep_semicolons() {
        let atom = "/obj/item/paper{info = \"a;b\"; name = \"letter\"}";
        assert_eq!(compact_atom(&format_atom(atom)), atom);
    }

    #[test]
    fn parses_every_repository_map() {
        let maps = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../maps");
        let mut pending = vec![maps];
        let mut count = 0;
        while let Some(directory) = pending.pop() {
            for entry in fs::read_dir(directory).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    pending.push(path);
                } else if path.extension().is_some_and(|ext| ext == "dmm") {
                    Map::read(&path).unwrap_or_else(|error| panic!("{}: {error}", path.display()));
                    count += 1;
                }
            }
        }
        assert!(count > 100);
    }
}
