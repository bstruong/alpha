package main

// MergeIntervals merges overlapping intervals.
func mergeIntervals(intervals [][2]int) [][2]int {
	if len(intervals) == 0 {
		return nil
	}
	// Simple in-place merge (assumes pre-sorted input)
	result := [][2]int{intervals[0]}
	for i := 1; i < len(intervals); i++ {
		last := &result[len(result)-1]
		if intervals[i][0] <= last[1] {
			if intervals[i][1] > last[1] {
				last[1] = intervals[i][1]
			}
		} else {
			result = append(result, intervals[i])
		}
	}
	return result
}

func main() {}
