use lib 'lib';
use Test;
use JSON::Fast;
sub cli(@args) {
 my $p=run $*EXECUTABLE,'-Ilib','-It/lib','bin/eel.raku',|@args,:in,:out,:err;
 try { $p.in.say('{"type":"ping","timestamp":0}'); $p.in.close; Nil }
 my $out=$p.out.slurp(:close);my $err=$p.err.slurp(:close);
 ($p.exitcode,$out,$err)
}
my $code='event Bla { pattern TOP { <.event(:type<ping>)> } }';
my ($status,$out,$err)=cli(['-e',$code]);
is $status,0,'inline declaration works without export';
is from-json($out)<type>,'Bla','output has user type name';
is $err,'','valid inline program is quiet';
($status,$out,$err)=cli(['-e','my $kind="ping"','--eval','event Other { pattern TOP { <.event(:type($kind))> } }']);
is $status,0,'repeated snippets share lexicals and statement separators';
is from-json($out)<type>,'Other','shared helper used';
($status,$out,$err)=cli(['--eval='~$code,'-e','event Second { pattern TOP { <.event> } }','--event','Second']);
is $status,0,'explicit event selection does not infer module';
is $out.lines.elems,1,'only selected event used';
is from-json($out)<type>,'Second','selected inline event';
for ['-e',''],['-e'],['-e','say "no events"'],['-e','event {'],['-e','die "init failed"'],['-e','event Missing { }'] -> @args {
 ($status,$out,$err)=cli(@args);
 is $status,2,'configuration failure exits with 2';
 is $out,'','configuration errors leave stdout clean';
 ok $err.chars > 0,'configuration error has diagnostic';
}
($status,$out,$err)=cli(['-e','say "debug"; '~$code]);
is $status,0,'initialization code allowed';
like $err,/'debug'/,'initialization output goes to stderr';
is $out.lines.elems,1,'stdout contains only JSON';
($status,$out,$err)=cli(['-e','event Exported { has Absence $.absence; pattern TOP { <.event(:type<ping>)> <missing=!event(:type<rain>)> { $!absence=$<missing> } } }']);
is $status,0,'use EEL exports Absence into inline code';
is from-json($out)<absence><reason>,'eof','exported Absence attribute receives evidence';
($status,$out,$err)=cli(['--module','CLIInferred','-e',$code]);
is $status,0,'inline definitions can be combined with loaded modules';
is from-json($out)<type>,'Bla','inline event included alongside module exports';
($status,$out,$err)=cli(['-e','use CLIInferred; '~$code,'--event','CLIInferred::Additional']);
is $status,2,'imported events are not automatically selectable inline declarations';
($status,$out,$err)=cli(['-e','event Good { pattern TOP { <.event> } }','-e','event Bad { pattern TOP { ??? } }']);
is $status,2,'second snippet syntax failure is configuration error';
like $err,/'--eval-2'/,'diagnostic identifies the failing snippet';
($status,$out,$err)=cli(['-e','event Boom { pattern TOP { <.event> { die "match failed" } } }']);
is $status,1,'matching action failures retain runtime exit status';
is $out,'','failed match does not emit partial JSON';
($status,$out,$err)=cli(['-e','event Named { pattern TOP { <.event(:type<ping>)> } }; die "wrong event name" unless Named.^name eq "Named"']);
is $status,0,'initializers see the public event type name';
done-testing;
