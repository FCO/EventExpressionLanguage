# Event Expression Language

EEL recognizes event sequences in Raku `Supply`s. The slang compiles `event` and
`pattern` declarations into definitions executed by a runner with in-memory state.

Requires Rakudo with the **RakuAST** frontend, on macOS or Linux. Enable it with
`RAKUDO_RAKUAST=1` when it is not the default frontend. The distribution is named
`EEL`, and the public API is imported with `use EEL`.

```sh
zef install .
# After installing, the CLI command is eel; in the checkout use bin/eel.raku.
raku -Ilib examples/login
raku tools/test.raku
```

```raku
use EEL;
event Session {
    has $.id;
    pattern TOP {
        :partition{ .<id> }
        :!ignore-unexpected
        <start=.event: :type<start>>
        <finish=.event: :type<finish>>
        { $!id = $<start>.id }
    }
}
({type=>'start', id=>42}, {type=>'finish', id=>42}).Supply.match(Session).tap:
    -> $session { say $session.id };
```

## Stream API

`$input.match(EventType, OtherType, :rule<TOP>, :reemit, :lateness(0), :actions($actions))` returns a `Supply` with
instances of the recognized events. Processing starts at subscription; each
subscription has its own runner. Inputs can be Hash/Map or defined objects.
`:type(Temperature)` accepts the class and its subclasses; an explicit `type` field
can classify objects or hashes by name. The remaining fields accept equality,
operator maps (`==`, `!=`, `>`, `>=`, `<`, `<=`) or callables, such as
`:value(* > 40)` and `:value{ $_ > 40 }`. Predicates receive the field value.

Without `:reemit`, the output contains only derived events. `:reemit` preserves all
inputs; `:reemit(Login, Temperature)` or `:reemit<info warning>` preserve only
selected types. Each input is re-emitted at most once, before the results it
completes. Selecting the output does not filter the matcher's input.
Derived events are not re-inserted automatically; chain `.match` calls to
recognize events derived by other stages.

Input or action errors end the subscription through the `quit` callback. Closing the
tap cancels the runner without finalizing incomplete matches. EOF finishes
recognition, including `||` results that were waiting for higher-priority
alternatives. `use EEL` installs `.match` on the shared `Supply` class via `augment`; the
slang is lexical. For direct control use `EEL::Runner.new(:patterns[Type])`, `.process`,
`.finish`, `.pending` and `.close`. `.process` and `.finish` return lists of results.

## Patterns and operators

| Syntax | Execution |
| --- | --- |
| `A B`, `A && B` | Sequence |
| `A &&& B` | Interleaved branches, with internal order preserved |
| `A & B` | Both branches whole, in any order |
| `A \| B` | Independent paths, possibly producing several matches |
| `A \|\| B` | Priority to the left, with alternatives kept for later failures |
| `[ ... ]` | Group with lexical scope |
| `( ... )` | Group with positional capture |
| `?`, `*`, `+`, `** 2`, `** 1..3`, `** 2..*` | Largest complete match per event |
| `??`, `*?`, `+?`, `** 1..3?` | Smallest complete match per event (including zero) |
| `?!`, `*!`, `+!`, `** 1..3!` | Every complete match per event |
| `:5min`, `[ :5min ... ]` | Window in event time, until the end of the scope |
| `OPEN ~ CLOSE BODY` | Recognizes OPEN, BODY and requires CLOSE; accepts recursion |
| `<name>`, `<alias=.name>` | Captured call |
| `<.name>` | Silent call |
| `<name(:flag)>`, `<name: :flag>` | Equivalent Raku argument forms |
| `<?{ ... }>`, `<!{ ... }>` | Zero-consumption boolean code assertion |
| `ITEM+ % SEP`, `ITEM+ %% SEP` | Separated repetition; `%%` permits a trailing separator |
| `$<name> = [ ... ]` | Named capture of an expression |
| `^` | In a window, select a recognition start for emission; otherwise subscription start |
| `$` | Wait for window closure or EOF; otherwise subscription EOF |
| `^^`, `$$` | Absolute subscription start and EOF |
| `::`, `::>` | Cut saved choices in the active `|` or `||` alternative |
| `:::`, `<commit>`, `<commit('name')>` | Cut saved choices in this pattern, the whole match, or a named caller |
| `:my $value = ...;` | Local initializer deferred to execution |
| `{ ... }` | Raku action |
| `:partition{ ... }` | Switches the partition context |
| `:ignore-unexpected`, `:!ignore-unexpected` | Ignore noise or invalidate the relevant path |

Precedence, from highest to lowest: sequence, `&&&`, `&&`, `&`, `|`, `||`. Alternatives
and conjunctions also accept the operator before the first operand, without adding
an empty operand: `| A | B`, `|| A || B`, `& A & B`, `&& A && B`, `&&& A &&& B`.

`[A B] & [C D]` allows `A B C D` and `C D A B`, but not `A C B D`. Each occurrence
belongs to a single branch per path. This is a conjunction of event sequences,
with no internal interleaving between operands. The runner explores order choices
without materializing all permutations in advance.

In `A || B`, results from B are held back while A could still complete the whole
input pattern, including the suffix after the operator. If that path fails or
expires, B can win. Commitment happens at the first complete published result of
that choice. EOF eliminates incomplete paths and releases valid alternatives;
cancellation discards held results. Without EOF, failure or window, waiting and
memory consumption can be unbounded. Held results keep the original
timestamp and may be emitted after more recent results.

`[A B] &&& [C D]` also allows `A C B D`, `A C D B`, `C A B D` and `C A D B`.
An event only advances one branch per path; ambiguous assignments create
independent paths. Each branch keeps its own subpatterns, partitions and windows.
Repeated captures are combined in the global consumption order. Variables external
to the branches are preserved across switches; each branch's local variables keep
their own state.

The quantifier policies select **complete** results from the current event,
across overlapping recognition starts of the same repeat and partition.
Without a suffix, publish the match consuming the most events; suffix `?`
publishes the match consuming the fewest, including zero when permitted;
suffix `!` publishes every completion. Repetition bounds still apply.
Ties for largest or smallest use stable path order. Combined policies have
left-to-right priority. All live starts keep growing independently even when
their current result is not published. Expiring a winner lets another valid
start win, even with the same size. EOF does not flush losing candidates,
but can resolve assertions and ordered alternatives that require end of input.

Actions run on speculative paths, as in `|`; external effects are not
transactional. Forks preserve variables, container aliases and multi
candidates without re-running actions or subscription defaults. Entry rules with no consuming path, recursion without consumption and unbounded nullable repetitions are
rejected during validation.

### Dynamic repetition bounds

`ITEM ** { expression }` evaluates the block once when that path enters the
repetition. It accepts a non-negative `Int` for an exact count or an inclusive
`Range` with non-negative integer endpoints; the upper endpoint may be `Inf`.
Invalid, inverted or exclusive bounds fail the subscription. Unbounded repetition
of a nullable item is rejected, including through nullable subpatterns.

```raku
<header=.event(:type<header>)>
<item=.event(:type<item>)> ** { $<header>.count }

# A calculated interval, exhaustive selection and separators:
<item=.event(:type<item>)> ** { 1..$<header>.count }! % <.event(:type<separator>)>
```

Blocks can read captures, pattern parameters and lexical variables. Evaluated
bounds survive forks without re-running the block; a new entry into the
repetition evaluates it again. Selection suffixes and `%`/`%%` work as with
literal bounds. Static recursion checks conservatively treat dynamic bounds as
possibly zero and possibly unbounded.

### Boolean code assertions

`<?{ expression }>` succeeds when the block returns a true value;
`<!{ expression }>` succeeds when it returns a false value. Neither consumes
an event. A false assertion rejects only its path; a thrown exception fails the
subscription, like an action error. Blocks can read captures, lexical variables
and domain attributes in the current pattern context.

```raku
<request> <response>
<?{ $<response>.timestamp - $<request>.timestamp < 2 }>
```

These blocks are evaluated when recognition reaches them, including on
speculative paths. Returning `False` from an ordinary `{ ... }` action still
does not reject a path. Like trailing actions, code assertions following a
terminal negative recognizer are deferred until its absence is confirmed.

### Separated repetitions

`ITEM+ % SEP` recognizes one or more items with a separator between consecutive
items. `ITEM+ %% SEP` also permits one final separator. `SEP` is an atom; use
`[ ... ]` for a separator sequence or alternative. Bounds and selection suffixes
belong to the item quantifier:

```raku
<chunk> ** 2..4 % <separator>
<chunk>+! %% [ <separator> <checksum> ]
```

The bounds count items; result selection counts all consumed events, including
separators. Item and separator captures accumulate as arrays. A zero-item match
never consumes a separator. Noise, partitions and windows obey the usual rules:
use `:!ignore-unexpected` when adjacent input occurrences are required.

### Stream and window anchors

| Anchor | Meaning |
| --- | --- |
| `^^` | Before the subscription's first processed input |
| `$$` | Actual subscription EOF |
| `^` | Select a recognition start in the innermost active window; otherwise `^^` |
| `$` | End of the innermost active window or EOF; otherwise `$$` |

Declare a window before its anchors: `:1h ^ ... $`. Each recognition candidate
starts its own window at its first consumed event. These are overlapping windows,
not fixed hourly buckets. Within a window, `^` does not require the subscription's
first event: unrelated input can precede the recognition. It must appear before
consumption in that same window.
`^^` cannot move to the first matching event or the first event of a partition.
The subscription start follows processed temporal order after lateness buffering;
discarded late inputs do not establish a boundary.

Window `^` also gives emission priority to the oldest completed recognition,
by its first event's timestamp, with stable input order breaking ties. Priority
is independent for each derived event type, anchor occurrence and partition key.
Incomplete older candidates do not block the first emission. Once a candidate
emits, older starts are discarded. Later starts keep evolving, but their results
are suppressed until the winner's effective window expires. The winner retains
priority even after reaching a repetition bound or failing a later assertion.
Expiration does not replay suppressed results: a successor needs a new complete
match to emit. Without window `^`, repetition selection keeps its usual behavior.

```raku
pattern TOP {
    :1h ^ :partition{ .<distro> }
    [ <item=.event(:distro(*.defined))> { ++$!count } ] ** 1..4
}
```

With a `has UInt $.count = 0` attribute, four or more matching inputs for a distro
within the winning window emit snapshots with counts `1`, `2`, `3`, `4`, all
sharing one `event-id`. The first item starts that candidate's hour and is already
counted. Reaching four does not release ownership: further inputs cannot make a
different start emit until the winner's window expires. Later starts continue
recognizing independently. Expiration itself emits nothing; a later start must
complete again to publish. Use `$` after the repetition to require a final match
at closure instead of incremental snapshots.

Both end anchors suspend recognition. Another input in the current partition
invalidates that end wait, even when unexpected events are ignored; other
partitions do not. Repetition growth can consume the next event and create a
new end wait. `$` resumes its suffix when the window closes or EOF arrives;
`$$` resumes only at EOF and fails if its window expires first. Closing a window
can confirm a new match, unlike merely promoting a suppressed candidate.
Results retain the timestamp of their last consumed event. Window closure uses
the existing event-time watermark, not a wall-clock timer.

```raku
pattern TOP {
    ^^ :!ignore-unexpected <request> <response> $$
    { # runs only after EOF confirms the end anchor
    }
}
```

Cancellation confirms neither end anchor. An enclosing window that expires
before the selected inner window invalidates its end wait. An entry pattern
must still have a consuming path; a lookbehind's historical boundary is not EOF.
Code requiring absolute subscription boundaries should use `^^` and `$$`.

### Explicit commitment

Cuts discard saved recognition choices without consuming an event:

| Syntax | Saved choices discarded |
| --- | --- |
| `::` | Choices within the innermost active `|` alternative |
| `::>` | Choices within the innermost active `||` alternative |
| `:::` | Choices made since entering the current pattern invocation |
| `<commit>` | Choices made since starting this recognition candidate |
| `<commit('name')>` | Choices made since entering the nearest active invocation of `name` |

```raku
[ <header> ::> <body> ] || <other-message>
[ <header> :: <body> ] | <other-message>
pattern message { <header> ::: <body> }
pattern payload { <header> <commit> <body> }
```

Scopes are dynamic: a cut in a subpattern can target an alternative in its
caller. `::` skips active `||` alternatives when finding its target; `::>` skips
active `|` alternatives. If no matching alternative is active, these two cuts
succeed without effect. Finishing an operand ends its active alternative scope,
but `:::` and `<commit>` can still discard choices saved before that operand
finished. Groups do not create pattern invocation boundaries.

`:::` preserves choices made by the caller before entering this invocation;
`<commit>` also removes those caller choices. Named commitment accepts the usual
argument forms, including `<commit: 'message'>`; an unknown active name or invalid
argument is an execution error. Cuts are allowed before the first consumption.

Cuts cover alternative operands, repeat growth/exit decisions, unordered
permutations and ambiguous shuffle assignments within the selected scope. Choices
created after a cut remain available. A cut does not publish a result by itself.
If the selected path later fails or expires, discarded choices cannot return.
Different recognition starts, including starts in different partitions, keep
independent choice identities. Already published results are not retracted.

EEL's `|` explores independent paths rather than performing Raku's
longest-token matching; `::` supplies the corresponding alternative cut scope.
Recognition explores speculative paths, and the first executed cut in stable
path order commits its saved choices, including when a higher-priority path is
still waiting for future input. Actions already run are not rolled back.
Assertion recognizers have isolated choice histories; cuts inside them affect
the auxiliary recognition, without cutting the observing main path.

## Captures and metadata

`$<request>.id` delegates to the field of the hash or the method of the captured
object, including positional and named method arguments. `.data` preserves the
original event and allows explicit access. Existing structural methods on the
capture, such as `.index`, `.made` and `.timestamp`, take precedence.

Captures of subpatterns are separate `Event` objects from the context that runs their
actions: they preserve subcaptures, `.made`, data and metadata without inheriting the
domain attributes of the derived type. Actions keep using `$!attribute` in the context
of the type. Groups `(…)` use the compiled numbering, starting from zero, within each
pattern; `$0`, `$1` and `$result[0]` give access to the captures. Repetitions accumulate
captures, and subpatterns/protos preserve the positional lists when returning.

`$<name> = ATOM` captures an expression without adding a positional slot.
The right-hand side includes its quantifier and separator, if present; use
`$<name> = [ ... ]` to capture a sequence or alternative. For example:

```raku
$<exchange> = [ <request> <response> ]
$<batch> = <item>+ % <separator>
```

The captured `Event` exposes the subcaptures, positional captures, `.made`, data
and timestamp at the end of that expression. Captures made inside the expression
remain available in the enclosing pattern too, as with positional groups.
Repeating the assignment accumulates named group captures in an array. As with
other groups, partition, window and noise settings are restored when it ends.

Every event has `timestamp` and `event-id`. The timestamp is normalized as `Instant`;
it accepts `Instant`, `DateTime`, ISO 8601 text with a time zone or a Unix number
in seconds. When absent, it uses the instant of entry. To assign to a DateTime
attribute use `has DateTime() $.start` or `$<request>.timestamp.DateTime`. Original
objects and hashes are not modified: the metadata lives in the snapshot and in
captures.

`event-id` is UUIDv7, preserved when received valid or generated when absent.
Generation is monotonic and synchronized within the process; between processes,
uniqueness is probabilistic, without coordination. The ID orders by generation,
not by the time of historical logs. Each recognition candidate receives a new ID,
which is preserved as it grows and emits successive snapshots. Different starts
have different IDs, including when an expired winner is replaced by another
candidate. Each emitted snapshot has the timestamp of its last consumed event;
previously emitted snapshots remain unchanged.

### Separate Actions and semantic values

Pass an Actions object with `.match(Type, :actions(MyActions.new))` or
`EEL::Runner.new(:patterns[Type], :actions(MyActions.new))`. When a pattern
invocation completes, its corresponding method receives the current `Event`
as `$/`. Modules defining Actions with `make` should import `EEL`; alternatively,
use the explicit `$/.make(VALUE)` method. Missing methods are ignored. Subpattern Actions run before their
captures return to the caller, including for silent calls. Inline actions run
first; the external Action can replace their semantic value.

```raku
event Batch {
    pattern TOP {
        <header=.event(:type<header>)>
        <item> ** { $<header>.count }
    }
    pattern item { <value=.event(:type<item>)> }
}
class BatchActions {
    method item($/) { make $<value>.value }
    method TOP($/) { make $<item>.map(*.made).Array }
}
my $results = $input.match(Batch, :actions(BatchActions.new));
$results.made.tap(-> $values { say $values });
```

`make VALUE` (or `$/.make(VALUE)`) sets the semantic value of the current Event.
`.made` reads it and `.ast` is an alias. A later `make` replaces the previous
value. The exported `make` also supports ordinary Raku regex and Grammar usage.
On a `Supply`, `.made` and `.ast` project each published result to that value,
including successive published updates of the same recognition. They do not
publish every speculative call to `make`; results without a semantic value
project to `Any`. When using `:reemit`, projection also applies to re-emitted inputs.

Like inline actions, external Actions can execute on speculative paths that
later fail. Their external effects are not rolled back. An Actions instance is
shared by the subscriptions using it; use a separate instance for independent
mutable action state. Exceptions fail the subscription through `quit`.

## Partitions, scopes and windows

`:partition{ .<a>, .<b> }` preserves a typed composite key, unlike
`:partition{ "{ .<a> } { .<b> }" }`. The block receives the event in `$_`, and may access
previous captures and variables. The expected key comes from the last consumed event;
before the first consumption, it is pinned to the first event actually recognized.

The next declaration replaces the partition. Groups and subpatterns restore the
previous one when returning; forks keep independent state. Events of another key do
not advance or invalidate that path, including in strict mode. Undefined values
share one partition; tuples and maps are structurally frozen, without using
`.Str` as identity. Cyclic keys cause an error. Storage remains in memory;
the runner uses internal indexes of equality, types, partitions and ranges, without plugins.

Windows are lexical adverbs: `pattern TOP { :5min ... }` or `[ :1.5h ... ]`.
They start at the first event consumed after the declaration and end with the scope;
nested windows must be satisfied simultaneously.

Units: `ms`, `s`, `min`, `h`, `d`, `m`, `y`. Aliases: `millisecond(s)`, `sec`,
`second(s)`, `minute(s)`, `hour(s)`, `day(s)`, `month(s)`, `year(s)`. `m` is a month;
a minute uses `min`. Months are 30 days and years 365 days. Non-negative durations
can be decimal, but must represent an integer number of nanoseconds.

Windows use **event timestamps** and exclusive upper bounds. The runner keeps
a global watermark per subscription: the greatest received timestamp minus `:lateness`,
a finite, non-negative duration in seconds representable in integer nanoseconds, default zero. The queue is ordered
by timestamp and then by arrival. The snapshot is prepared when the input is received,
before any buffering. Inputs older than the already committed watermark are
discarded with a diagnostic of ID, timestamp and boundary; ties on the boundary
are still accepted. With `:reemit`, only processed inputs are published, in
temporal order, using their original snapshots.

The watermark advances only through input. Idle flow and `.pending` do not advance
time: a window is not closed by the local clock. A deadline closes when the watermark reaches it, before processing that event. EOF drains the queue and ends incomplete
paths; cancellation discards buffers and held conclusions. Expiring a
window does not call `FAILGOAL`.

A window on TOP limits the duration of paths, but partitioning and time do not
impose hard limits on the number of paths, events or memory per window.
The CLI's polling and `--merge-wait` keep using a monotonic clock, regardless
of the matcher's windows.

## Zero-consumption assertions

`<?B>` requires B to recognize, while leaving those same events available to
subsequent steps. `<!B>` forbids B from completing until the next step consumes
an occurrence. B may be a query or subpattern with sequences, alternatives,
recursion and proto/multi dispatch. Arguments use the usual call syntax.

```raku
<A> <?pair> <B>       # pair may verify B C; B is consumed once
<A> <!forbidden> <C> # forbidden wins if it also completes on C
```

When unexpected events are ignored, negative recognizers keep watching until
the next step consumes. In strict mode, the next event of the partition must
allow that consumption. Incomplete negative prefixes are discarded at that
boundary; a sequence that would finish after it does not invalidate the match.

Terminal negation, such as `<A> <!B>`, waits for a window deadline or EOF. Idle
time does not confirm it; cancellation discards it. An occurrence exactly at the
deadline can still invalidate it. Incomplete positive assertions fail on EOF or
expiration. Windows retain their event-time and watermark semantics.

New root paths start where an initial auxiliary query can begin recognizing,
just like ordinary initial waits; earlier unrelated inputs are not replayed
into that new root match.

Named forms are `<data=?event: :area(*.defined)>` and `<absence=!B>`. Positive
captures expose the recognized event/submatch. Negative captures expose
`EEL::Absence` (also exported as `Absence` by `use EEL`) with `pattern`, `started-at`, `confirmed-at`, `reason` (`next-step`,
`window` or `eof`) and `witness`. The witness is the original event that allowed
the next consumption; it is `Nil` for window/EOF. A window confirmation uses its
deadline; EOF uses the timestamp of the last processed input, without wall time.

To use a negative capture in an action, put the action after the step that
confirms the absence. Terminal trailing actions are deferred until confirmation.
Unnamed auxiliary captures and state changes inside B do not escape to the
main path. Auxiliary actions are speculative, like alternative-path actions;
external effects are not rolled back.

The runner retains prepared snapshots needed by positive assertions and replays
them only into the suspended continuation. It does not duplicate inputs,
starters or `:reemit`, and preserves identity, ordinals and timestamps. A result
can be published after the timestamp of its last consumed event. Without a
window, pending assertions can retain history indefinitely. See
[Fire risk with assertions](examples/fire-risk-2.raku).

### Inline lookaround

`<?before P>` and `<!before P>` accept an inline EEL pattern body and use
the same future-recognition semantics as `<?name>` and `<!name>`.
For example, `<A> <?before <B> <C>> <B>` verifies the future pair without
consuming it on the main path. Negative observation ends at the next consumption,
or at a window deadline/EOF when terminal.

`<?after P>` requires P to recognize in the processed history, ending at the
current boundary; `<!after P>` requires no such recognition. After a consumption,
the boundary includes that event. At a candidate start it precedes the proposed
input. Internal noise follows `:ignore-unexpected`, but trailing noise does not
move the end of P. Bodies have isolated lexical scopes and captures; their actions
are speculative, like named assertions.

Patterns using `after` retain snapshots from the beginning of the subscription,
including events preceding the candidate. This history can grow without bound
until the runner finishes, fails or is cancelled. Replay does not reemit inputs.

## Indexed search

See [Runtime architecture](docs/runtime-architecture.md) for how definitions,
continuations, wait subscriptions, indexes and result selection fit together.

Field conditions have a presence index, including opaque predicates: missing
fields are rejected before invoking their predicates. The forms `*.defined`,
`!*.defined` and `*.defined.not` also have definition-state indexes. An absent
field differs from a present undefined value; `False`, `0` and `''` are defined.
Custom objects remain conservative candidates, and the original predicate makes
the final decision without running user methods during index lookup. Arbitrary
blocks such as `{ .defined }` receive presence filtering only.

The index starts with a selective anchor and can intersect its hits with
secondary equality, type, presence, definition and numeric interval restrictions
on other fields. Secondary numeric checks use exact `Int`, `Rat` and `FatRat`
values; other representations retain coercive or custom predicate evaluation.
Cached interval checks distinguish both bounds, open/closed endpoints and
coercion policy.
Checks are cached per input and never invoke opaque predicates. Disjunctive plans
remain alternatives. Low-yield workloads skip secondary checks, with periodic
probes to reconsider; final predicates always validate the remaining candidates.
Index statistics include `intersected` (secondary checks) and `pruned` (anchor
hits rejected before predicate evaluation).

Literal string predicates such as `:path(*.starts-with('/api/'))` use a
per-field prefix trie. Lookup follows the input string's Unicode graphemes and
returns every registered prefix along the path, including the empty prefix.
Removing subscriptions prunes unused trie nodes. Non-string values retain
conservative candidates, so custom methods and exceptions are handled by the
final predicate. Dynamic prefixes and arbitrary blocks retain callable fallback.
Literal `:path(*.ends-with('.json'))` uses a reverse trie, walking Unicode
graphemes from the end without reversing text into a new normalized string.
It has the same fallback and cleanup guarantees. Prefix and suffix conditions
can be combined on the same field. Index statistics expose `prefix-nodes` and
`suffix-nodes` for memory and cleanup inspection.

Subscriptions are identified individually. Equalities use hashes; numeric bounds
and windows use AVL trees of ranges. A deadline queue removes
expired waits without scanning all continuations. Strict mode also consults
the relevant partitions, even when no query accepts the event.

The slang recognizes simple comparisons and chains such as `:value(1 < * <= 42)`.
Their bounds, including those obtained from captures, are evaluated when the wait is
created. The numeric indexes use finite `Int`, `Rat` and `FatRat`; other values keep
going through residual evaluation. Arbitrary predicates such as `:value{ check($_) }`
also keep working. Missing fields never satisfy a condition.

Junctions can combine values and predicates:

```raku
<.event(:value(any(1, 5, * > 40)))>
<.event(:value(all(* > 1, * <= 42)))>
<.event(:value(* == any(1, 5)))>
```

`any`, `all`, `one` and `none` keep their boolean meanings. Direct values
use the typed equality of the field; numeric comparisons use the Raku operators.
Explicit Junctions preserve their structure in the compiler; opaque Junctions,
`one` and `none` use residual filters when necessary, without internal introspection.

**Partition predicates and extractors must be pure.** The search may skip or
reuse evaluations. Explicit actions of the patterns keep executing in
the order of their respective paths. Simple extractors, such as `.<session>` and
tuples of fields, share the computation per event; arbitrary closures keep
separate contexts. Custom types or operators are not reinterpreted
as standard comparisons. There is no sublinear cost guarantee when almost all
queries accept an event or when their conditions are opaque.

`raku -Ilib tools/benchmark-indexes.raku --size=1000 --rounds=50` compares indexed
and linear search in equalities, ranges, overlap, opaque predicates,
partitions and expiry. It shows time and candidates; the tests verify reduction
of candidates without depending on time thresholds of the machine.

### Execution optimizations

Each conjunction chooses a selective anchor, such as an ID instead of the whole bucket
of an event type. The other constraints are confirmed by the matcher. The
anchors are re-evaluated at growth/shrinkage thresholds of the population, and
numeric bounds of the same field are merged into a single range.

Storage estimates the cost per entry and chooses between index and scan of the
eligible set. It uses cardinalities, a moving average of selectivity and
hysteresis; the scan makes periodic probes to follow changes in load.
Ordered snapshots are reused until the next change, without including
subscriptions created during the current round.

Starters are also indexed. Their actions keep executing at
the same moment, and new starters can only consume the next occurrence. The
lateness buffer uses a heap keyed by `(timestamp, arrival order)`, preserving ties.
Held results are linked to the selection/alternative groups; changes
in independent groups do not trigger a scan of all results.

Forks reuse the structural traversal of frames. Definitions with constant arguments,
without effective parameters, actions, local variables, partitions or
subcalls can share the compiled instructions. Contexts and mutable
containers are still copied; the general path rematerializes the closures.
This is not unrestricted sharing of match state.

To measure these stages separately:

```sh
raku -Ilib tools/benchmark-optimizations.raku --size=1000 --repeats=7 --rounds=5
raku -Ilib tools/benchmark-optimizations.raku --size=10000 --only=anchor
```

The benchmark uses warm-up and medians, presents work counters and
allows `--only=anchor|interval|overlap|opaque|buffer|starters|forks|retained`.
The baselines are linear scan, repeated sorting of the buffer and internal paths
without the optimization under analysis; they are not promises of gain for every load.
Large buffers make the sorting baseline especially slow.
The [local measurements and their baselines](tools/benchmark-results.md) are recorded
for comparison, without temporal thresholds in CI.

## Proto and multi

```raku
proto pattern response {*}
pattern response:sym<ok> { <.event(:status(200))> }
multi pattern response:sym<error> { <.event(:status(* >= 400))> }
```

`<response>` considers all applicable symbolic candidates. They represent
independent paths, without waiting for longest-token matching. `:sym` is a label,
without automatically creating a condition on fields. The proto body is `{*}`.

`multi pattern item(Int $n)` uses native signature dispatch, including implicit
protos, names, defaults and `where`. Mismatched arguments raise an error;
mismatched events merely fail to match. Families can be inherited,
extended or overridden by symbolic name, including in `proto pattern TOP`.

## CLI and examples

`bin/eel.raku` reads finite files or stdin, merges temporally across sources and
publishes recognitions as JSONL. `--follow` tails several files with configurable
tolerance. `--transform Module::function` allows converting text into events with
Grammar, regex, split or Raku code. See the [CLI guide](examples/cli/README.md)
and the [catalog of runnable examples](examples/README.md).

The matcher uses `EEL::Runner` and `EEL::MemoryStorage`.

### Inline event definitions

```sh
eel -e 'event Hot { pattern TOP { <.event(:type<temperature>, :value(* > 40))> } }' log.jsonl
```

`-e CODE`, `--eval CODE` and `--eval=CODE` compile Raku code with `use EEL`
automatically enabled. Repeat the option to append snippets in order, sharing
helpers and constants. All declared inline events are selected without requiring
exports; `--event` filters the selection. Inline definitions can be combined
with `--module`; module-only discovery still uses exported events. Imported
events are not automatically selected by inline discovery. Code runs normally,
including initializers; its output goes to stderr, leaving stdout for JSONL.
Compilation and selection errors exit with status 2 before reading the input.
