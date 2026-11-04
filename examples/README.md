# EEL Examples

Run the commands **at the repository root**. All examples are finite;
the newer examples include the expected output in the `# OUTPUT:` comments.

A suggested reading order is: sequence → objects → correlation → alternatives
→ repetition → strict mode → re-emit → pipeline → recursion → windows.

| Example | What it demonstrates | Command |
| --- | --- | --- |
| [Proto](proto.raku) | Symbolic candidates for login responses | `raku -Ilib examples/proto.raku` |
| [Signatures](proto-signatures.raku) | Dispatch by type, named argument and default | `raku -Ilib examples/proto-signatures.raku` |
| [Recursive proto](proto-recursive.raku) | Leaf family and groups with nested captures | `raku -Ilib examples/proto-recursive.raku` |
| [Inheritance](proto-inheritance.raku) | Subclass extending a pattern family | `raku -Ilib examples/proto-inheritance.raku` |
| [Partitions](partition.raku) | Strict sequences isolated by IP | `raku -Ilib examples/partition.raku` |
| [Partition change](partition-change.raku) | Client, order and scope restoration | `raku -Ilib examples/partition-change.raku` |
| [Positionals](positional.raku) | `$0` in actions and index access on the result | `raku -Ilib examples/positional.raku` |
| [Interleaving](interleave.raku) | Interleaved branches with `&&&` and a window on TOP | `raku -Ilib examples/interleave.raku` |
| [Selection](selection.raku) | All, first and last completion | `raku -Ilib examples/selection.raku` |
| [Event time](event-time.raku) | Out-of-order replay with `:lateness` | `raku -Ilib examples/event-time.raku` |
| [Conjunction](unordered.raku) | Complete branches in reverse order with `&` | `raku -Ilib examples/unordered.raku` |
| [Priority](ordered-choice.raku) | Result held by `||` and released at EOF | `raku -Ilib examples/ordered-choice.raku` |
| [Sequence](runner.raku) | Two interleaved sessions | `raku -Ilib examples/runner.raku` |
| [Objects](objects.raku) | Raku class, subclasses and attribute filters | `raku -Ilib examples/objects.raku` |
| [Predicates](predicates.raku) | Equivalent forms with map, `* > 40` and block with `$_` | `raku -Ilib examples/predicates.raku` |
| [Correlation](correlation.raku) | Orders and payments arriving in different orders | `raku -Ilib examples/correlation.raku` |
| [Alternatives](alternatives.raku) | Approval or rejection using the initial capture | `raku -Ilib examples/alternatives.raku` |
| [Repetition](repetition.raku) | `+` emitting progress at every valid completion | `raku -Ilib examples/repetition.raku` |
| [Strict mode](strict.raku) | Difference between ignoring noise and invalidating a partial match | `raku -Ilib examples/strict.raku` |
| [Re-emit](reemit.raku) | `:reemit<info>` preserving selected inputs | `raku -Ilib examples/reemit.raku` |
| [Pipeline](match.raku) | A `.match` recognizing objects produced by the previous one | `raku -Ilib examples/match.raku` |
| [Live stream](live.raku) | `Supplier`, subscription before emission and shutdown | `raku -Ilib examples/live.raku` |
| [Recursion](nested.raku) | Nested blocks with `~` and recursive call to TOP | `raku -Ilib examples/nested.raku` |
| [Decimal window](time-window.raku) | Sequence bounded by `1.5h` | `raku -Ilib examples/time-window.raku` |
| [Missing close](missing-close.raku) | `FAILGOAL` and handling by the `quit` callback | `raku -Ilib examples/missing-close.raku` |
| [Fire risk 2](fire-risk-2.raku) | Named positive capture, heat/humidity in either order, and named absence of rain confirmed by window or EOF | `raku -Ilib examples/fire-risk-2.raku` |
| [Fire risk](fire-risk.rakumod) | Temperature and humidity of the same area, in any order, within `5min` | `raku -Ilib examples/fire-risk.rakumod` |
| [Login](login) | Form, unsuccessful attempts and authentication | `raku -Ilib examples/login` |
| [Port knocking](port-knocking.rakumod) | Two door sequences correlated by IP | `raku -Ilib examples/port-knocking.rakumod` |

## Key points

- `$events.match(Type)` returns instances of the recognized event.
- `:type(Temperature)` recognizes the class and its subclasses. `.data` preserves the received object.
- `:reemit` selects inputs for the output; all of them are still considered for recognition.
- Each completion of a repetition can produce a result: previous results remain independent.
- Strict mode considers events of the current partition; without `:partition`, the whole stream is relevant. Correlating by a field does not create a partition.
- Windows use event timestamps. The decimal example replays one hour of historical data immediately; `:lateness` controls reordering and the watermark.
- Months are fixed periods of 30 days, and years of 365 days.

The textual parser and its legacy fixtures were removed; the examples use `use EEL` and `Supply.match`.

To automatically verify the output of examples with documented output:

```sh
raku -Ilib t/10-examples.t
```

In the proto examples, `:sym` identifies candidates. Multis by signature use
Raku's dispatch rules; symbolic candidates represent independent
recognitions. That is why a leaf and the group containing it can produce separate
events. The examples catch errors from the Supply and report them after execution.

## Fire Risk 2

`fire-risk-2.raku` is finite. `<data=?event: :area(*.defined)>` captures the area
without consuming the reading; that occurrence can also satisfy `dry` or `hot`.
After both thresholds match, `<no-rain=!rain: :$!area>` waits for confirmation
that no rain occurred in that area. The five-minute window starts with the first
consumed reading; crossing its deadline confirms the terminal absence. EOF also
confirms it, even when the full duration was not observed: the example prints
`window` for A and `eof` for C. Rain in B prevents B from producing a result.
