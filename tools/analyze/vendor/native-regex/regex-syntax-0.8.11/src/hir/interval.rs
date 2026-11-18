use core::{char, cmp, fmt::Debug, slice};

use alloc::vec::Vec;

use crate::unicode;

// This module contains an *internal* implementation of interval sets.
//
// The primary invariant that interval sets guards is canonical ordering. That
// is, every interval set contains an ordered sequence of intervals where
// no two intervals are overlapping or adjacent. While this invariant is
// occasionally broken within the implementation, it should be impossible for
// callers to observe it.
//
// Since case folding (as implemented below) breaks that invariant, we roll
// that into this API even though it is a little out of place in an otherwise
// generic interval set. (Hence the reason why the `unicode` module is imported
// here.)
//
// Some of the implementation complexity here is a result of me wanting to
// preserve the sequential representation without using additional memory.
// In many cases, we do use linear extra memory, but it is at most 2x and it
// is amortized. If we relaxed the memory requirements, this implementation
// could become much simpler. The extra memory is honestly probably OK, but
// character classes (especially of the Unicode variety) can become quite
// large, and it would be nice to keep regex compilation snappy even in debug
// builds. (In the past, I have been careless with this area of code and it has
// caused slow regex compilations in debug mode, so this isn't entirely
// unwarranted.)
//
// Tests on this are relegated to the public API of HIR in src/hir.rs.

#[derive(Clone, Debug)]
pub struct IntervalSet<I> {
    /// A sorted set of non-overlapping ranges.
    ranges: Vec<I>,
    /// While not required at all for correctness, we keep track of whether an
    /// interval set has been case folded or not. This helps us avoid doing
    /// redundant work if, for example, a set has already been cased folded.
    /// And note that whether a set is folded or not is preserved through
    /// all of the pairwise set operations. That is, if both interval sets
    /// have been case folded, then any of difference, union, intersection or
    /// symmetric difference all produce a case folded set.
    ///
    /// Note that when this is true, it *must* be the case that the set is case
    /// folded. But when it's false, the set *may* be case folded. In other
    /// words, we only set this to true when we know it to be case, but we're
    /// okay with it being false if it would otherwise be costly to determine
    /// whether it should be true. This means code cannot assume that a false
    /// value necessarily indicates that the set is not case folded.
    ///
    /// Bottom line: this is a performance optimization.
    folded: bool,
}

#[cfg(feature="native-admission")]
impl<I> IntervalSet<I>{pub(super)fn native_storage_bytes(&self)->Option<usize>{if self.ranges.capacity()==0{Some(0)}else{self.ranges.capacity().checked_mul(core::mem::size_of::<I>())?.checked_add(64)}}}

impl<I: Interval> Eq for IntervalSet<I> {}

// We implement PartialEq manually so that we don't consider the set's internal
// 'folded' property to be part of its identity. The 'folded' property is
// strictly an optimization.
impl<I: Interval> PartialEq for IntervalSet<I> {
    fn eq(&self, other: &IntervalSet<I>) -> bool {
        self.ranges.eq(&other.ranges)
    }
}

impl<I: Interval> IntervalSet<I> {
    /// Create a new set from a sequence of intervals. Each interval is
    /// specified as a pair of bounds, where both bounds are inclusive.
    ///
    /// The given ranges do not need to be in any specific order, and ranges
    /// may overlap.
    pub fn new<T: IntoIterator<Item = I>>(intervals: T) -> IntervalSet<I> {
        let ranges: Vec<I> = intervals.into_iter().collect();
        // An empty set is case folded.
        let folded = ranges.is_empty();
        let mut set = IntervalSet { ranges, folded };
        set.canonicalize();
        set
    }

    /// Add a new interval to this set.
    pub fn push(&mut self, mut interval: I) {
        let Err(i) = self.ranges.binary_search(&interval) else {
            // Exact match, `interval` is already in the set.
            return;
        };

        // The search finds us the first index where the previous interval
        // start is less than or equal to the new interval start. Since the
        // existing intervals are non-overlapping we only need to try to union
        // this single preceding interval
        let mut start = i;
        if let Some(before_i) = i.checked_sub(1) {
            let before = &self.ranges[before_i];
            if let Some(union) = before.union(&interval) {
                interval = union;
                start = before_i;
            }
        }
        // `interval` may overlap any number of intervals following the
        // insertion point so will union each of them until we reach the
        // first non-overlapping interval
        let mut end = i;
        for after_i in i..self.ranges.len() {
            let after = &self.ranges[after_i];
            let Some(union) = interval.union(after) else {
                break;
            };
            interval = union;
            end = after_i + 1;
        }
        self.ranges.splice(start..end, core::iter::once(interval));

        // We don't know whether the new interval added here is considered
        // case folded, so we conservatively assume that the entire set is
        // no longer case folded if it was previously.
        self.folded = false;
    }

    /// Return an iterator over all intervals in this set.
    ///
    /// The iterator yields intervals in ascending order.
    pub fn iter(&self) -> IntervalSetIter<'_, I> {
        IntervalSetIter(self.ranges.iter())
    }

    /// Return an immutable slice of intervals in this set.
    ///
    /// The sequence returned is in canonical ordering.
    pub fn intervals(&self) -> &[I] {
        &self.ranges
    }

    /// Expand this interval set such that it contains all case folded
    /// characters. For example, if this class consists of the range `a-z`,
    /// then applying case folding will result in the class containing both the
    /// ranges `a-z` and `A-Z`.
    ///
    /// This returns an error if the necessary case mapping data is not
    /// available.
    pub fn case_fold_simple(&mut self) -> Result<(), unicode::CaseFoldError> {
        if self.folded {
            return Ok(());
        }
        let len = self.ranges.len();
        for i in 0..len {
            let range = self.ranges[i];
            if let Err(err) = range.case_fold_simple(&mut self.ranges) {
                self.canonicalize();
                return Err(err);
            }
        }
        self.canonicalize();
        self.folded = true;
        Ok(())
    }

    /// Union this set with the given set, in place.
    pub fn union(&mut self, other: &IntervalSet<I>) {
        if other.ranges.is_empty() || self.ranges == other.ranges {
            return;
        }
        // This could almost certainly be done more efficiently.
        self.ranges.extend(&other.ranges);
        self.canonicalize();
        self.folded = self.folded && other.folded;
    }

    /// Intersect this set with the given set, in place.
    pub fn intersect(&mut self, other: &IntervalSet<I>) {
        if self.ranges.is_empty() {
            return;
        }
        if other.ranges.is_empty() {
            self.ranges.clear();
            // An empty set is case folded.
            self.folded = true;
            return;
        }

        // There should be a way to do this in-place with constant memory,
        // but I couldn't figure out a simple way to do it. So just append
        // the intersection to the end of this range, and then drain it before
        // we're done.
        let drain_end = self.ranges.len();

        let mut ita = 0..drain_end;
        let mut itb = 0..other.ranges.len();
        let mut a = ita.next().unwrap();
        let mut b = itb.next().unwrap();
        loop {
            if let Some(ab) = self.ranges[a].intersect(&other.ranges[b]) {
                self.ranges.push(ab);
            }
            let (it, aorb) =
                if self.ranges[a].upper() < other.ranges[b].upper() {
                    (&mut ita, &mut a)
                } else {
                    (&mut itb, &mut b)
                };
            match it.next() {
                Some(v) => *aorb = v,
                None => break,
            }
        }
        self.ranges.drain(..drain_end);
        self.folded = self.folded && other.folded;
    }

    /// Subtract the given set from this set, in place.
    pub fn difference(&mut self, other: &IntervalSet<I>) {
        if self.ranges.is_empty() || other.ranges.is_empty() {
            return;
        }

        // This algorithm is (to me) surprisingly complex. A search of the
        // interwebs indicate that this is a potentially interesting problem.
        // Folks seem to suggest interval or segment trees, but I'd like to
        // avoid the overhead (both runtime and conceptual) of that.
        //
        // The following is basically my Shitty First Draft. Therefore, in
        // order to grok it, you probably need to read each line carefully.
        // Simplifications are most welcome!
        //
        // Remember, we can assume the canonical format invariant here, which
        // says that all ranges are sorted, not overlapping and not adjacent in
        // each class.
        let drain_end = self.ranges.len();
        let (mut a, mut b) = (0, 0);
        'LOOP: while a < drain_end && b < other.ranges.len() {
            // Basically, the easy cases are when neither range overlaps with
            // each other. If the `b` range is less than our current `a`
            // range, then we can skip it and move on.
            if other.ranges[b].upper() < self.ranges[a].lower() {
                b += 1;
                continue;
            }
            // ... similarly for the `a` range. If it's less than the smallest
            // `b` range, then we can add it as-is.
            if self.ranges[a].upper() < other.ranges[b].lower() {
                let range = self.ranges[a];
                self.ranges.push(range);
                a += 1;
                continue;
            }
            // Otherwise, we have overlapping ranges.
            assert!(!self.ranges[a].is_intersection_empty(&other.ranges[b]));

            // This part is tricky and was non-obvious to me without looking
            // at explicit examples (see the tests). The trickiness stems from
            // two things: 1) subtracting a range from another range could
            // yield two ranges and 2) after subtracting a range, it's possible
            // that future ranges can have an impact. The loop below advances
            // the `b` ranges until they can't possible impact the current
            // range.
            //
            // For example, if our `a` range is `a-t` and our next three `b`
            // ranges are `a-c`, `g-i`, `r-t` and `x-z`, then we need to apply
            // subtraction three times before moving on to the next `a` range.
            let mut range = self.ranges[a];
            while b < other.ranges.len()
                && !range.is_intersection_empty(&other.ranges[b])
            {
                let old_range = range;
                range = match range.difference(&other.ranges[b]) {
                    (None, None) => {
                        // We lost the entire range, so move on to the next
                        // without adding this one.
                        a += 1;
                        continue 'LOOP;
                    }
                    (Some(range1), None) | (None, Some(range1)) => range1,
                    (Some(range1), Some(range2)) => {
                        self.ranges.push(range1);
                        range2
                    }
                };
                // It's possible that the `b` range has more to contribute
                // here. In particular, if it is greater than the original
                // range, then it might impact the next `a` range *and* it
                // has impacted the current `a` range as much as possible,
                // so we can quit. We don't bump `b` so that the next `a`
                // range can apply it.
                if other.ranges[b].upper() > old_range.upper() {
                    break;
                }
                // Otherwise, the next `b` range might apply to the current
                // `a` range.
                b += 1;
            }
            self.ranges.push(range);
            a += 1;
        }
        while a < drain_end {
            let range = self.ranges[a];
            self.ranges.push(range);
            a += 1;
        }
        self.ranges.drain(..drain_end);
        self.folded = self.folded && other.folded;
    }

    /// Compute the symmetric difference of the two sets, in place.
    ///
    /// This computes the symmetric difference of two interval sets. This
    /// removes all elements in this set that are also in the given set,
    /// but also adds all elements from the given set that aren't in this
    /// set. That is, the set will contain all elements in either set,
    /// but will not contain any elements that are in both sets.
    pub fn symmetric_difference(&mut self, other: &IntervalSet<I>) {
        // TODO(burntsushi): Fix this so that it amortizes allocation.
        let mut intersection = self.clone();
        intersection.intersect(other);
        self.union(other);
        self.difference(&intersection);
    }

    /// Negate this interval set.
    ///
    /// For all `x` where `x` is any element, if `x` was in this set, then it
    /// will not be in this set after negation.
    pub fn negate(&mut self) {
        if self.ranges.is_empty() {
            let (min, max) = (I::Bound::min_value(), I::Bound::max_value());
            self.ranges.push(I::create(min, max));
            // The set containing everything must case folded.
            self.folded = true;
            return;
        }

        // There should be a way to do this in-place with constant memory,
        // but I couldn't figure out a simple way to do it. So just append
        // the negation to the end of this range, and then drain it before
        // we're done.
        let drain_end = self.ranges.len();

        // We do checked arithmetic below because of the canonical ordering
        // invariant.
        if self.ranges[0].lower() > I::Bound::min_value() {
            let upper = self.ranges[0].lower().decrement();
            self.ranges.push(I::create(I::Bound::min_value(), upper));
        }
        for i in 1..drain_end {
            let lower = self.ranges[i - 1].upper().increment();
            let upper = self.ranges[i].lower().decrement();
            self.ranges.push(I::create(lower, upper));
        }
        if self.ranges[drain_end - 1].upper() < I::Bound::max_value() {
            let lower = self.ranges[drain_end - 1].upper().increment();
            self.ranges.push(I::create(lower, I::Bound::max_value()));
        }
        self.ranges.drain(..drain_end);
        // We don't need to update whether this set is folded or not, because
        // it is conservatively preserved through negation. Namely, if a set
        // is not folded, then it is possible that its negation is folded, for
        // example, [^☃]. But we're fine with assuming that the set is not
        // folded in that case. (`folded` permits false negatives but not false
        // positives.)
        //
        // But what about when a set is folded, is its negation also
        // necessarily folded? Yes. Because if a set is folded, then for every
        // character in the set, it necessarily included its equivalence class
        // of case folded characters. Negating it in turn means that all
        // equivalence classes in the set are negated, and any equivalence
        // class that was previously not in the set is now entirely in the set.
    }

    /// Converts this set into a canonical ordering.
    fn canonicalize(&mut self) {
        if self.is_canonical() {
            return;
        }
        self.ranges.sort();
        assert!(!self.ranges.is_empty());

        // Is there a way to do this in-place with constant memory? I couldn't
        // figure out a way to do it. So just append the canonicalization to
        // the end of this range, and then drain it before we're done.
        let drain_end = self.ranges.len();
        for oldi in 0..drain_end {
            // If we've added at least one new range, then check if we can
            // merge this range in the previously added range.
            if self.ranges.len() > drain_end {
                let (last, rest) = self.ranges.split_last_mut().unwrap();
                if let Some(union) = last.union(&rest[oldi]) {
                    *last = union;
                    continue;
                }
            }
            let range = self.ranges[oldi];
            self.ranges.push(range);
        }
        self.ranges.drain(..drain_end);
    }

    #[cfg(feature="native-admission")]
    pub fn push_admitted(&mut self, mut interval: I, hook:&crate::native_admission::Hook<'_>)->Result<(),crate::native_admission::Refused> {
        hook.require_active()?;hook.checkpoint()?;
        let Err(i) = self.ranges.binary_search(&interval) else {
            // Exact match, `interval` is already in the set.
            return Ok(());
        };

        // The search finds us the first index where the previous interval
        // start is less than or equal to the new interval start. Since the
        // existing intervals are non-overlapping we only need to try to union
        // this single preceding interval
        let mut start = i;
        if let Some(before_i) = i.checked_sub(1) {
            let before = &self.ranges[before_i];
            if let Some(union) = before.union(&interval) {
                interval = union;
                start = before_i;
            }
        }
        // `interval` may overlap any number of intervals following the
        // insertion point so will union each of them until we reach the
        // first non-overlapping interval
        let mut end = i;
        for after_i in i..self.ranges.len() {
            hook.require_active()?;hook.checkpoint()?;
            let after = &self.ranges[after_i];
            let Some(union) = interval.union(after) else {
                break;
            };
            interval = union;
            end = after_i + 1;
        }
        hook.room(&mut self.ranges,1)?;
        self.ranges.splice(start..end, core::iter::once(interval));

        // We don't know whether the new interval added here is considered
        // case folded, so we conservatively assume that the entire set is
        // no longer case folded if it was previously.
        self.folded = false;
            Ok(())
    }
    #[cfg(feature="native-admission")]
    pub fn intersect_admitted(&mut self, other: &IntervalSet<I>, hook:&crate::native_admission::Hook<'_>)->Result<(),crate::native_admission::Refused> {
        hook.require_active()?;hook.checkpoint()?;
        if self.ranges.is_empty() {
            return Ok(());
        }
        if other.ranges.is_empty() {
            self.ranges.clear();
            // An empty set is case folded.
            self.folded = true;
            return Ok(());
        }

        // There should be a way to do this in-place with constant memory,
        // but I couldn't figure out a simple way to do it. So just append
        // the intersection to the end of this range, and then drain it before
        // we're done.
        let drain_end = self.ranges.len();

        let mut ita = 0..drain_end;
        let mut itb = 0..other.ranges.len();
        let mut a = ita.next().unwrap();
        let mut b = itb.next().unwrap();
        loop {
            if let Some(ab) = self.ranges[a].intersect(&other.ranges[b]) {
                hook.push(&mut self.ranges,ab)?;
            }
            let (it, aorb) =
                if self.ranges[a].upper() < other.ranges[b].upper() {
                    (&mut ita, &mut a)
                } else {
                    (&mut itb, &mut b)
                };
            match it.next() {
                Some(v) => *aorb = v,
                None => break,
            }
        }
        self.ranges.drain(..drain_end);
        self.folded = self.folded && other.folded;
            Ok(())
    }
    #[cfg(feature="native-admission")]
    pub fn difference_admitted(&mut self, other: &IntervalSet<I>, hook:&crate::native_admission::Hook<'_>)->Result<(),crate::native_admission::Refused> {
        hook.require_active()?;hook.checkpoint()?;
        if self.ranges.is_empty() || other.ranges.is_empty() {
            return Ok(());
        }

        // This algorithm is (to me) surprisingly complex. A search of the
        // interwebs indicate that this is a potentially interesting problem.
        // Folks seem to suggest interval or segment trees, but I'd like to
        // avoid the overhead (both runtime and conceptual) of that.
        //
        // The following is basically my Shitty First Draft. Therefore, in
        // order to grok it, you probably need to read each line carefully.
        // Simplifications are most welcome!
        //
        // Remember, we can assume the canonical format invariant here, which
        // says that all ranges are sorted, not overlapping and not adjacent in
        // each class.
        let drain_end = self.ranges.len();
        let (mut a, mut b) = (0, 0);
        'LOOP: while a < drain_end && b < other.ranges.len() {
            hook.require_active()?;hook.checkpoint()?;
            // Basically, the easy cases are when neither range overlaps with
            // each other. If the `b` range is less than our current `a`
            // range, then we can skip it and move on.
            if other.ranges[b].upper() < self.ranges[a].lower() {
                b += 1;
                continue;
            }
            // ... similarly for the `a` range. If it's less than the smallest
            // `b` range, then we can add it as-is.
            if self.ranges[a].upper() < other.ranges[b].lower() {
                let range = self.ranges[a];
                hook.push(&mut self.ranges,range)?;
                a += 1;
                continue;
            }
            // Otherwise, we have overlapping ranges.
            assert!(!self.ranges[a].is_intersection_empty(&other.ranges[b]));

            // This part is tricky and was non-obvious to me without looking
            // at explicit examples (see the tests). The trickiness stems from
            // two things: 1) subtracting a range from another range could
            // yield two ranges and 2) after subtracting a range, it's possible
            // that future ranges can have an impact. The loop below advances
            // the `b` ranges until they can't possible impact the current
            // range.
            //
            // For example, if our `a` range is `a-t` and our next three `b`
            // ranges are `a-c`, `g-i`, `r-t` and `x-z`, then we need to apply
            // subtraction three times before moving on to the next `a` range.
            let mut range = self.ranges[a];
            while b < other.ranges.len()
                && !range.is_intersection_empty(&other.ranges[b])
            {
                let old_range = range;
                range = match range.difference(&other.ranges[b]) {
                    (None, None) => {
                        // We lost the entire range, so move on to the next
                        // without adding this one.
                        a += 1;
                        continue 'LOOP;
                    }
                    (Some(range1), None) | (None, Some(range1)) => range1,
                    (Some(range1), Some(range2)) => {
                        hook.push(&mut self.ranges,range1)?;
                        range2
                    }
                };
                // It's possible that the `b` range has more to contribute
                // here. In particular, if it is greater than the original
                // range, then it might impact the next `a` range *and* it
                // has impacted the current `a` range as much as possible,
                // so we can quit. We don't bump `b` so that the next `a`
                // range can apply it.
                if other.ranges[b].upper() > old_range.upper() {
                    break;
                }
                // Otherwise, the next `b` range might apply to the current
                // `a` range.
                b += 1;
            }
            hook.push(&mut self.ranges,range)?;
            a += 1;
        }
        while a < drain_end {
            hook.require_active()?;hook.checkpoint()?;
            let range = self.ranges[a];
            hook.push(&mut self.ranges,range)?;
            a += 1;
        }
        self.ranges.drain(..drain_end);
        self.folded = self.folded && other.folded;
            Ok(())
    }
    #[cfg(feature="native-admission")]
    pub fn negate_admitted(&mut self, hook:&crate::native_admission::Hook<'_>)->Result<(),crate::native_admission::Refused> {
        hook.require_active()?;hook.checkpoint()?;
        if self.ranges.is_empty() {
            let (min, max) = (I::Bound::min_value(), I::Bound::max_value());
            hook.push(&mut self.ranges,I::create(min, max))?;
            // The set containing everything must case folded.
            self.folded = true;
            return Ok(());
        }

        // There should be a way to do this in-place with constant memory,
        // but I couldn't figure out a simple way to do it. So just append
        // the negation to the end of this range, and then drain it before
        // we're done.
        let drain_end = self.ranges.len();

        // We do checked arithmetic below because of the canonical ordering
        // invariant.
        if self.ranges[0].lower() > I::Bound::min_value() {
            let upper = self.ranges[0].lower().decrement();
            hook.push(&mut self.ranges,I::create(I::Bound::min_value(), upper))?;
        }
        for i in 1..drain_end {
            hook.require_active()?;hook.checkpoint()?;
            let lower = self.ranges[i - 1].upper().increment();
            let upper = self.ranges[i].lower().decrement();
            hook.push(&mut self.ranges,I::create(lower, upper))?;
        }
        if self.ranges[drain_end - 1].upper() < I::Bound::max_value() {
            let lower = self.ranges[drain_end - 1].upper().increment();
            hook.push(&mut self.ranges,I::create(lower, I::Bound::max_value()))?;
        }
        self.ranges.drain(..drain_end);
        // We don't need to update whether this set is folded or not, because
        // it is conservatively preserved through negation. Namely, if a set
        // is not folded, then it is possible that its negation is folded, for
        // example, [^☃]. But we're fine with assuming that the set is not
        // folded in that case. (`folded` permits false negatives but not false
        // positives.)
        //
        // But what about when a set is folded, is its negation also
        // necessarily folded? Yes. Because if a set is folded, then for every
        // character in the set, it necessarily included its equivalence class
        // of case folded characters. Negating it in turn means that all
        // equivalence classes in the set are negated, and any equivalence
        // class that was previously not in the set is now entirely in the set.
            Ok(())
    }
    #[cfg(feature="native-admission")]
    fn canonicalize_admitted(&mut self, hook:&crate::native_admission::Hook<'_>)->Result<(),crate::native_admission::Refused> {
        hook.require_active()?;hook.checkpoint()?;
        if self.is_canonical() {
            return Ok(());
        }
        // Stable sort may own a temporary buffer. Pay the full actual
        // input extent before invoking the unchanged stable algorithm.
        hook.reserve(||self.ranges.len().checked_mul(core::mem::size_of::<I>())?.checked_add(64))?;
        self.ranges.sort();
        assert!(!self.ranges.is_empty());

        // Is there a way to do this in-place with constant memory? I couldn't
        // figure out a way to do it. So just append the canonicalization to
        // the end of this range, and then drain it before we're done.
        let drain_end = self.ranges.len();
        for oldi in 0..drain_end {
            hook.require_active()?;hook.checkpoint()?;
            // If we've added at least one new range, then check if we can
            // merge this range in the previously added range.
            if self.ranges.len() > drain_end {
                let (last, rest) = self.ranges.split_last_mut().unwrap();
                if let Some(union) = last.union(&rest[oldi]) {
                    *last = union;
                    continue;
                }
            }
            let range = self.ranges[oldi];
            hook.push(&mut self.ranges,range)?;
        }
        self.ranges.drain(..drain_end);
            Ok(())
    }
    #[cfg(feature="native-admission")]
    pub fn clone_admitted(&self,hook:&crate::native_admission::Hook<'_>)->Result<Self,crate::native_admission::Refused>{
        hook.require_active()?;let mut ranges=Vec::new();hook.room(&mut ranges,self.ranges.len())?;
        ranges.extend_from_slice(&self.ranges);Ok(Self{ranges,folded:self.folded})
    }
    #[cfg(feature="native-admission")]
    pub fn new_admitted<T:IntoIterator<Item=I>>(items:T,hook:&crate::native_admission::Hook<'_>)->Result<Self,crate::native_admission::Refused>{
        hook.require_active()?;let mut ranges=Vec::new();for range in items{hook.push(&mut ranges,range)?;}
        let folded=ranges.is_empty();let mut actual=Self{ranges,folded};actual.canonicalize_admitted(hook)?;Ok(actual)
    }
    #[cfg(feature="native-admission")]
    pub fn union_admitted(&mut self,other:&Self,hook:&crate::native_admission::Hook<'_>)->Result<(),crate::native_admission::Refused>{
        hook.require_active()?;hook.checkpoint()?;if other.ranges.is_empty()||self.ranges==other.ranges{return Ok(())}
        hook.room(&mut self.ranges,other.ranges.len())?;self.ranges.extend_from_slice(&other.ranges);
        self.canonicalize_admitted(hook)?;self.folded=self.folded&&other.folded;Ok(())
    }
    #[cfg(feature="native-admission")]
    pub fn symmetric_difference_admitted(&mut self,other:&Self,hook:&crate::native_admission::Hook<'_>)->Result<(),crate::native_admission::Refused>{
        let mut intersection=self.clone_admitted(hook)?;intersection.intersect_admitted(other,hook)?;
        self.union_admitted(other,hook)?;self.difference_admitted(&intersection,hook)
    }
    #[cfg(feature="native-admission")]
    pub fn case_fold_simple_admitted(&mut self,hook:&crate::native_admission::Hook<'_>)->Result<(),NativeCaseFoldError>{
        hook.require_active()?;hook.checkpoint()?;if self.folded{return Ok(())}let len=self.ranges.len();
        for i in 0..len{hook.checkpoint()?;let range=self.ranges[i];
            match range.case_fold_simple_admitted(&mut self.ranges,hook){
                Ok(())=>{},Err(NativeCaseFoldError::Unavailable(actual))=>{self.canonicalize_admitted(hook)?;return Err(NativeCaseFoldError::Unavailable(actual))},
                Err(actual)=>return Err(actual),
            }
        }
        self.canonicalize_admitted(hook)?;self.folded=true;Ok(())
    }

    /// Returns true if and only if this class is in a canonical ordering.
    fn is_canonical(&self) -> bool {
        for pair in self.ranges.windows(2) {
            if pair[0] >= pair[1] {
                return false;
            }
            if pair[0].is_contiguous(&pair[1]) {
                return false;
            }
        }
        true
    }
}

/// An iterator over intervals.
#[derive(Debug)]
pub struct IntervalSetIter<'a, I>(slice::Iter<'a, I>);

impl<'a, I> Iterator for IntervalSetIter<'a, I> {
    type Item = &'a I;

    fn next(&mut self) -> Option<&'a I> {
        self.0.next()
    }
}

#[cfg(feature="native-admission")]
#[derive(Debug)]
pub enum NativeCaseFoldError{Refused(crate::native_admission::Refused),Unavailable(unicode::CaseFoldError)}
#[cfg(feature="native-admission")]
impl From<crate::native_admission::Refused> for NativeCaseFoldError{fn from(actual:crate::native_admission::Refused)->Self{Self::Refused(actual)}}
#[cfg(feature="native-admission")]
impl From<unicode::CaseFoldError> for NativeCaseFoldError{fn from(actual:unicode::CaseFoldError)->Self{Self::Unavailable(actual)}}

pub trait Interval:
    Clone + Copy + Debug + Default + Eq + PartialEq + PartialOrd + Ord
{
    type Bound: Bound;

    fn lower(&self) -> Self::Bound;
    fn upper(&self) -> Self::Bound;
    fn set_lower(&mut self, bound: Self::Bound);
    fn set_upper(&mut self, bound: Self::Bound);
    fn case_fold_simple(
        &self,
        intervals: &mut Vec<Self>,
    ) -> Result<(), unicode::CaseFoldError>;

    #[cfg(feature="native-admission")]
    fn case_fold_simple_admitted(&self,intervals:&mut Vec<Self>,hook:&crate::native_admission::Hook<'_>)->Result<(),NativeCaseFoldError>;

    /// Create a new interval.
    fn create(lower: Self::Bound, upper: Self::Bound) -> Self {
        let mut int = Self::default();
        if lower <= upper {
            int.set_lower(lower);
            int.set_upper(upper);
        } else {
            int.set_lower(upper);
            int.set_upper(lower);
        }
        int
    }

    /// Union the given overlapping range into this range.
    ///
    /// If the two ranges aren't contiguous, then this returns `None`.
    fn union(&self, other: &Self) -> Option<Self> {
        if !self.is_contiguous(other) {
            return None;
        }
        let lower = cmp::min(self.lower(), other.lower());
        let upper = cmp::max(self.upper(), other.upper());
        Some(Self::create(lower, upper))
    }

    /// Intersect this range with the given range and return the result.
    ///
    /// If the intersection is empty, then this returns `None`.
    fn intersect(&self, other: &Self) -> Option<Self> {
        let lower = cmp::max(self.lower(), other.lower());
        let upper = cmp::min(self.upper(), other.upper());
        if lower <= upper {
            Some(Self::create(lower, upper))
        } else {
            None
        }
    }

    /// Subtract the given range from this range and return the resulting
    /// ranges.
    ///
    /// If subtraction would result in an empty range, then no ranges are
    /// returned.
    fn difference(&self, other: &Self) -> (Option<Self>, Option<Self>) {
        if self.is_subset(other) {
            return (None, None);
        }
        if self.is_intersection_empty(other) {
            return (Some(self.clone()), None);
        }
        let add_lower = other.lower() > self.lower();
        let add_upper = other.upper() < self.upper();
        // We know this because !self.is_subset(other) and the ranges have
        // a non-empty intersection.
        assert!(add_lower || add_upper);
        let mut ret = (None, None);
        if add_lower {
            let upper = other.lower().decrement();
            ret.0 = Some(Self::create(self.lower(), upper));
        }
        if add_upper {
            let lower = other.upper().increment();
            let range = Self::create(lower, self.upper());
            if ret.0.is_none() {
                ret.0 = Some(range);
            } else {
                ret.1 = Some(range);
            }
        }
        ret
    }

    /// Returns true if and only if the two ranges are contiguous. Two ranges
    /// are contiguous if and only if the ranges are either overlapping or
    /// adjacent.
    fn is_contiguous(&self, other: &Self) -> bool {
        let lower1 = self.lower().as_u32();
        let upper1 = self.upper().as_u32();
        let lower2 = other.lower().as_u32();
        let upper2 = other.upper().as_u32();
        cmp::max(lower1, lower2) <= cmp::min(upper1, upper2).saturating_add(1)
    }

    /// Returns true if and only if the intersection of this range and the
    /// other range is empty.
    fn is_intersection_empty(&self, other: &Self) -> bool {
        let (lower1, upper1) = (self.lower(), self.upper());
        let (lower2, upper2) = (other.lower(), other.upper());
        cmp::max(lower1, lower2) > cmp::min(upper1, upper2)
    }

    /// Returns true if and only if this range is a subset of the other range.
    fn is_subset(&self, other: &Self) -> bool {
        let (lower1, upper1) = (self.lower(), self.upper());
        let (lower2, upper2) = (other.lower(), other.upper());
        (lower2 <= lower1 && lower1 <= upper2)
            && (lower2 <= upper1 && upper1 <= upper2)
    }
}

pub trait Bound:
    Copy + Clone + Debug + Eq + PartialEq + PartialOrd + Ord
{
    fn min_value() -> Self;
    fn max_value() -> Self;
    fn as_u32(self) -> u32;
    fn increment(self) -> Self;
    fn decrement(self) -> Self;
}

impl Bound for u8 {
    fn min_value() -> Self {
        u8::MIN
    }
    fn max_value() -> Self {
        u8::MAX
    }
    fn as_u32(self) -> u32 {
        u32::from(self)
    }
    fn increment(self) -> Self {
        self.checked_add(1).unwrap()
    }
    fn decrement(self) -> Self {
        self.checked_sub(1).unwrap()
    }
}

impl Bound for char {
    fn min_value() -> Self {
        '\x00'
    }
    fn max_value() -> Self {
        '\u{10FFFF}'
    }
    fn as_u32(self) -> u32 {
        u32::from(self)
    }

    fn increment(self) -> Self {
        match self {
            '\u{D7FF}' => '\u{E000}',
            c => char::from_u32(u32::from(c).checked_add(1).unwrap()).unwrap(),
        }
    }

    fn decrement(self) -> Self {
        match self {
            '\u{E000}' => '\u{D7FF}',
            c => char::from_u32(u32::from(c).checked_sub(1).unwrap()).unwrap(),
        }
    }
}

// Tests for interval sets are written in src/hir.rs against the public API.
