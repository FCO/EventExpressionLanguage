use lib 'lib';
use Test;
use EEL;
use Event;
use EEL::Runner;
sub feed($type,@events,Str :$rule='TOP',Real :$lateness=0,Bool :$linear=False) {
    my $r=EEL::Runner.new(:patterns[$type],:$rule,:$lateness); $r.EEL-linear-search($linear);
    my @out; @out.append($r.process($_)) for @events;
    @out.append($r.finish); @out.Array
}
event Scoped {
 pattern TOP { :partition{ .<session> } :!ignore-unexpected <s=.event(:type<S>)> <abs=!pair> <e=.event(:type<E>)> }
 pattern pair { <.event(:type<B>)> <.event(:type<C>)> }
 pattern captured { <.event(:type<S>)> <part> <.event(:type<E>)> }
 pattern part { <absence=!event(:type<B>)> }
}
my @input=%(type=>'S',session=>1,timestamp=>0),%(type=>'B',session=>2,timestamp=>1),%(type=>'E',session=>1,timestamp=>2);
is feed(Scoped,@input).elems,1,'other partition does not invalidate strict absence';
my $nested=feed(Scoped,[%(type=>'S',timestamp=>0),%(type=>'E',timestamp=>1)],:rule<captured>)[0];
isa-ok $nested<part><absence>,EEL::Absence,'absence survives subpattern return';

event LocalWindow {
 pattern TOP { <.event(:type<S>)> [ :1s <.event(:type<A>)> <x=!event(:type<X>)> ] }
}
my $r=EEL::Runner.new(:patterns[LocalWindow]);
$r.process({type=>'S',timestamp=>0});$r.process({type=>'A',timestamp=>10});
my @window=$r.process({type=>'noise',timestamp=>12});
is @window.elems,1,'group-local terminal absence keeps its deadline after restoration';
is @window[0]<x>.confirmed-at,Instant.from-posix(11),'local absence deadline is preserved';
$r.finish;

event Parallel {
 pattern TOP { <.event(:type<S>)> [ [ :1s <a=.event(:type<A>)> <x=!event(:type<X>)> ] &&& [ :5s <b=.event(:type<B>)> <y=!event(:type<Y>)> ] ] }
}
$r=EEL::Runner.new(:patterns[Parallel]);
$r.process({type=>'S',timestamp=>0});$r.process({type=>'A',timestamp=>1});$r.process({type=>'B',timestamp=>1});
is $r.process({type=>'noise',timestamp=>3}).elems,0,'short branch deadline does not prematurely confirm longer absence';
my @parallel=$r.process({type=>'noise',timestamp=>7});
is @parallel.elems,1,'both shuffle absences eventually confirm';
is @parallel[0]<x>.confirmed-at,Instant.from-posix(2),'short branch retains its actual deadline';
is @parallel[0]<y>.confirmed-at,Instant.from-posix(6),'long branch retains its own deadline';
$r.finish;

event Nested {
 pattern TOP { <.event(:type<A>)> <?with-absence> <.event(:type<B>)> }
 pattern with-absence { <.event(:type<B>)> <abs=!event(:type<X>)> }
 pattern negated { <.event(:type<A>)> <abs=!with-absence> }
}
is feed(Nested,[%(type=>'A',timestamp=>0),%(type=>'B',timestamp=>1)]).elems,1,'positive can confirm a nested terminal absence at EOF';
is feed(Nested,[%(type=>'A',timestamp=>0),%(type=>'B',timestamp=>1),%(type=>'X',timestamp=>2)]).elems,0,'nested negative failure rejects outer positive';
is feed(Nested,[%(type=>'A',timestamp=>0),%(type=>'B',timestamp=>1)],:rule<negated>).elems,0,'negative of a sequence ending in absence detects EOF completion';
is feed(Nested,[%(type=>'A',timestamp=>0),%(type=>'B',timestamp=>1),%(type=>'X',timestamp=>2)],:rule<negated>).elems,1,'negative succeeds when nested absence was invalidated';

event Priority {
 pattern TOP { <.event(:type<A>)> <?choice> <.event(:type<B>)> }
 pattern choice { [ <.event(:type<B>)> <.event(:type<C>)> ] || <.event(:type<B>)> }
}
$r=EEL::Runner.new(:patterns[Priority]);$r.process({type=>'A',timestamp=>0});
is $r.process({type=>'B',timestamp=>1}).elems,0,'positive honors unresolved ordered alternative';
is $r.finish.elems,1,'EOF releases completed lower-priority recognition';

event Recursive {
 pattern TOP { <.event(:type<A>)> <?block> <.event(:type<open>)> }
 pattern block { <.event(:type<open>)> [ <block> | <.event(:type<leaf>)> ] <.event(:type<close>)> }
}
my @recursive=<A open open leaf close close>.kv.map(-> $time,$type { %(timestamp=>$time,:$type) }).Array;
is feed(Recursive,@recursive).elems,1,'recursive assertion can recognize nested sequence';

event Dispatch {
 proto pattern check(|) {*}
 multi pattern check(Int $limit) { <.event(:type<B>,:value(* > $limit))> }
 multi pattern check(Str $type) { <.event(:$type)> }
 pattern TOP { <.event(:type<A>)> <data=?check(40)> <.event(:type<B>)> }
}
is feed(Dispatch,[%(type=>'A',timestamp=>0),%(type=>'B',value=>45,timestamp=>1)]).elems,1,'assertion uses native multi dispatch';

event Replay {
 has $.id;
 pattern TOP { <.event(:type<A>)> <data=?pair> { $!id=$<data><first>.id } <first=.event(:type<B>)> }
 pattern pair { <first=.event(:type<B>)> <second=.event(:type<C>)> }
}
class Reading { has $.type; has $.id; has $.timestamp }
my $a=Reading.new(:type<A>,:id(1),:timestamp(0));
my $b=Reading.new(:type<B>,:id(2),:timestamp(1));
my $c=Reading.new(:type<C>,:id(3),:timestamp(2));
my @output; ($c,$a,$b).Supply.match(Replay,:lateness(2),:reemit).tap({ @output.push($_) });
is @output.grep(* ~~ Reading).elems,3,'replay never reemits buffered inputs';
is @output.grep(* ~~ Replay).elems,1,'reordered positive emits one derived event';
my $derived=@output.first(* ~~ Replay);
is $derived.id,2,'confirmed assertion data is visible to subsequent action';
ok $derived<first>.data === $b,'replay retains input object identity';
is $derived<first>.EEL-index,2,'reordering and replay preserve processed ordinal';
# Independent negative capture holders are remapped when suffix alternatives fork.
event ForkedAbsence {
 pattern TOP { <.event(:type<A>)> <absence=!event(:type<B>)> [ <x=.event(:type<C>)> | <y=.event(:type<C>)> ] }
}
my @forks=feed(ForkedAbsence,[%(type=>'A',timestamp=>0),%(type=>'C',timestamp=>1)]);
is @forks.elems,2,'negative suffix forks remain independent matches';
isa-ok @forks[0]<absence>,EEL::Absence,'first fork has absence capture';
isa-ok @forks[1]<absence>,EEL::Absence,'second fork has absence capture';

event OuterNegative {
 pattern TOP { <.event(:type<A>)> <absence=!event(:type<X>)> <?pair> <.event(:type<B>)> }
 pattern pair { <.event(:type<B>)> <.event(:type<C>)> }
}
is feed(OuterNegative,[%(type=>'A',timestamp=>0),%(type=>'B',timestamp=>1),%(type=>'X',timestamp=>2),%(type=>'C',timestamp=>3)]).elems,1,'outer absence closes at replayed B, before later X';
is feed(OuterNegative,[%(type=>'A',timestamp=>0),%(type=>'X',timestamp=>1),%(type=>'B',timestamp=>2),%(type=>'C',timestamp=>3)]).elems,0,'outer absence still rejects X preceding replayed boundary';
for Scoped,Replay,OuterNegative -> $type {
    my @events=(<A B X C E>.kv.map(-> $time,$type { %(timestamp=>$time,:$type,session=>1,id=>$time) })).Array;
    is feed($type,@events).elems,feed($type,@events,:linear).elems,"{$type.^name} indexed and linear results agree";
}
event AuxiliaryClock {
 pattern TOP { <.event(:type<A>)> <?verify> <.event(:type<B>)> <.event(:type<C>)> <.event(:type<C>)> }
 pattern verify { [ :1s <.event(:type<B>)> <no=!event(:type<X>)> ] }
}
$r=EEL::Runner.new(:patterns[AuxiliaryClock]);
$r.process({type=>'A',timestamp=>0}); $r.process({type=>'B',timestamp=>1});
is $r.process({type=>'C',timestamp=>3}).elems,0,'auxiliary timer replay does not consume current C twice';
is $r.process({type=>'C',timestamp=>4}).elems,1,'auxiliary negative window can confirm positive before EOF';
$r.finish;

# History must be released as soon as no pending assertion can replay it.
$r=EEL::Runner.new(:patterns[Replay]);
$r.process({type=>'A',timestamp=>0}); $r.process({type=>'B',timestamp=>1,id=>5});
ok $r.EEL-work<history> > 0,'pending positive retains prepared input';
$r.process({type=>'C',timestamp=>2,id=>6});
is $r.EEL-work<history>,0,'resolved positive releases replay history';
$r.close;
is $r.EEL-work<history>,0,'cancellation releases replay history';

event BrokenAssertion {
 pattern TOP { <.event(:type<A>)> <?body> <.event(:type<B>)> }
 pattern body { <.event(:type<B>)> { die 'assertion-action-error' } }
}
$r=EEL::Runner.new(:patterns[BrokenAssertion]); $r.process({type=>'A',timestamp=>0});
throws-like {$r.process({type=>'B',timestamp=>1})},X::AdHoc,message=>/'assertion-action-error'/,'assertion exceptions propagate';
is $r.EEL-work<history>,0,'failed runner releases replay history';
is $r.pending,0,'failed runner releases all waits';

event Collision {
 pattern TOP { <.event(:type<A>)> <abs=!event(:forbidden(True))> <.event(:type<C>)> }
}
is feed(Collision,[%(type=>'A',timestamp=>0),%(type=>'C',forbidden=>True,timestamp=>1)]).elems,0,'prohibition wins over positive transition on same occurrence';

event Nullable {
 pattern empty { }
 pattern TOP { <.event(:type<A>)> <?empty> <.event(:type<B>)> }
 pattern negative { <.event(:type<A>)> <!empty> <.event(:type<B>)> }
}
is feed(Nullable,[%(type=>'A',timestamp=>0),%(type=>'B',timestamp=>1)]).elems,1,'nullable positive confirms immediately';
is feed(Nullable,[%(type=>'A',timestamp=>0),%(type=>'B',timestamp=>1)],:rule<negative>).elems,0,'nullable negative always fails';

event NoConsumption { pattern TOP { <?event> } }
throws-like {EEL::Runner.new(:patterns[NoConsumption])},X::AdHoc,message=>/'must consume'/,'assertions do not satisfy entry consumption requirement';
event NoProgress { pattern TOP { <.event> <?event>* } }
throws-like {EEL::Runner.new(:patterns[NoProgress])},X::AdHoc,message=>/'must consume'/,'unbounded repetition of assertions rejected';

event InitialLookahead { pattern TOP { <?event(:type<B>)> <c=.event(:type<C>)> } }
my @earlier=feed(InitialLookahead,[%(type=>'C',timestamp=>0),%(type=>'C',timestamp=>1),%(type=>'B',timestamp=>2)]);
is @earlier.elems,0,'initial assertion starts where its auxiliary query can recognize, without old noise';
event RootPriority {
 pattern TOP { [<?pair> <b=.event(:type<B>)>] || [<?single> <b=.event(:type<B>)>] }
 pattern pair { <.event(:type<B>)> <.event(:type<C>)> }
 pattern single { <.event(:type<B>)> }
}
$r=EEL::Runner.new(:patterns[RootPriority]);
is $r.process({type=>'B',timestamp=>0}).elems,0,'root assertion alternatives share startup identity before consumption';
is $r.process({type=>'C',timestamp=>1}).elems,1,'higher-priority root assertion can resolve before fallback';
is $r.finish.elems,0,'root assertion fallback is pruned after winner';

event NullablePriority {
 pattern TOP { <.event(:type<A>)> <?choice> <.event(:type<B>)> }
 pattern choice { <.event(:type<C>)> || <empty> }
 pattern empty { }
}
$r=EEL::Runner.new(:patterns[NullablePriority]);
$r.process({type=>'A',timestamp=>0});
is $r.process({type=>'B',timestamp=>1}).elems,0,'nullable fallback in assertion waits for viable higher branch';
is $r.finish.elems,1,'EOF releases nullable assertion fallback';
event StrictPriority {
 pattern TOP { <.event(:type<A>)> <?choice> <.event(:type<B>)> }
 pattern choice { [ :!ignore-unexpected <.event(:type<B>)> <.event(:type<C>)> ] || <.event(:type<B>)> }
}
$r=EEL::Runner.new(:patterns[StrictPriority]);
$r.process({type=>'A',timestamp=>0});
is $r.process({type=>'B',timestamp=>1}).elems,0,'strict higher assertion branch initially blocks fallback';
is $r.process({type=>'X',timestamp=>2}).elems,1,'failure of strict higher prefix releases completed fallback';
$r.finish;
done-testing;

