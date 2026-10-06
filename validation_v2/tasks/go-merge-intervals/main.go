package main

import (
	"fmt"
	"sort"
)

// Interval represents a half-open interval [start, end).
type Interval struct {
	Start int
	End   int
}

// MergeIntervals merges overlapping intervals and returns the non-overlapping result.
func MergeIntervals(intervals []Interval) []Interval {
	if len(intervals) == 0 {
		return nil
	}

	// Make a copy to avoid mutating the caller's slice.
	c := make([]Interval, len(intervals))
	copy(c, intervals)
	sort.Slice(c, func(i, j int) bool {
		return c[i].Start < c[j].Start
	})

	result := []Interval{c[0]}
	for i := 1; i < len(c); i++ {
		last := &result[len(result)-1]
		if c[i].Start <= last.End {
			// Overlapping or adjacent — merge.
			if c[i].End > last.End {
				last.End = c[i].End
			}
		} else {
			result = append(result, c[i])
		}
	}
	return result
}

func assertEq(actual, expected any, name string) {
	if actual != expected {
		panic(fmt.Sprintf("assertion [%s] failed: got %v, want %v", name, actual, expected))
	}
}

func main() {
	// --- Assertions ---

	// 1. Empty input
	got := MergeIntervals(nil)
	assertEq(len(got), 0, "empty input")

	// 2. Single interval
	got = MergeIntervals([]Interval{{1, 5}})
	assertEq(len(got), 1, "single")
	assertEq(got[0].Start, 1, "single start")
	assertEq(got[0].End, 5, "single end")

	// 3. No overlap
	got = MergeIntervals([]Interval{{1, 2}, {4, 5}})
	assertEq(len(got), 2, "no overlap count")
	assertEq(got[0].Start, 1, "no overlap 0 start")
	assertEq(got[0].End, 2, "no overlap 0 end")
	assertEq(got[1].Start, 4, "no overlap 1 start")
	assertEq(got[1].End, 5, "no overlap 1 end")

	// 4. Full overlap
	got = MergeIntervals([]Interval{{1, 10}, {2, 6}, {8, 11}})
	assertEq(len(got), 1, "full overlap count")
	assertEq(got[0].Start, 1, "full overlap start")
	assertEq(got[0].End, 11, "full overlap end")

	// 5. Adjacent merge
	got = MergeIntervals([]Interval{{1, 3}, {3, 6}})
	assertEq(len(got), 1, "adjacent count")
	assertEq(got[0].End, 6, "adjacent end")

	// 6. Unsorted input
	got = MergeIntervals([]Interval{{6, 8}, {1, 3}, {2, 6}})
	assertEq(len(got), 1, "unsorted count")
	assertEq(got[0].Start, 1, "unsorted start")
	assertEq(got[0].End, 8, "unsorted end")

	// 7. Nested containment
	got = MergeIntervals([]Interval{{1, 10}, {3, 5}})
	assertEq(len(got), 1, "nested count")
	assertEq(got[0].End, 10, "nested end")

	// 8. Multiple disjoint
	got = MergeIntervals([]Interval{{1, 2}, {5, 7}, {9, 10}})
	assertEq(len(got), 3, "disjoint count")

	fmt.Println("go-merge-intervals: all assertions passed.")
}
