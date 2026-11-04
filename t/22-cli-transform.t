use lib 'lib';
use Test;
use JSON::Fast;
sub cli($function, Str :$input!, :@events = ['--module','LogEvents','--event','Login'], :@files = []) {
    my $p=run $*EXECUTABLE,'-Iexamples/cli','-It/lib','bin/eel.raku',|@events,'--transform',$function,|@files,:in,:out,:err;
    try { $p.in.print($input); $p.in.close; Nil }
    my $out=$p.out.slurp(:close); my $err=$p.err.slurp(:close);
    ($p.exitcode,$out,$err)
}
for <grammar-line regex-line split-line object-line> -> $name {
    my ($status,$out,$err)=cli("LogTransforms::$name", :input("1 start 42\n2 finish 42\n"));
    is $status,0,"$name succeeds";
    is from-json($out)<id>,42,"$name recognizes Login";
    is from-json($out)<timestamp>,'1970-01-01T00:00:02Z',"$name preserves event time";
    is $err,'',"$name is quiet";
}
my ($status,$out,$err)=cli('LogTransforms::burst-line',:input("1 login 42\n"));
is from-json($out)<id>,42,'one line can produce multiple events';
($status,$out,$err)=cli('LogTransforms::grammar-line',:input("\nbad\n1 start 42\n2 finish 42\n"));
is $status,0,'transformation errors do not abort input';
is from-json($out)<id>,42,'valid lines survive invalid transform';
like $err,/'<stdin>:2'/,'transformation diagnostic has original line number';
my @inferred='--event','CLIInferred';
($status,$out,$err)=cli('TransformFixture::hidden',:events(@inferred),:input("line\n"));
is $status,0,'default exported private function is supported';
is $out.lines.elems,1,'exported transform emits';
($status,$out,$err)=cli('TransformFixture::invalid',:events(@inferred),:input("line\n"));
is $status,0,'invalid output warns and continues';
is $out,'','line is discarded atomically';
like $err,/'<stdin>:1'/,'invalid returned event has source diagnostic';
($status,$out,$err)=cli('TransformFixture::endless',:events(@inferred),:input("line\n"));
is $status,0,'lazy infinite output is rejected without hanging';
is $out,'','infinite list produces no partial output';
($status,$out,$err)=cli('TransformFixture::measured',:events(['--module','TransformFixture','--event','Seen']),:input("line\n"));
is $status,0,'object snapshot reused by runner';
is $out.lines.elems,1,'object recognized with identity preserved';
is $err,'','no duplicate getter reads';
my $dir = $*TMPDIR.add("eel-transform-{$*PID}"); $dir.mkdir;
LEAVE { if $dir.defined && $dir.d { .unlink for $dir.dir; $dir.rmdir } }
my $a=$dir.add('a.log'); my $b=$dir.add('b.log');
$a.spurt("1 start 42\n"); $b.spurt("2 finish 42\n");
($status,$out,$err)=cli('LogTransforms::split-line',:input(''),:files([$a.Str,$b.Str]));
is from-json($out)<id>,42,'transformed files merge into one matcher';
is $status,0,'parallel transformed files succeed';
$a.spurt("0 ping 0\n1 start 42\n"); $b.spurt('');
my $proc=Proc::Async.new($*EXECUTABLE,'-Iexamples/cli','bin/eel.raku',
 '--module','LogEvents','--event','Login','--event','Heartbeat','--transform','LogTransforms::grammar-line',
 '--follow','--merge-wait','0.05',$a.Str,$b.Str);
my $ready=Promise.new; my $matched=Promise.new;
my $errors='';
$proc.stdout.lines.tap(-> $line {
 my $v=from-json($line);
 $ready.keep(True) if $v<type> eq 'LogEvents::Heartbeat' && $ready.status==Planned;
 $matched.keep($v<id>) if $v<type> eq 'LogEvents::Login' && $matched.status==Planned;
});
$proc.stderr.tap(-> $text {$errors ~= $text});
my $task=$proc.start;
LEAVE { try $proc.kill(SIGKILL) if $task.defined && $task.status==Planned }
await Promise.anyof($ready,Promise.in(5));
is $ready.status,Kept,'follow transforms existing text';
$b.spurt("2 finish 42\n",:append);
await Promise.anyof($matched,Promise.in(5));
is $matched.status,Kept,'follow transforms appended text from another file';
is ($matched.status==Kept ?? $matched.result !! Nil),42,'transformed follow preserves shared matcher';
$proc.kill(SIGTERM);
await Promise.anyof($task,Promise.in(5));
is $task.status,Kept,'transformed follow terminates';
is ($task.status==Kept ?? $task.result.exitcode !! Nil),143,'transformed follow signal status';
is $errors,'','transformed follow has no unexpected diagnostics';
done-testing;
