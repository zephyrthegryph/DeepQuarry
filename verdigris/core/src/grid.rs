//! Cell addressing for BYOND's turf grid (`rust_architecture.md` §4.6).
//!
//! A [`CellId`] is BYOND's zero-based turf ref number:
//! `(x - 1) + (y - 1) * max_x + (z - 1) * max_x * max_y`. Grid cells are not
//! entities; everything that lives on the grid (fields, network occupancy)
//! is keyed by `CellId`.
//!
//! - [`GridDims`] is the bounds-checked arithmetic.
//! - [`Dir`] is a BYOND direction value (`NORTH`..`DOWN` bits), which is also
//!   a set of faces: a blocked-face mask is a `Dir`.
//! - [`ChunkedLayer`] stores a per-cell value in 16x16 chunks that are only
//!   allocated once a cell in them holds a non-default value. Chunks are
//!   shared copy-on-write, so cloning a layer (the driver's per-frame
//!   snapshot for worker readers) copies pointers, and every chunk carries a
//!   revision so readers can wake exactly what changed.
//! - [`Grid`] is the one owner of every block layer ([`BlockKind`]: air,
//!   heat, movement, opacity, radiation) plus the z-level links multi-z
//!   steps follow ([`Grid::step`]). Fields read their blocked faces from it
//!   (`FieldKind::BLOCK`); nothing else keeps a mask copy.

/// One of the six grid faces. The discriminant is the bit position of the same
/// direction in BYOND's `NORTH`/`SOUTH`/`EAST`/`WEST`/`UP`/`DOWN` flags.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum Face {
    North = 0,
    South = 1,
    East = 2,
    West = 3,
    Up = 4,
    Down = 5,
}

impl Face {
    /// This face's bit in a BYOND direction flag / [`Dir`].
    #[must_use]
    pub const fn bit(self) -> u8 {
        1 << self as u8
    }

    #[must_use]
    pub const fn opposite(self) -> Face {
        match self {
            Face::North => Face::South,
            Face::South => Face::North,
            Face::East => Face::West,
            Face::West => Face::East,
            Face::Up => Face::Down,
            Face::Down => Face::Up,
        }
    }

    pub const ALL: [Face; 6] = [
        Face::North,
        Face::South,
        Face::East,
        Face::West,
        Face::Up,
        Face::Down,
    ];

    /// The face for a BYOND direction bit position (0..6).
    #[must_use]
    pub const fn from_bit_index(bit: u8) -> Option<Face> {
        match bit {
            0 => Some(Face::North),
            1 => Some(Face::South),
            2 => Some(Face::East),
            3 => Some(Face::West),
            4 => Some(Face::Up),
            5 => Some(Face::Down),
            _ => None,
        }
    }
}

/// World dimensions. Every neighbour lookup is bounds-checked: a cell on the
/// east edge has no east neighbour (it does not wrap to the next row), and a
/// cell on the top row has no north neighbour (it does not step into the next
/// z-level).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GridDims {
    max_x: u32,
    max_y: u32,
    max_z: u32,
}

impl GridDims {
    /// `None` if any dimension is zero or the grid does not fit a `u32` index.
    #[must_use]
    pub fn new(max_x: u32, max_y: u32, max_z: u32) -> Option<Self> {
        if max_x == 0 || max_y == 0 || max_z == 0 {
            return None;
        }
        max_x.checked_mul(max_y)?.checked_mul(max_z)?;
        Some(Self {
            max_x,
            max_y,
            max_z,
        })
    }

    /// Dimensions when only the plane size is known. The z range is as deep as
    /// a `u32` index allows, so `Up` is bounded only by the index space.
    #[must_use]
    pub fn planar(max_x: u32, max_y: u32) -> Option<Self> {
        let layer = max_x.checked_mul(max_y)?;
        if layer == 0 {
            return None;
        }
        Self::new(max_x, max_y, u32::MAX / layer)
    }

    #[must_use]
    pub const fn max_x(self) -> u32 {
        self.max_x
    }

    #[must_use]
    pub const fn max_y(self) -> u32 {
        self.max_y
    }

    #[must_use]
    pub const fn max_z(self) -> u32 {
        self.max_z
    }

    /// Index of zero-based (x, y, z), or `None` outside the grid.
    #[must_use]
    pub const fn index(self, x: u32, y: u32, z: u32) -> Option<u32> {
        if x >= self.max_x || y >= self.max_y || z >= self.max_z {
            return None;
        }
        Some(x + y * self.max_x + z * self.layer_len())
    }

    #[must_use]
    pub const fn layer_len(self) -> u32 {
        self.max_x * self.max_y
    }

    /// Zero-based (x, y, z) of an index, or `None` if it is outside the grid.
    #[must_use]
    pub const fn coords(self, index: u32) -> Option<(u32, u32, u32)> {
        let layer = self.layer_len();
        let z = index / layer;
        if z >= self.max_z {
            return None;
        }
        let in_layer = index % layer;
        Some((in_layer % self.max_x, in_layer / self.max_x, z))
    }

    /// The index of the cell across `face`, or `None` at the grid edge.
    #[must_use]
    pub const fn neighbor(self, index: u32, face: Face) -> Option<u32> {
        let Some((x, y, z)) = self.coords(index) else {
            return None;
        };
        match face {
            Face::North if y + 1 < self.max_y => Some(index + self.max_x),
            Face::South if y > 0 => Some(index - self.max_x),
            Face::East if x + 1 < self.max_x => Some(index + 1),
            Face::West if x > 0 => Some(index - 1),
            Face::Up if z + 1 < self.max_z => Some(index + self.layer_len()),
            Face::Down if z > 0 => Some(index - self.layer_len()),
            _ => None,
        }
    }
}

/// Cells per chunk edge.
pub const CHUNK_EDGE: u32 = 16;
/// Cells per chunk.
pub const CHUNK_CELLS: usize = (CHUNK_EDGE * CHUNK_EDGE) as usize;

/// A per-cell value stored in 16x16 chunks. Chunks whose cells all hold
/// `T::default()` are never allocated, so pure space costs one pointer per
/// chunk. Z-levels are allocated on first write, so [`GridDims::planar`]
/// grids are fine.
#[derive(Clone, Debug)]
pub struct ChunkedLayer<T> {
    dims: GridDims,
    chunks_x: u32,
    chunks_per_z: usize,
    /// `levels[z][chunk]`, shared copy-on-write between clones.
    levels: Vec<Vec<Option<std::sync::Arc<[T; CHUNK_CELLS]>>>>,
    /// `revisions[z][chunk]`: the layer revision of the chunk's last change.
    revisions: Vec<Vec<u64>>,
    revision: u64,
}

impl<T: Copy + Default + PartialEq> ChunkedLayer<T> {
    #[must_use]
    pub fn new(dims: GridDims) -> Self {
        let chunks_x = dims.max_x.div_ceil(CHUNK_EDGE);
        let chunks_y = dims.max_y.div_ceil(CHUNK_EDGE);
        Self {
            dims,
            chunks_x,
            chunks_per_z: (chunks_x * chunks_y) as usize,
            levels: Vec::new(),
            revisions: Vec::new(),
            revision: 0,
        }
    }

    /// Bumped by every write that changed a value.
    #[must_use]
    pub const fn revision(&self) -> u64 {
        self.revision
    }

    /// The layer revision at which the chunk holding `index` last changed
    /// (0: never).
    #[must_use]
    pub fn chunk_revision(&self, index: u32) -> u64 {
        let Some((z, chunk, _)) = self.locate(index) else {
            return 0;
        };
        self.revisions.get(z).and_then(|l| l.get(chunk)).copied().unwrap_or(0)
    }

    fn touch(&mut self, z: usize, chunk: usize) {
        self.revision += 1;
        if self.revisions.len() <= z {
            self.revisions.resize_with(z + 1, Vec::new);
        }
        let level = &mut self.revisions[z];
        if level.len() < self.chunks_per_z {
            level.resize(self.chunks_per_z, 0);
        }
        level[chunk] = self.revision;
    }

    #[must_use]
    pub const fn dims(&self) -> GridDims {
        self.dims
    }

    /// (z, chunk in level, cell in chunk), or `None` outside the grid.
    fn locate(&self, index: u32) -> Option<(usize, usize, usize)> {
        let (x, y, z) = self.dims.coords(index)?;
        let chunk = (y / CHUNK_EDGE) * self.chunks_x + x / CHUNK_EDGE;
        let cell = (y % CHUNK_EDGE) * CHUNK_EDGE + x % CHUNK_EDGE;
        Some((z as usize, chunk as usize, cell as usize))
    }

    /// The value at `index`; `None` only if `index` is outside the grid.
    #[must_use]
    pub fn get(&self, index: u32) -> Option<T> {
        let (z, chunk, cell) = self.locate(index)?;
        Some(
            self.levels
                .get(z)
                .and_then(|level| level.get(chunk)?.as_ref())
                .map_or_else(T::default, |c| c[cell]),
        )
    }

    /// Writes `value`; returns `false` (and does nothing) outside the grid.
    /// Writing the default into an unallocated chunk allocates nothing.
    pub fn set(&mut self, index: u32, value: T) -> bool {
        let Some((z, chunk, cell)) = self.locate(index) else {
            return false;
        };
        if self.levels.len() <= z {
            if value == T::default() {
                return true;
            }
            self.levels.resize_with(z + 1, Vec::new);
        }
        let level = &mut self.levels[z];
        if level.is_empty() {
            if value == T::default() {
                return true;
            }
            level.resize_with(self.chunks_per_z, || None);
        }
        let changed = match &mut level[chunk] {
            Some(cells) => {
                if cells[cell] == value {
                    false
                } else {
                    std::sync::Arc::make_mut(cells)[cell] = value;
                    true
                }
            }
            slot @ None => {
                if value == T::default() {
                    false
                } else {
                    let mut cells = [T::default(); CHUNK_CELLS];
                    cells[cell] = value;
                    *slot = Some(std::sync::Arc::new(cells));
                    true
                }
            }
        };
        if changed {
            self.touch(z, chunk);
        }
        true
    }

    /// Chunks currently allocated.
    #[must_use]
    pub fn allocated_chunks(&self) -> usize {
        self.levels.iter().flatten().filter(|c| c.is_some()).count()
    }

    /// Frees chunks that have returned to all-default.
    pub fn compact(&mut self) {
        for chunk in self.levels.iter_mut().flatten() {
            if chunk
                .as_ref()
                .is_some_and(|cells| cells.iter().all(|v| *v == T::default()))
            {
                *chunk = None;
            }
        }
    }

    /// Bytes held by allocated chunks, for the allocator-tag report.
    #[must_use]
    pub fn reserved_bytes(&self) -> usize {
        self.allocated_chunks() * size_of::<[T; CHUNK_CELLS]>()
            + self
                .levels
                .iter()
                .map(|l| l.capacity() * size_of::<Option<std::sync::Arc<[T; CHUNK_CELLS]>>>())
                .sum::<usize>()
    }
}

/// A BYOND direction value: `NORTH` 1, `SOUTH` 2, `EAST` 4, `WEST` 8, `UP`
/// 16, `DOWN` 32 (the same bits as [`Face::bit`]). A diagonal is two planar
/// bits; a set of blocked faces is also a `Dir`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Dir(pub u8);

impl Dir {
    pub const NONE: Dir = Dir(0);
    pub const NORTH: Dir = Dir(1);
    pub const SOUTH: Dir = Dir(2);
    pub const EAST: Dir = Dir(4);
    pub const WEST: Dir = Dir(8);
    pub const UP: Dir = Dir(16);
    pub const DOWN: Dir = Dir(32);
    /// Every face.
    pub const ALL: Dir = Dir(0b11_1111);

    #[must_use]
    pub const fn from_face(face: Face) -> Self {
        Dir(face.bit())
    }

    #[must_use]
    pub const fn contains(self, face: Face) -> bool {
        self.0 & face.bit() != 0
    }

    #[must_use]
    pub const fn with(self, face: Face) -> Self {
        Dir(self.0 | face.bit())
    }

    #[must_use]
    pub const fn without(self, face: Face) -> Self {
        Dir(self.0 & !face.bit())
    }

    #[must_use]
    pub const fn union(self, other: Dir) -> Self {
        Dir(self.0 | other.0)
    }

    #[must_use]
    pub const fn intersects(self, other: Dir) -> bool {
        self.0 & other.0 != 0
    }

    #[must_use]
    pub const fn is_empty(self) -> bool {
        self.0 == 0
    }

    /// `GLOB.reverse_dir`: every face flipped.
    #[must_use]
    pub const fn reverse(self) -> Self {
        let mut r = 0;
        let mut bit = 0;
        while bit < 6 {
            if self.0 & (1 << bit) != 0 {
                r |= 1 << (bit ^ 1);
            }
            bit += 1;
        }
        Dir(r)
    }

    /// The planar part (`NORTH`/`SOUTH`/`EAST`/`WEST` bits).
    #[must_use]
    pub const fn planar(self) -> Self {
        Dir(self.0 & 0b1111)
    }

    /// Two planar bits set (`NORTHEAST`, ...).
    #[must_use]
    pub const fn is_diagonal(self) -> bool {
        let planar = self.0 & 0b1111;
        planar != 0 && planar & (planar - 1) != 0
    }

    /// The faces this direction names, in [`Face::ALL`] order.
    pub fn faces(self) -> impl Iterator<Item = Face> {
        Face::ALL.into_iter().filter(move |f| self.contains(*f))
    }
}

/// The kinds of blocking a cell face can have; one layer each.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum BlockKind {
    Air = 0,
    Heat = 1,
    Movement = 2,
    Opacity = 3,
    Radiation = 4,
}

impl BlockKind {
    pub const COUNT: usize = 5;
    pub const ALL: [BlockKind; Self::COUNT] = [
        BlockKind::Air,
        BlockKind::Heat,
        BlockKind::Movement,
        BlockKind::Opacity,
        BlockKind::Radiation,
    ];
}

/// Grid addressing plus one blocked-direction layer per [`BlockKind`].
/// Every neighbour access goes through [`GridDims::neighbor`], so nothing
/// wraps across a row or z-level edge.
#[derive(Clone, Debug)]
pub struct Grid {
    dims: GridDims,
    blocks: [ChunkedLayer<Dir>; BlockKind::COUNT],
    /// Per zero-based z: the level `UP`/`DOWN` lead to, if linked. Empty:
    /// every level links to its numeric neighbours.
    z_links: Vec<(Option<u32>, Option<u32>)>,
    links_revision: u64,
}

/// A grid cell: BYOND's zero-based turf index ([`GridDims::index`]).
pub type CellId = u32;

impl Grid {
    #[must_use]
    pub fn new(dims: GridDims) -> Self {
        Self {
            dims,
            blocks: std::array::from_fn(|_| ChunkedLayer::new(dims)),
            z_links: Vec::new(),
            links_revision: 0,
        }
    }

    /// Links zero-based level `z` to the levels `UP` and `DOWN` reach (a
    /// station deck above another need not be `z + 1`). Once any link is
    /// set, an unlinked vertical step leads nowhere.
    pub fn set_z_link(&mut self, z: u32, up: Option<u32>, down: Option<u32>) {
        let z = z as usize;
        if self.z_links.len() <= z {
            self.z_links.resize(z + 1, (None, None));
        }
        if self.z_links[z] != (up, down) {
            self.z_links[z] = (up, down);
            self.links_revision += 1;
        }
    }

    /// The cell one step from `cell` in `dir`: planar bits move within the
    /// level (a diagonal moves on both axes), `UP`/`DOWN` follow the z links.
    /// `None` off the grid or across an unlinked level.
    #[must_use]
    pub fn step(&self, cell: CellId, dir: Dir) -> Option<CellId> {
        let mut at = cell;
        for face in dir.planar().faces() {
            at = self.dims.neighbor(at, face)?;
        }
        let vertical = [(Face::Up, true), (Face::Down, false)];
        for (face, up) in vertical {
            if !dir.contains(face) {
                continue;
            }
            if self.z_links.is_empty() {
                at = self.dims.neighbor(at, face)?;
                continue;
            }
            let (x, y, z) = self.dims.coords(at)?;
            let link = self.z_links.get(z as usize).copied().unwrap_or((None, None));
            let target = if up { link.0 } else { link.1 }?;
            at = self.dims.index(x, y, target)?;
        }
        Some(at)
    }

    #[must_use]
    pub const fn dims(&self) -> GridDims {
        self.dims
    }

    #[must_use]
    pub fn neighbor(&self, index: u32, face: Face) -> Option<u32> {
        self.dims.neighbor(index, face)
    }

    #[must_use]
    pub fn layer(&self, kind: BlockKind) -> &ChunkedLayer<Dir> {
        &self.blocks[kind as usize]
    }

    /// Faces of `index` blocked for `kind` (none outside the grid).
    #[must_use]
    pub fn blocked(&self, kind: BlockKind, index: u32) -> Dir {
        self.layer(kind).get(index).unwrap_or_default()
    }

    /// The layer revision at which `index`'s chunk last changed for `kind`
    /// (a field wakes the chunks whose revision moved).
    #[must_use]
    pub fn blocked_revision(&self, kind: BlockKind, index: u32) -> u64 {
        self.layer(kind).chunk_revision(index)
    }

    /// Bumped by any change to any block layer.
    #[must_use]
    pub fn revision(&self) -> u64 {
        self.blocks.iter().map(ChunkedLayer::revision).sum::<u64>() + self.links_revision
    }

    /// Returns `false` outside the grid.
    pub fn set_blocked(&mut self, kind: BlockKind, index: u32, mask: Dir) -> bool {
        self.blocks[kind as usize].set(index, Dir(mask.0 & Dir::ALL.0))
    }

    /// The neighbour across `face` if it exists and neither side blocks the
    /// shared face for `kind`.
    #[must_use]
    pub fn open_neighbor(&self, kind: BlockKind, index: u32, face: Face) -> Option<u32> {
        let other = self.dims.neighbor(index, face)?;
        let layer = self.layer(kind);
        let here = layer.get(index).unwrap_or_default();
        let there = layer.get(other).unwrap_or_default();
        (!here.contains(face) && !there.contains(face.opposite())).then_some(other)
    }

    /// Open neighbours of `index` for `kind`.
    pub fn open_neighbors(
        &self,
        kind: BlockKind,
        index: u32,
    ) -> impl Iterator<Item = (Face, u32)> + '_ {
        Face::ALL
            .into_iter()
            .filter_map(move |face| self.open_neighbor(kind, index, face).map(|n| (face, n)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    fn dims() -> GridDims {
        GridDims::new(4, 3, 2).unwrap()
    }

    fn index(x: u32, y: u32, z: u32) -> u32 {
        x + y * 4 + z * 12
    }

    #[test]
    fn dir_math_matches_byond() {
        assert_eq!(Dir::NORTH.union(Dir::EAST).reverse(), Dir::SOUTH.union(Dir::WEST));
        assert_eq!(Dir::UP.reverse(), Dir::DOWN);
        assert!(Dir::NORTH.union(Dir::EAST).is_diagonal());
        assert!(!Dir::NORTH.is_diagonal());
        assert_eq!(Dir::from_face(Face::West), Dir::WEST);
    }

    #[test]
    fn step_moves_diagonally_and_follows_z_links() {
        let mut grid = Grid::new(GridDims::new(4, 4, 3).unwrap());
        let dims = grid.dims();
        let at = dims.index(1, 1, 0).unwrap();
        assert_eq!(grid.step(at, Dir::NORTH.union(Dir::EAST)), dims.index(2, 2, 0));
        assert_eq!(grid.step(at, Dir::UP), dims.index(1, 1, 1), "no links: numeric neighbour");
        grid.set_z_link(0, Some(2), None);
        assert_eq!(grid.step(at, Dir::UP), dims.index(1, 1, 2), "follows the link");
        assert_eq!(grid.step(at, Dir::DOWN), None, "unlinked");
        let before = grid.revision();
        grid.set_blocked(BlockKind::Air, at, Dir::ALL);
        assert!(grid.revision() > before);
        assert!(grid.blocked_revision(BlockKind::Air, at) > 0);
        let snapshot = grid.clone();
        assert_eq!(snapshot.blocked(BlockKind::Air, at), Dir::ALL, "clones share chunks");
    }

    #[test]
    fn rejects_empty_and_overflowing_grids() {
        assert!(GridDims::new(0, 3, 1).is_none());
        assert!(GridDims::new(u32::MAX, 2, 1).is_none());
        assert!(GridDims::planar(0, 5).is_none());
    }

    #[test]
    fn interior_cell_has_all_six_neighbours() {
        let dims = GridDims::new(4, 3, 3).unwrap();
        let centre = 1 + 4 + 12;
        let found = Face::ALL.map(|face| dims.neighbor(centre, face));
        assert_eq!(
            found,
            [
                Some(centre + 4),
                Some(centre - 4),
                Some(centre + 1),
                Some(centre - 1),
                Some(centre + 12),
                Some(centre - 12),
            ]
        );
    }

    /// Regression for B1: heat conducted from the east edge into the next row's
    /// west edge, and from the top row into the next z-level.
    #[test]
    fn edges_do_not_wrap() {
        let d = dims();
        for z in 0..2 {
            for y in 0..3 {
                assert_eq!(d.neighbor(index(3, y, z), Face::East), None);
                assert_eq!(d.neighbor(index(0, y, z), Face::West), None);
            }
            for x in 0..4 {
                assert_eq!(d.neighbor(index(x, 2, z), Face::North), None);
                assert_eq!(d.neighbor(index(x, 0, z), Face::South), None);
            }
        }
        assert_eq!(d.neighbor(index(1, 1, 1), Face::Up), None);
        assert_eq!(d.neighbor(index(1, 1, 0), Face::Down), None);
        assert_eq!(d.neighbor(24, Face::West), None, "index outside the grid");
    }

    #[test]
    fn neighbour_relation_is_symmetric() {
        let d = dims();
        let opposite = |face| match face {
            Face::North => Face::South,
            Face::South => Face::North,
            Face::East => Face::West,
            Face::West => Face::East,
            Face::Up => Face::Down,
            Face::Down => Face::Up,
        };
        for cell in 0..24 {
            for face in Face::ALL {
                if let Some(other) = d.neighbor(cell, face) {
                    assert_eq!(d.neighbor(other, opposite(face)), Some(cell));
                }
            }
        }
    }

    #[test]
    fn planar_dims_bound_the_plane() {
        let d = GridDims::planar(255, 255).unwrap();
        assert_eq!(d.neighbor(254, Face::East), None);
        assert_eq!(d.neighbor(254, Face::Up), Some(254 + 255 * 255));
        assert_eq!(d.neighbor(0, Face::Down), None);
    }

    #[test]
    fn layer_allocates_only_touched_chunks() {
        let dims = GridDims::new(40, 40, 3).unwrap();
        let mut layer = ChunkedLayer::<u8>::new(dims);
        assert!(layer.set(0, 0));
        assert_eq!(layer.allocated_chunks(), 0);
        assert!(layer.set(dims.index(39, 39, 2).unwrap(), 7));
        assert_eq!(layer.allocated_chunks(), 1);
        assert_eq!(layer.get(dims.index(39, 39, 2).unwrap()), Some(7));
        assert_eq!(layer.get(dims.index(38, 39, 2).unwrap()), Some(0));
        assert!(!layer.set(40 * 40 * 3, 1));
        assert_eq!(layer.get(40 * 40 * 3), None);
        layer.set(dims.index(39, 39, 2).unwrap(), 0);
        layer.compact();
        assert_eq!(layer.allocated_chunks(), 0);
    }

    #[test]
    fn blocked_faces_close_both_sides() {
        let d = dims();
        let mut grid = Grid::new(d);
        let a = index(1, 1, 0);
        let east = index(2, 1, 0);
        assert_eq!(
            grid.open_neighbor(BlockKind::Air, a, Face::East),
            Some(east)
        );
        grid.set_blocked(BlockKind::Air, east, Dir::NONE.with(Face::West));
        assert_eq!(grid.open_neighbor(BlockKind::Air, a, Face::East), None);
        assert_eq!(grid.open_neighbor(BlockKind::Air, east, Face::West), None);
        assert_eq!(
            grid.open_neighbor(BlockKind::Heat, a, Face::East),
            Some(east)
        );
        assert_eq!(grid.open_neighbors(BlockKind::Air, a).count(), 4);
    }

    /// B1 again, through `Grid`: an unblocked edge cell still has no
    /// neighbour across the edge for any block kind.
    #[test]
    fn grid_edges_do_not_wrap() {
        let grid = Grid::new(dims());
        for kind in BlockKind::ALL {
            assert_eq!(grid.open_neighbor(kind, index(3, 0, 0), Face::East), None);
            assert_eq!(grid.open_neighbor(kind, index(0, 1, 0), Face::West), None);
            assert_eq!(grid.open_neighbor(kind, index(0, 2, 0), Face::North), None);
            assert_eq!(grid.open_neighbor(kind, index(0, 2, 1), Face::Up), None);
        }
    }

    fn arb_dims() -> impl Strategy<Value = GridDims> {
        (1u32..40, 1u32..40, 1u32..5).prop_map(|(x, y, z)| GridDims::new(x, y, z).unwrap())
    }

    proptest! {
        /// Every neighbour is inside the grid, differs by exactly one step on
        /// exactly one axis (so it never wraps), and the relation is symmetric.
        #[test]
        fn neighbours_stay_in_bounds_and_never_wrap(d in arb_dims(), seed in any::<u32>()) {
            let len = d.layer_len() * d.max_z();
            let cell = seed % len;
            let (x, y, z) = d.coords(cell).unwrap();
            for face in Face::ALL {
                let expected = match face {
                    Face::North => (y + 1 < d.max_y()).then(|| (x, y + 1, z)),
                    Face::South => y.checked_sub(1).map(|y| (x, y, z)),
                    Face::East => (x + 1 < d.max_x()).then(|| (x + 1, y, z)),
                    Face::West => x.checked_sub(1).map(|x| (x, y, z)),
                    Face::Up => (z + 1 < d.max_z()).then(|| (x, y, z + 1)),
                    Face::Down => z.checked_sub(1).map(|z| (x, y, z)),
                };
                let found = d.neighbor(cell, face);
                prop_assert_eq!(found.and_then(|n| d.coords(n)), expected);
                if let Some(n) = found {
                    prop_assert!(n < len);
                    prop_assert_eq!(d.neighbor(n, face.opposite()), Some(cell));
                }
            }
            prop_assert_eq!(d.index(x, y, z), Some(cell));
            prop_assert_eq!(d.neighbor(len + seed % 100, Face::North), None);
        }

        #[test]
        fn layer_matches_model(d in arb_dims(), writes in prop::collection::vec((any::<u32>(), 0u8..4), 0..100)) {
            let len = d.layer_len() * d.max_z();
            let mut layer = ChunkedLayer::<u8>::new(d);
            let mut model = std::collections::HashMap::new();
            for (i, v) in writes {
                let i = i % (len + 10);
                prop_assert_eq!(layer.set(i, v), i < len);
                if i < len {
                    model.insert(i, v);
                }
            }
            for i in 0..len {
                prop_assert_eq!(layer.get(i), Some(model.get(&i).copied().unwrap_or(0)));
            }
        }
    }
}
