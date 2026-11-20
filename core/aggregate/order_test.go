package aggregate

import (
	"math/rand/v2"
	"slices"
	"testing"
)

func isPermutation(order []int, n int) bool {
	if len(order) != n {
		return false
	}
	sorted := slices.Clone(order)
	slices.Sort(sorted)
	for i, v := range sorted {
		if v != i {
			return false
		}
	}
	return true
}

func TestLinkOrderIsAPermutationThatStartsHealthy(t *testing.T) {
	rng := rand.New(rand.NewPCG(7, 11))
	for _, mode := range []string{ModeFailover, ModeBalance, ModeBond} {
		for round := 0; round < 2000; round++ {
			n := rng.IntN(6) // 0 and 1 included
			healthy := make([]bool, n)
			backup := make([]bool, n)
			for i := range n {
				healthy[i] = rng.IntN(3) > 0
				backup[i] = rng.IntN(4) == 0
			}
			order := linkOrder(mode, healthy, backup, rng.Uint64())
			if !isPermutation(order, n) {
				t.Fatalf("%s: order %v is not a permutation of %d links", mode, order, n)
			}
			hasHealthyPrimary := false
			hasHealthy := false
			for i := range n {
				hasHealthyPrimary = hasHealthyPrimary || (healthy[i] && !backup[i])
				hasHealthy = hasHealthy || healthy[i]
			}
			if hasHealthyPrimary && (!healthy[order[0]] || backup[order[0]]) {
				t.Fatalf("%s: healthy=%v backup=%v order=%v starts with a backup or unhealthy link", mode, healthy, backup, order)
			}
			if !hasHealthyPrimary && hasHealthy && !healthy[order[0]] {
				t.Fatalf("%s: healthy=%v order=%v starts unhealthy although a backup is healthy", mode, healthy, order)
			}
		}
	}
}

func TestFailoverFollowsPriorityAndBalanceRotatesEvenly(t *testing.T) {
	healthy := []bool{true, true, true}
	none := []bool{false, false, false}
	if got := linkOrder(ModeFailover, healthy, none, 99); !slices.Equal(got, []int{0, 1, 2}) {
		t.Fatalf("failover order = %v, want priority order", got)
	}
	if got := linkOrder(ModeFailover, []bool{false, true, true}, none, 0); !slices.Equal(got, []int{1, 2, 0}) {
		t.Fatalf("failover with a dead first link = %v, want [1 2 0]", got)
	}
	if got := linkOrder(ModeFailover, healthy, []bool{false, true, false}, 0); !slices.Equal(got, []int{0, 2, 1}) {
		t.Fatalf("failover with a backup = %v, want the backup after the other healthy link", got)
	}
	firsts := map[int]int{}
	const k = 50
	for cursor := uint64(0); cursor < 3*k; cursor++ {
		firsts[linkOrder(ModeBalance, healthy, none, cursor)[0]]++
	}
	for i := range 3 {
		if firsts[i] != k {
			t.Fatalf("balance put link %d first %d times out of %d, want %d", i, firsts[i], 3*k, k)
		}
	}
}
