# CLI JSONL

Run from the repository root:

```sh
raku -Iexamples/cli bin/eel.raku --module LogEvents --event Login examples/cli/start.jsonl examples/cli/finish.jsonl
```

Output (key order may vary):

```json
{"type":"LogEvents::Login","id":42,"timestamp":"1970-01-01T00:00:02Z","event-id":"01900000-0000-7000-8000-000000000001"}
```

The UUID in the output varies with each run. The start is in the first file and the finish in the second. The matcher keeps
state across files. They are read concurrently and merged by timestamp,
preserving the internal order of each file. Each input must be sorted;
regressions in finite mode exit with status 1. Ties use the file position
in the arguments and then the line number. Without paths, the input is stdin:

```sh
cat examples/cli/start.jsonl examples/cli/finish.jsonl | raku -Iexamples/cli bin/eel.raku --module LogEvents --event Login
```

To tail a file from the beginning:

```sh
raku -Iexamples/cli bin/eel.raku --module LogEvents --event Login --follow app.jsonl
```

`--follow` receives one or more existing files. New lines are watched by
polling every 100 ms; fragments and UTF-8 characters are accumulated until the newline.
Rotation by replacement and observable truncations are tracked while keeping the
matcher. The path may disappear temporarily during rotation. Ctrl+C
cancels all readers and the recognition, without calling FAILGOAL for incomplete events.

```sh
raku -Iexamples/cli bin/eel.raku --module LogEvents --follow --merge-wait 1 app-a.jsonl app-b.jsonl
```

The merge waits up to `--merge-wait SECONDS` (default 1, only in follow) for silent
sources. If all of them have a next event, the smallest one is published immediately.
After the wait, it releases the smallest available one. Later events with a timestamp
lower than the last released one are ignored with a warning. Regressions within a
file in follow are also ignored; rotation does not restart the time reference.
There is no guarantee of recovering events that arrive after that tolerance.

Use modules with public declarations (`our event Login`) and no demos that
run on load. Repeat `--module` and `--event` to select several types.
If you give only `--event Login`, the CLI tries to load the module `Login` and
selects that event. With several `--event`s, it loads the corresponding modules.
If you give only `--module LogEvents`, it uses all events exported by the
module with `is export` (including exports with tags). Public events without export
remain available when explicitly selected with `--event`.
A module without exported events raises an error when there is no `--event`.

For example, the events of `LogEvents` are exported, so it is enough to write:

```sh
raku -Iexamples/cli bin/eel.raku --module LogEvents examples/cli/start.jsonl examples/cli/finish.jsonl
```

Ambiguous names require qualification, such as `--event LogEvents::Login`. Module
paths are the usual Raku ones (`-I` before the script name).

Each input line must be a JSON object. Empty lines are ignored;
invalid lines produce warnings with file and line number on stderr and are
ignored. The last record of a finite input may lack a newline.

stdout contains JSONL of the recognitions, with `type` reserved for the qualified
class name and its public domain attributes. Captures and internal
state are not published. Dates become strings and undefined values become null.
Cycles, callables and non-serializable values cause an error. Prints from the modules
and actions are directed to stderr.

JSONL output can be consumed by another CLI as hashes with type tags; there
is no automatic object reconstruction. Text transformations are described below.

Status: 0 on completion, 2 for invalid configuration, 1 for execution failure,
130 for SIGINT and 143 for SIGTERM in follow. Temporary EOF of follow does not end
matches; in finite mode, only the end of all inputs ends the Supply.

All events have `timestamp` and `event-id`. The timestamp accepts ISO 8601 with
a time zone or a Unix number in seconds (including fractions); when absent, it uses the
instant of reading. `--timestamp-field FIELD` selects another input field. Present
but invalid values are warned and ignored. Stdin may participate as `-` a
single time in finite mode.

`event-id` is UUIDv7: preserved when valid or generated when absent. Generated IDs
grow within the process; their uniqueness across processes is probabilistic, with no
global coordination. They order by generation of the identity, not by the time of
historical logs. Derived events receive a new identity and the timestamp of the last
consumed event. The output always includes both metadata.

In `Supply.match`, original objects and hashes remain untouched; the metadata
lives in the snapshots and captures. EEL events expose `.timestamp` (`Instant`) and
`.event-id`. Timewindows use event timestamps. The runner's watermark advances with the input; the CLI's polling and `--merge-wait` keep using monotonic time.

## Converting text logs

Use `--transform Module::function` to adapt each line. The function receives
`Str $line`, `:$origin` and `:$line-number`. It returns an event Hash/object,
a finite List/Array of events, or `Nil` to ignore the line. It also receives
empty lines; the adapter decides what to do. Callables and scalars are not events.
An exception or an invalid value/metadata discards the whole line with a warning.

The adapters in `LogTransforms.rakumod` implement Grammar with Actions, regex,
split, returning an object and generating two events from the same line:

```sh
raku -Iexamples/cli bin/eel.raku --module LogEvents --event Login --transform LogTransforms::grammar-line examples/cli/login.log
raku -Iexamples/cli bin/eel.raku --module LogEvents --event Login --transform LogTransforms::regex-line examples/cli/login.log
raku -Iexamples/cli bin/eel.raku --module LogEvents --event Login --transform LogTransforms::split-line examples/cli/login.log
raku -Iexamples/cli bin/eel.raku --module LogEvents --event Login --transform LogTransforms::object-line examples/cli/login.log
raku -Iexamples/cli bin/eel.raku --module LogEvents --event Login --transform LogTransforms::burst-line examples/cli/burst.log
```

Each command recognizes the Login with id 42. The timestamp comes from the last event consumed
and the UUID varies per run. Exported or public functions can be selected.
The lines of each file are transformed sequentially, but several files
may run the adapter concurrently. The transformer must tolerate this usage.
The generated events follow the same merge, monotonicity,
`--timestamp-field` and `--follow` delay rules; the order within each list is preserved.
Objects keep identity, and the matcher reuses the snapshot prepared by the CLI.
