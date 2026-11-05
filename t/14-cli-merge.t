use lib 'lib';
use Test;
use JSON::Fast;
my $dir=$*TMPDIR.add("eel-merge-{$*PID}"); $dir.mkdir;
LEAVE { if $dir.defined && $dir.d { .unlink for $dir.dir; $dir.rmdir } }
my $a=$dir.add('a'); my $b=$dir.add('b');
sub records(*@times) { @times.map({ to-json(%(type=>'inferred',timestamp=>$_),:!pretty) }).join("\n") ~ "\n" }
my @command=$*EXECUTABLE,'-It/lib','bin/eel.raku','--module','CLIInferred','--event','CLIInferred';
sub finite(*@extra) {
    my $p=run |@command,|@extra,:out,:err;
    my $out=$p.out.slurp(:close); my $err=$p.err.slurp(:close);
    ($p.exitcode,$out,$err)
}
$a.spurt(records(2,4)); $b.spurt(records(1,3));
my ($status,$out,$err)=finite($a.Str,$b.Str);
is $status,0,'finite merge succeeds';
is-deeply $out.lines.map({ DateTime.new(from-json($_)<timestamp>).posix.Int }).Array,[1,2,3,4],'files merge by event time';
is $err,'','valid merge is quiet';
$a.spurt(records(1));
$b.spurt(q[{"type":"additional","timestamp":1}] ~ "\n");
($status,$out,$err)=finite('--event','Additional',$a.Str,$b.Str);
is-deeply $out.lines.map({ from-json($_)<type> }).Array,
    ['CLIInferred::CLIInferred','CLIInferred::Additional'],'equal times use argument order';
$a.spurt(''); $b.spurt(records(3));
($status,$out,$err)=finite($a.Str,$b.Str);
is $out.lines.elems,1,'empty source does not block finite merge';
$a.spurt(records(2,1)); $b.spurt('');
($status,$out,$err)=finite($a.Str,$b.Str);
is $status,1,'finite timestamp regression fails';
like $err,/'timestamp regression'/,'regression diagnostic';
$a.spurt(q[{"type":"inferred","time":5}] ~ "\n");
($status,$out,$err)=finite('--timestamp-field','time',$a.Str);
is DateTime.new(from-json($out)<timestamp>).posix.Int,5,'custom timestamp field';
$a.spurt(q[{"type":"inferred","timestamp":"bad"}] ~ "\n" ~ records(6));
($status,$out,$err)=finite($a.Str);
is $status,0,'invalid timestamps are skipped';
is $out.lines.elems,1,'valid record after invalid time is emitted';
like $err,/'a:1'/,'invalid timestamp has origin';
$a.spurt(records(2)); $b.spurt(records(1));
my $proc=Proc::Async.new(|@command,'--follow','--merge-wait','0.1',$a.Str,$b.Str);
my @seen; my $errors=''; my $initial=Promise.new; my $advanced=Promise.new;
$proc.stdout.lines.tap(-> $line {
    @seen.push(DateTime.new(from-json($line)<timestamp>).posix.Int);
    $initial.keep(True) if @seen.elems==2 && $initial.status==Planned;
    $advanced.keep(True) if @seen.elems==3 && $advanced.status==Planned;
});
$proc.stderr.tap(-> $s { $errors ~= $s });
my $task=$proc.start;
LEAVE { try $proc.kill(SIGKILL) if $task.defined && $task.status==Planned }
await Promise.anyof($initial,Promise.in(5));
is $initial.status,Kept,'silent follow source does not block indefinitely';
is-deeply @seen.Array,[1,2],'initial follow content merges in order';
$b.spurt(records(1.5,3),:append);
await Promise.anyof($advanced,Promise.in(5));
is $advanced.status,Kept,'follow consumes append after late event';
is-deeply @seen.Array,[1,2,3],'late event never enters matcher';
$proc.kill(SIGTERM);
await Promise.anyof($task,Promise.in(5));
is $task.status,Kept,'all follow readers terminate';
is $task.result.exitcode,143,'multiple follow termination status';
like $errors,/'ignored late event'/,'late event is diagnosed';
done-testing;
