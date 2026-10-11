//! BYOND map placement projection over captured immutable symbolic models.
//! Not admitted by the cold composer until initializer and descriptor ABI gates pass.
use dm_ir::map::MapAtom;
use dm_ir::SymbolId;
use dm_tree::maps::MapPlan;
use std::collections::BTreeMap;
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InstanceKind {
    Mob,
    Object,
    Turf,
    Area,
}
/// Classification must walk the certified semantic parent hierarchy. Mob paths
/// remain symbolic here; serialization resolves their mob-descriptor namespace.
pub trait InstanceClassifier {
    fn classify(&self, path: SymbolId) -> Result<InstanceKind, String>;
}
#[derive(Clone, Copy, Debug)]
pub struct WorldDefaults {
    pub turf: SymbolId,
    pub area: SymbolId,
    pub minimum_dimensions: [u16; 3],
}
#[derive(Clone, Debug)]
pub struct Instance {
    pub kind: InstanceKind,
    pub atom: MapAtom,
    pub origin: Option<AtomOrigin>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AtomOrigin {
    pub map: usize,
    pub template: usize,
    pub atom: usize,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GridRun {
    pub turf: usize,
    pub area: usize,
    pub copies: u8,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PlacedObject {
    pub offset: u16,
    pub instance: usize,
}
#[derive(Clone, Debug)]
pub struct Projection {
    pub dimensions: [u16; 3],
    /// Local symbolic descriptor indices, never BYOND table identifiers.
    pub instances: Arc<[Instance]>,
    pub grid: Arc<[GridRun]>,
    pub objects: Arc<[PlacedObject]>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Error {
    Verification(String),
    Unsupported(String),
    Invalid { map: usize, message: String },
    Unresolved { path: SymbolId, message: String },
    DimensionOverflow,
    ObjectGapOverflow,
    SizeOverflow,
}
#[derive(Clone)]
struct Cell {
    turf: usize,
    area: usize,
    objects: Vec<usize>,
}
fn classify(classifier: &dyn InstanceClassifier, path: SymbolId) -> Result<InstanceKind, Error> {
    classifier
        .classify(path)
        .map_err(|message| Error::Unresolved { path, message })
}
fn default_instance(instances: &mut Vec<Instance>, kind: InstanceKind, path: SymbolId) -> usize {
    let index = instances.len();
    instances.push(Instance {
        kind,
        atom: MapAtom {
            type_path: path,
            initializer_present: false,
            assignments: Arc::from([]),
        },
        origin: None,
    });
    index
}
fn invalid(map: usize, message: impl Into<String>) -> Error {
    Error::Invalid {
        map,
        message: message.into(),
    }
}
/// Project map files in manifest order. The verified map-stack fixture establishes
/// local z levels stacking above previously placed cells; minimum world dimensions
/// affect final extent only. Duplicate keys and turf/area ambiguity fail closed
/// pending distinguishing contracts, instead of choosing by hash iteration.
pub fn project(
    maps: &[MapPlan],
    defaults: WorldDefaults,
    classifier: &dyn InstanceClassifier,
) -> Result<Projection, Error> {
    if classify(classifier, defaults.turf)? != InstanceKind::Turf
        || classify(classifier, defaults.area)? != InstanceKind::Area
    {
        return Err(Error::Unsupported(
            "world defaults require exact turf/area ancestry".into(),
        ));
    }
    let mut instances = Vec::new();
    let default_turf = default_instance(&mut instances, InstanceKind::Turf, defaults.turf);
    let default_area = default_instance(&mut instances, InstanceKind::Area, defaults.area);
    let empty = Cell {
        turf: default_turf,
        area: default_area,
        objects: Vec::new(),
    };
    // z,y,x keys directly encode the target x-fastest serialization order.
    let mut placed = BTreeMap::<(u64, u64, u64), Cell>::new();
    let mut maximum = [0u64; 3];
    for (map_index, map) in maps.iter().enumerate() {
        let z_offset = maximum[2];
        let width = map
            .model
            .key_width
            .and_then(|value| usize::try_from(value).ok())
            .filter(|width| *width != 0)
            .ok_or_else(|| invalid(map_index, "map requires a uniform nonempty byte key width"))?;
        let mut templates = BTreeMap::<&str, Cell>::new();
        for (template_index, template) in map.model.templates.iter().enumerate() {
            let mut cell = empty.clone();
            let mut seen_turf = false;
            let mut seen_area = false;
            for (atom_index, atom) in template.atoms.iter().enumerate() {
                let kind = classify(classifier, atom.type_path)?;
                let index = instances.len();
                // No deduplication: initializer effects, repeated writes and source
                // origins remain distinguishable until exact initializer policy exists.
                instances.push(Instance {
                    kind,
                    atom: atom.clone(),
                    origin: Some(AtomOrigin {
                        map: map_index,
                        template: template_index,
                        atom: atom_index,
                    }),
                });
                match kind {
                    InstanceKind::Turf => {
                        if seen_turf {
                            return Err(invalid(
                                map_index,
                                "multiple turf atoms require an explicit precedence contract",
                            ));
                        }
                        seen_turf = true;
                        cell.turf = index;
                    }
                    InstanceKind::Area => {
                        if seen_area {
                            return Err(invalid(
                                map_index,
                                "multiple area atoms require an explicit precedence contract",
                            ));
                        }
                        seen_area = true;
                        cell.area = index;
                    }
                    InstanceKind::Object | InstanceKind::Mob => cell.objects.push(index),
                }
            }
            if templates.insert(&template.key, cell).is_some() {
                return Err(invalid(
                    map_index,
                    "duplicate template keys require an explicit precedence contract",
                ));
            }
        }
        for block in map.model.blocks.iter() {
            if block.origin.contains(&0) {
                return Err(invalid(map_index, "map coordinates must be positive"));
            }
            let rows: Vec<_> = block.cells.trim().lines().map(str::trim).collect();
            let row_count = u64::try_from(rows.len()).map_err(|_| Error::SizeOverflow)?;
            for (row_index, row) in rows.iter().enumerate() {
                if !row.is_ascii() {
                    return Err(Error::Unsupported(
                        "non-ASCII grid keys require a verified byte/character contract".into(),
                    ));
                }
                if row.len() % width != 0 {
                    return Err(invalid(
                        map_index,
                        "grid row is not an exact sequence of template keys",
                    ));
                }
                let y = block.origin[1]
                    .checked_add(
                        row_count
                            - 1
                            - u64::try_from(row_index).map_err(|_| Error::SizeOverflow)?,
                    )
                    .ok_or(Error::DimensionOverflow)?;
                let z = block.origin[2]
                    .checked_add(z_offset)
                    .ok_or(Error::DimensionOverflow)?;
                for (column, key) in row.as_bytes().chunks_exact(width).enumerate() {
                    let key = std::str::from_utf8(key)
                        .map_err(|_| invalid(map_index, "invalid grid key"))?;
                    let cell = templates
                        .get(key)
                        .ok_or_else(|| invalid(map_index, format!("unknown grid key {key:?}")))?;
                    let x = block.origin[0]
                        .checked_add(u64::try_from(column).map_err(|_| Error::SizeOverflow)?)
                        .ok_or(Error::DimensionOverflow)?;
                    if placed.insert((z, y, x), cell.clone()).is_some() {
                        return Err(invalid(map_index, "overlapping map cells"));
                    }
                    maximum = [maximum[0].max(x), maximum[1].max(y), maximum[2].max(z)];
                }
            }
        }
    }
    if placed.is_empty() {
        return Err(Error::Unsupported("maps contain no placed cells".into()));
    }
    let mut dimensions = [0u16; 3];
    for axis in 0..3 {
        dimensions[axis] =
            u16::try_from(maximum[axis].max(u64::from(defaults.minimum_dimensions[axis])))
                .map_err(|_| Error::DimensionOverflow)?;
    }
    let [nx, ny, nz] = dimensions.map(u64::from);
    let mut grid = Vec::new();
    let mut objects = Vec::new();
    let mut cursor = 0u64;
    let mut previous_object = 0u64;
    for ((z, y, x), cell) in placed {
        let position = ((z - 1) * ny + (y - 1)) * nx + (x - 1);
        push_runs(&mut grid, default_turf, default_area, position - cursor)?;
        push_runs(&mut grid, cell.turf, cell.area, 1)?;
        for (ordinal, instance) in cell.objects.into_iter().enumerate() {
            let delta = if ordinal == 0 {
                position - previous_object
            } else {
                0
            };
            objects.push(PlacedObject {
                offset: u16::try_from(delta).map_err(|_| Error::ObjectGapOverflow)?,
                instance,
            });
            previous_object = position;
        }
        cursor = position + 1;
    }
    push_runs(&mut grid, default_turf, default_area, nx * ny * nz - cursor)?;
    Ok(Projection {
        dimensions,
        instances: instances.into(),
        grid: grid.into(),
        objects: objects.into(),
    })
}
fn push_runs(
    grid: &mut Vec<GridRun>,
    turf: usize,
    area: usize,
    mut count: u64,
) -> Result<(), Error> {
    if let Some(last) = grid.last_mut() {
        if last.turf == turf && last.area == area {
            let extra = count.min(u64::from(u8::MAX - last.copies));
            last.copies += extra as u8;
            count -= extra;
        }
    }
    let additional = count.div_ceil(u64::from(u8::MAX));
    grid.try_reserve(usize::try_from(additional).map_err(|_| Error::SizeOverflow)?)
        .map_err(|_| Error::SizeOverflow)?;
    while count != 0 {
        let copies = count.min(u64::from(u8::MAX)) as u8;
        grid.push(GridRun { turf, area, copies });
        count -= u64::from(copies);
    }
    Ok(())
}

/// Production classification from the same immutable resolver used by lowering.
/// Exact parent ancestry, rather than lexical path prefixes, determines map kind.
pub struct ResolverClassifier<'a, R: dm_ir::Resolver>(pub &'a R);
impl<R: dm_ir::Resolver> InstanceClassifier for ResolverClassifier<'_, R> {
    fn classify(&self, path: SymbolId) -> Result<InstanceKind, String> {
        use dm_ir::{ResolveQuery, ResolvedMeaning};
        match self.0.resolve(ResolveQuery::Type(path)) {
            ResolvedMeaning::Symbol(actual) if actual == path => {}
            ResolvedMeaning::Unsupported(_) => {
                return Err("map type inventory is incomplete".into())
            }
            _ => return Err("map type is absent or inconsistent".into()),
        }
        let chain = match self.0.resolve(ResolveQuery::Ancestry(path)) {
            ResolvedMeaning::Symbols(chain) => chain,
            ResolvedMeaning::Unsupported(_) => return Err("map ancestry is not certified".into()),
            _ => return Err("map ancestry is absent or inconsistent".into()),
        };
        for ancestor in std::iter::once(path).chain(chain.iter().copied()) {
            for (root, kind) in [
                ("/turf", InstanceKind::Turf),
                ("/area", InstanceKind::Area),
                ("/obj", InstanceKind::Object),
                ("/mob", InstanceKind::Mob),
            ] {
                if ancestor == SymbolId::of(root) {
                    return Ok(kind);
                }
            }
        }
        Err("map atom has no turf/area/object/mob ancestor".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_tree::maps::{plan, CapturedMap};
    use std::path::PathBuf;
    struct Kinds;
    impl InstanceClassifier for Kinds {
        fn classify(&self, path: SymbolId) -> Result<InstanceKind, String> {
            for (name, kind) in [
                ("/turf", InstanceKind::Turf),
                ("/area", InstanceKind::Area),
                ("/obj/a", InstanceKind::Object),
                ("/obj/b", InstanceKind::Object),
                ("/mob", InstanceKind::Mob),
            ] {
                if path == SymbolId::of(name) {
                    return Ok(kind);
                }
            }
            Err("uncertified hierarchy".into())
        }
    }
    fn captured(source: &str) -> MapPlan {
        plan(CapturedMap {
            path: Arc::new(PathBuf::from("probe.dmm")),
            include_occurrence: 1,
            source: Arc::from(source),
        })
        .unwrap()
    }
    fn defaults() -> WorldDefaults {
        WorldDefaults {
            turf: SymbolId::of("/turf"),
            area: SymbolId::of("/area"),
            minimum_dimensions: [1, 1, 1],
        }
    }
    #[test]
    fn top_down_rows_project_to_x_fastest_object_offsets() {
        let map=captured("\"a\"=(/obj/a,/obj/b,/turf,/area)\n\"b\"=(/obj/b,/obj/a,/turf,/area)\n(1,1,1)={\"\nab\nba\n\"}");
        let result = project(&[map], defaults(), &Kinds).unwrap();
        assert_eq!(result.dimensions, [2, 2, 1]);
        let paths: Vec<_> = result
            .objects
            .iter()
            .map(|object| result.instances[object.instance].atom.type_path)
            .collect();
        assert_eq!(
            paths,
            ["/obj/b", "/obj/a", "/obj/a", "/obj/b", "/obj/a", "/obj/b", "/obj/b", "/obj/a"]
                .map(SymbolId::of)
        );
        assert_eq!(
            result
                .objects
                .iter()
                .map(|object| object.offset)
                .collect::<Vec<_>>(),
            [0, 0, 1, 0, 1, 0, 1, 0]
        );
    }
    #[test]
    fn separate_files_stack_local_z_and_preserve_minimum_extent() {
        let a = captured("\"a\"=(/mob,/turf,/area)\n(1,1,1)={\"a\"}");
        let mut config = defaults();
        config.minimum_dimensions = [1, 1, 3];
        let result = project(&[a.clone(), a], config, &Kinds).unwrap();
        assert_eq!(result.dimensions, [1, 1, 3]);
        assert_eq!(
            result
                .objects
                .iter()
                .map(|object| object.offset)
                .collect::<Vec<_>>(),
            [0, 1]
        );
        assert!(result
            .objects
            .iter()
            .all(|object| result.instances[object.instance].kind == InstanceKind::Mob));
        assert_eq!(
            result
                .grid
                .iter()
                .map(|run| u64::from(run.copies))
                .sum::<u64>(),
            3
        );
    }
    #[test]
    fn sparse_holes_and_run_limits_are_exact_without_cell_materialization() {
        let mut runs = Vec::new();
        push_runs(&mut runs, 0, 1, 511).unwrap();
        assert_eq!(
            runs.iter().map(|run| run.copies).collect::<Vec<_>>(),
            [255, 255, 1]
        );
        push_runs(&mut runs, 0, 1, 2).unwrap();
        assert_eq!(runs[2].copies, 3);
        let map = captured("\"a\"=(/obj/a)\n(3,1,1)={\"a\"}");
        let result = project(&[map], defaults(), &Kinds).unwrap();
        assert_eq!(result.objects[0].offset, 2);
        assert_eq!(
            result.grid.as_ref(),
            [GridRun {
                turf: 0,
                area: 1,
                copies: 3
            }]
        );
    }
    #[test]
    fn unchecked_precedence_and_large_object_gaps_fail_closed() {
        let duplicate = captured("\"a\"=(/obj/a)\n\"a\"=(/obj/b)\n(1,1,1)={\"a\"}");
        assert!(matches!(
            project(&[duplicate], defaults(), &Kinds),
            Err(Error::Invalid { .. })
        ));
        let map = captured("\"a\"=(/obj/a)\n(1,2,1)={\"a\"}");
        let mut config = defaults();
        config.minimum_dimensions = [65535, 3, 1];
        // First object delta65535 fits; at row3 it cannot fit u16.
        assert!(project(&[map], config, &Kinds).is_ok());
        let map = captured("\"a\"=(/obj/a)\n(2,2,1)={\"a\"}");
        assert!(matches!(
            project(&[map], config, &Kinds),
            Err(Error::ObjectGapOverflow)
        ));
    }
}
