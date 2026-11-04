use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
use EEL::Clock;
event Timed { pattern TOP { :1ms <.event(:type<A>)> <.event(:type<B>)> } }
for 999999,1000000,1000001 -> $end {
 my $r=EEL::Runner.new(:patterns[Timed]);
 $r.process({type=>'noise',timestamp=>0});
 $r.process({type=>'A',timestamp=>10/1000});
 is $r.process({type=>'B',timestamp=>(10_000_000+$end)/1_000_000_000}).elems,
  ($end <= 1_000_000 ?? 1 !! 0),"inclusive event-time boundary $end";
}
my $r=EEL::Runner.new(:patterns[Timed]);
$r.process({type=>'A',timestamp=>0});
is $r.pending,1,'idle does not advance the watermark';
is $r.pending,1,'repeated pending checks do not expire event-time paths';
$r.process({type=>'noise',timestamp=>2/1000});
is $r.pending,0,'later watermark expires paths';
$r.process({type=>'A',timestamp=>3/1000});
is $r.process({type=>'B',timestamp=>4/1000}).elems,1,'new match has its own deadline';
event Units {
 pattern TOP { [ :0.5ms <.event> ] [ :0.5s <.event> ] [ :1.5min <.event> ] [ :1.5h <.event> ] [ :1.5d <.event> ] [ :0.5m <.event> ] [ :0.5y <.event> ] }
}
sub nodes($n) { gather { take $n; for $n.children { .take for nodes($_) } } }
is-deeply nodes(Units.new.TOP).grep(*.kind eq 'window-start').map(*.properties<nanoseconds>).List,
 (500000,500000000,90000000000,5400000000000,129600000000000,1296000000000000,15768000000000000),'seven canonical units use exact nanoseconds';
event Nested { pattern TOP { :1s <.event(:type<A>)> [ :1ms <.event(:type<B>)> <.event(:type<C>)> ] } }
$r=EEL::Runner.new(:patterns[Nested]);
$r.process({type=>'A',timestamp=>0}); $r.process({type=>'B',timestamp=>10/1000});
is $r.process({type=>'C',timestamp=>11/1000}).elems,1,'inner window starts at its own first event';
event Reordered { pattern TOP { :3s <.event(:type<A>)> <.event(:type<B>)> } }
$r=EEL::Runner.new(:patterns[Reordered],:lateness(2));
is $r.process({type=>'B',timestamp=>2}).elems,0,'future event buffered until watermark';
is $r.process({type=>'A',timestamp=>0}).elems,0,'earlier event accepted at watermark';
is $r.process({type=>'noise',timestamp=>4}).elems,1,'out-of-order input is processed in event time';
is $r.finish.elems,0,'EOF flushes remainder once';
my @out;
({type=>'B',timestamp=>2},{type=>'A',timestamp=>0},{type=>'noise',timestamp=>4}).Supply.match(Reordered,:lateness(2),:reemit).tap(-> $v { @out.push($v) });
is-deeply @out.grep(Associative).map(*.<type>).Array,['A','B','noise'],'reemission follows processing order including EOF';
is @out.grep(Reordered).elems,1,'reordered Supply emits recognition once';
my $failures=0;
event Goal { pattern TOP { :1ms <.event(:type<A>)> ~ <.event(:type<B>)> [] }; method FAILGOAL($goal) { $failures++ } }
$r=EEL::Runner.new(:patterns[Goal]); $r.process({type=>'A',timestamp=>0}); $r.process({type=>'noise',timestamp=>2/1000}); $r.finish;
is $failures,0,'expired goal is not diagnosed as missing closer';
for <0.0000000001s -1ms 1fortnights> -> $d {
 my $p=run $*EXECUTABLE,'-Ilib','-c','-e',"use EEL; event Bad \{ pattern TOP \{ :$d <.event> \} \}",:out,:err;
 $p.out.slurp(:close); $p.err.slurp(:close);
 isnt $p.exitcode,0,"reject invalid duration $d";
}
for 'use EEL; event Bad { pattern TOP { [ <.event> ] 1s } }',
 'use EEL; event Bad { pattern TOP { <.event> 1s } }' -> $code {
 my $p=run $*EXECUTABLE,'-Ilib','-c','-e',$code,:out,:err; $p.out.slurp(:close); $p.err.slurp(:close);
 isnt $p.exitcode,0,'postfix window syntax removed';
}
for -1,Inf,0.0000000001 -> $lateness {
 throws-like { EEL::Runner.new(:patterns[Timed],:$lateness) },X::AdHoc,'invalid lateness rejected';
}
my $first=monotonic(); ok monotonic() >= $first,'CLI monotonic clock remains available';
done-testing;
