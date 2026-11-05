use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
event Policies {
 pattern optional-all { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>? }
 pattern optional-first { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>?? }
 pattern optional-last { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>?! }
 pattern plus-all { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+ }
 pattern plus-first { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+? }
 pattern plus-last { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+! }
 pattern star-all { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>* }
 pattern star-first { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>*? }
 pattern star-last { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>*! }
 pattern suffix-first { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+? <.event(:type<B>)> }
 pattern suffix-last { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+! <.event(:type<B>)> }
 pattern window-last { :2s :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+! }
 pattern tie-last { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+! [<b=.event(:type<B>)> | <c=.event(:type<B>)>] }
 pattern nested-first { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+? <others=.event(:type<B>)>+? }
 pattern nested-last { :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+! <others=.event(:type<B>)>+! }
}
sub feed($rule,@types,Bool :$finish=True) {
 my $r=EEL::Runner.new(:patterns[Policies],:$rule);
 my @out;
 for @types.kv -> $time,$type { @out.append($r.process({:$type,timestamp=>$time})) }
 @out.append($r.finish) if $finish;
 @out
}
for 'optional-all'=>[0,1], 'optional-first'=>[0,1], 'optional-last'=>[0,1],
 'plus-all'=>[1,2], 'plus-first'=>[1,2], 'plus-last'=>[1,2],
 'star-all'=>[0,1,2], 'star-first'=>[0,1,2], 'star-last'=>[0,1,2] -> $case {
 is-deeply feed($case.key,<S A A X>).map(*.<items>.elems).Array,$case.value,"selection {$case.key}";
}
is feed('suffix-first',<S A A B>)[0]<items>.elems,2,'first keeps extensions needed by suffix';
is feed('suffix-last',<S A A B>)[0]<items>.elems,2,'last accepts complete suffix before releasing';
my $r=EEL::Runner.new(:patterns[Policies],:rule<plus-last>);
$r.process({type=>'S',timestamp=>0});
is $r.process({type=>'A',timestamp=>1}).elems,1,'all-results suffix publishes first conclusion';
is $r.process({type=>'A',timestamp=>2}).elems,1,'all-results suffix publishes longer conclusion';
ok $r.pending > 0,'idle does not publish or expire last result';
is $r.finish.elems,0,'EOF does not replay conclusions';
$r=EEL::Runner.new(:patterns[Policies],:rule<window-last>);
$r.process({type=>'S',timestamp=>0}); $r.process({type=>'A',timestamp=>1});
is $r.process({type=>'A',timestamp=>2}).elems,0,'deadline event is excluded';
is $r.process({type=>'X',timestamp=>3}).elems,0,'expired paths emit nothing further';
my @tie=feed('tie-last',<S A B>);
is @tie.elems,2,'all-results suffix publishes tied completions';
ok @tie[0].hash<b>:exists,'source path order deterministically breaks tie';
is feed('nested-first',<S A B B X>).elems,2,'nested minimum policies select per event';
is feed('nested-last',<S A B B X>)[* - 1]<others>.elems,2,'nested last policies preserve latest result';
event Overlap { pattern TOP { <items=.event(:type<A>)>+! } }
my @overlap;
({type=>'A',timestamp=>0},{type=>'A',timestamp=>1}).Supply.match(Overlap).tap(-> $v {@overlap.push($v)});
is-deeply @overlap.map(*.<items>.elems).Array,[1,2,1],'all-results suffix publishes every growing start';
my $source=Supplier.new; my @cancelled;
my $tap=$source.Supply.match(Overlap).tap(-> $v {@cancelled.push($v)});
$source.emit({type=>'A',timestamp=>0}); $tap.close; $source.done;
is @cancelled.elems,1,'cancellation preserves already published results';
$r=EEL::Runner.new(:patterns[Policies],:rule<plus-last>);
$r.process({type=>'S',timestamp=>0});
$r.process(%(type=>'A',timestamp=>$_)) for 1..10;
is $r.pending,1,'all-results suffix retains only its open extension';
is $r.process({type=>'A',timestamp=>11})[0]<items>.elems,11,'open continuation keeps growing';
is $r.finish.elems,0,'EOF does not duplicate results';
done-testing;
