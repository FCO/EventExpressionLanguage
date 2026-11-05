use lib 'lib';
use Test;
use JSON::Fast;
use EEL::CLI;

sub cli(@arguments, Str :$input = '') {
    my $p = run $*EXECUTABLE, '-Iexamples/cli', '-It/lib', 'bin/eel.raku', |@arguments, :in, :out, :err;
    try { $p.in.print($input); $p.in.close; Nil }
    my $out = $p.out.slurp(:close); my $err = $p.err.slurp(:close);
    ($p.exitcode, $out, $err)
}
my @base = '--module', 'LogEvents', '--event', 'Login';
my ($status,$out,$err) = cli([|@base,'examples/cli/start.jsonl','examples/cli/finish.jsonl']);
is $status,0,'multiple files complete normally';
is from-json($out)<id>,42,'match spans input files';
is from-json($out)<timestamp>,'1970-01-01T00:00:02Z','derived timestamp comes from final event';
ok from-json($out)<event-id>.chars == 36,'derived event has UUID';
is $err,'','valid input is quiet';
($status,$out,$err) = cli(@base, :input(('bad','42','',q[{"type":"start","id":7}],q[{"type":"finish","id":7}]).join("\n")));
is $status,0,'invalid records are skipped and final newline is optional';
is from-json($out)<id>,7,'stdin recognized';
like $err, /'<stdin>:1'/,'malformed JSON diagnostic includes line';
like $err, /'<stdin>:2'/,'non-object diagnostic includes line';
($status,$out,$err) = cli(['--module=LogEvents','--event=LogEvents::Login'], :input((q[{"type":"start","id":8}],q[{"type":"finish","id":8}]).join("\n")));
is $status,0,'qualified names and equals syntax work';
is from-json($out)<id>,8,'qualified selection recognizes';
($status,$out,$err) = cli(['--event','CLIInferred'], :input(q[{"type":"inferred"}]));
is $status,0,'event alone loads a module with the same name';
is from-json($out)<type>,'CLIInferred::CLIInferred','inferred module selects the requested event';
($status,$out,$err) = cli(['--module','CLIInferred','--module','CLIOther'],
    :input(<inferred additional hidden exported other>.map({ to-json(%(type=>$_), :!pretty) }).join("\n")));
is $status,0,'module alone selects exported events';
is-deeply $out.lines.map({ from-json($_)<type> }).sort.Array,
    ['CLIInferred::Additional','CLIInferred::CLIInferred','CLIOther::Exported'],
    'includes default and tagged exports across modules, excludes unexported events';
($status,$out,$err) = cli(['--module','JSON::Fast']);
is $status,2,'module without exported events is a configuration error';
like $err, /'No exported events'/,'empty event selection is explained';
($status,$out,$err) = cli(['--event','CLIMissingModule']);
is $status,2,'failed inferred module load is a configuration error';
($status,$out,$err) = cli(['--module','CLIInferred','--event','Hidden'], :input(q[{"type":"hidden"}]));
is $status,0,'explicit selection still permits public unexported events';
is from-json($out)<type>,'CLIInferred::Hidden','explicit event selection takes precedence over exports';
for [], [|@base,'--follow'], [|@base,'--unknown'], ['--module','LogEvents','--event','Missing'] -> @bad {
    ($status,$out,$err) = cli(@bad);
    is $status,2,'invalid configuration exits 2';
    is $out,'','configuration errors do not pollute stdout';
    ok $err.chars > 0,'configuration diagnostic goes to stderr';
}
my $dir = $*TMPDIR.add("eel-reader-{$*PID}"); $dir.mkdir;
my $path = $dir.add('log');
LEAVE { if $dir.defined && $dir.d { .unlink for $dir.dir; $dir.rmdir } }
$path.spurt('{"value":');
my $reader=Reader.new(:$path);
is $reader.poll.elems,0,'partial line waits';
$path.spurt('1}' ~ "\n", :append);
my @lines=$reader.poll;
is @lines[0][1].decode,'{"value":1}','append completes prior fragment';
is @lines[0][0],1,'line numbering begins at one';
$path.rename($dir.add('old'));
$path.spurt(q[{"value":2}] ~ "\n");
@lines=$reader.poll;
is @lines[0][1].decode,'{"value":2}','rotation opens replacement';
is @lines[0][0],1,'rotation resets line number';
$path.spurt(q[{}] ~ "\n");
@lines=$reader.poll;
is @lines[0][1].decode,'{}','truncation restarts the file';
$path.unlink;
is $reader.poll.elems,0,'temporary disappearance waits';
$path.spurt(q[{"back":true}] ~ "\n");
is $reader.poll[0][1].decode,'{"back":true}','path recreation resumes';
$reader.close;
my $unicode='{"text":"é"}'.encode('utf8');
$path.spurt(Buf.new($unicode.subbuf(0,10).list));
$reader=Reader.new(:$path);
is $reader.poll.elems,0,'UTF8 fragment waits';
my $append = $path.open(:a,:bin); $append.write(Buf.new(|$unicode.subbuf(10).list,10)); $append.close;
is from-json($reader.poll[0][1].decode)<text>,'é','UTF8 bytes reassemble before decoding';
$reader.close;
my %cycle; %cycle<self> := %cycle;
throws-like { encode-event(%cycle) },X::AdHoc,message=>/'cycle'/,'serialization detects cycles';
is encode-event(DateTime.new('2026-01-01T00:00:00Z')), '2026-01-01T00:00:00Z','dates are strings';
($status,$out,$err) = cli(['--module','LogEvents','--module','CLIOther','--event','Login']);
is $status,2,'ambiguous names are rejected';
like $err, /'Ambiguous'/,'ambiguity diagnostic requests qualification';
for 'Exported' => 'exported', 'CLIOther::Group::Nested' => 'nested' -> $choice {
    ($status,$out,$err) = cli(['--module','CLIOther','--event',$choice.key], :input(to-json({type=>$choice.value}, :!pretty)));
    is $status,0,'exported or nested event loads';
    ok from-json($out)<type>.contains($choice.key.split('::').tail), 'selected event emitted';
}
($status,$out,$err) = cli(['--module','CLIOther','--event','Noisy'], :input(q[{"type":"noisy"}]));
is from-json($out)<value>,3,'stdout remains JSON despite action prints';
like $err, /'action diagnostic'/,'action prints go to stderr';
($status,$out,$err) = cli(['--module','CLIOther','--event','Cyclic'], :input(q[{"type":"cycle"}]));
is $status,1,'serialization failures exit 1';
is $out,'','serialization failure emits no partial JSON';

sub check-follow($signal, $expected) {
    $path.spurt(q[{"type":"ping"}] ~ "\n" ~ q[{"type":"start","id":99}] ~ "\n");
    my $ready = Promise.new;
    my $matched = Promise.new;
    my $proc = Proc::Async.new($*EXECUTABLE, '-Iexamples/cli', 'bin/eel.raku',
        '--module','LogEvents','--event','Login','--event','Heartbeat','--follow',$path.Str);
    my $errors = '';
    $proc.stdout.lines.tap(-> $line {
        my $event = from-json($line);
        $ready.keep(True) if $event<type> eq 'LogEvents::Heartbeat' && $ready.status == Planned;
        $matched.keep($event<id>) if $event<type> eq 'LogEvents::Login' && $matched.status == Planned;
    });
    $proc.stderr.tap(-> $text { $errors ~= $text });
    my $task = $proc.start;
    LEAVE { try { $proc.kill(SIGKILL) if $task.status == Planned; Nil } }
    await Promise.anyof($ready, Promise.in(5));
    is $ready.status,Kept,'follow processes existing content';
    $path.spurt(q[{"type":"finish","id":99}] ~ "\n", :append);
    await Promise.anyof($matched, Promise.in(5));
    is $matched.status,Kept,'follow recognizes appended content';
    is $matched.result,99,'follow preserves matcher state';
    $proc.kill($signal);
    await Promise.anyof($task, Promise.in(5));
    is $task.status,Kept,'follow terminates promptly';
    is $task.result.exitcode,$expected,'follow returns signal status';
    is $errors,'','follow stops without missing-goal errors';
}
check-follow(SIGINT,130);
check-follow(SIGTERM,143);
done-testing;
