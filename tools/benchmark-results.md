# Optimization measurements

Local measurement on macOS, Rakudo/RakuAST, with one warm-up and median of seven
repetitions. These synthetic microbenchmarks compare execution strategies within
the matcher; their results are not guarantees for other machines or loads.

Commands:

```sh
raku -Ilib tools/benchmark-optimizations.raku --size=100 --repeats=7 --rounds=10
raku -Ilib tools/benchmark-optimizations.raku --size=1000 --repeats=7 --rounds=5
raku -Ilib tools/benchmark-optimizations.raku --size=10000 --repeats=7 --rounds=5 --only=anchor
raku -Ilib tools/benchmark-optimizations.raku --size=10000 --repeats=7 --rounds=5 --only=interval
```

Times below are medians per batch, in milliseconds. The search batches have 10
queries with size 100 and 5 with size 1,000/10,000. Buffer measures a full
load. Forks use, respectively, 10 or 5 A/B/D sequences, with eight branches.
Absolute times must not be compared across rows of different sizes.

| Size | Scenario | Optimized (ms) | Baseline (ms) | Baseline/optimized ratio |
|---:|---|---:|---:|---:|
| 100 | anchor | 1.829 | 4.076 | 2.23× |
| 100 | interval | 1.714 | 7.254 | 4.23× |
| 100 | overlap | 8.648 | 8.582 | 0.99× |
| 100 | opaque | 3.074 | 3.148 | 1.02× |
| 100 | buffer | 0.739 | 7.021 | 9.50× |
| 100 | starters | 5.229 | 9.149 | 1.75× |
| 100 | forks | 124.252 | 174.917 | 1.41× |
| 100 | retained | 4.594 | 173.487 | 37.76× |
| 1000 | anchor | 1.079 | 21.658 | 20.08× |
| 1000 | interval | 1.026 | 40.049 | 39.03× |
| 1000 | overlap | 47.692 | 47.258 | 0.99× |
| 1000 | opaque | 16.733 | 16.800 | 1.00× |
| 1000 | buffer | 12.898 | 986.249 | 76.46× |
| 1000 | starters | 2.736 | 33.304 | 12.17× |
| 1000 | forks | 68.663 | 90.727 | 1.32× |
| 1000 | retained | 2.368 | 857.074 | 361.95× |
| 10000 | anchor | 0.964 | 199.713 | 207.26× |
| 10000 | interval | 1.098 | 398.905 | 363.44× |

The search baselines scan the subscriptions through the same matcher; the
buffer baseline re-sorts the queue at every arrival. Starters compare against
evaluating every starter path. Forks disable the safe sharing
of definitions. Retained results compare against reconsidering all
results at every round, keeping the same priority rules.

Structural results verified in the tests:

- One bucket visit to find an ID among 1,000/10,000 waits of the same type.
- One interval node per conjunction/field represents both bounds.
- No starter evaluation on inputs irrelevant to 100 definitions.
- No rematerialization of safe frames; mutable containers are still copied.
- No reconsideration of held results in unaffected groups.
- Transition from index to scan and selectivity recovery through probes.

Broad loads are not sublinear: if every match needs to advance, the
work remains proportional to the number of matches. Fallbacks, hysteresis and
differential tests preserve the matcher's semantics. The values
are not temporal asserts in CI. The quadratic case of buffer sorting and the
initialization of thousands of classes make some size-10,000 scenarios
expensive; only the selective searches were run at that scale.
