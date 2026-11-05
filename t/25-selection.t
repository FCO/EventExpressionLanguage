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
for 'optional-all'=>[0,1], 'optional-first'=>[0], 'optional-last'=>[1],
 'plus-all'=>[1,2], 'plus-first'=>[1], 'plus-last'=>[2],
 'star-all'=>[0,1,2], 'star-first'=>[0], 'star-last'=>[2] -> $case {
 is-deeply feed($case.key,<S A A X>).map(*.<items>.elems).Array,$case.value,"selection {$case.key}";
}
is feed('suffix-first',<S A A B>)[0]<items>.elems,2,'first keeps extensions needed by suffix';
is feed('suffix-last',<S A A B>)[0]<items>.elems,2,'last accepts complete suffix before releasing';
my $r=EEL::Runner.new(:patterns[Policies],:rule<plus-last>);
$r.process({type=>'S',timestamp=>0});
is $r.process({type=>'A',timestamp=>1}).elems,0,'last holds first complete result';
is $r.process({type=>'A',timestamp=>2}).elems,0,'last replaces buffered result';
ok $r.pending > 0,'idle does not publish or expire last result';
is $r.finish[0]<items>.elems,2,'EOF releases latest complete result';
$r=EEL::Runner.new(:patterns[Policies],:rule<window-last>);
$r.process({type=>'S',timestamp=>0}); $r.process({type=>'A',timestamp=>1});
is $r.process({type=>'A',timestamp=>2}).elems,0,'deadline boundary is inclusive';
is $r.process({type=>'X',timestamp=>3})[0]<items>.elems,2,'watermark beyond window releases last';
my @tie=feed('tie-last',<S A B>);
is @tie.elems,1,'one result for tied last completions';
ok @tie[0].hash<b>:exists,'source path order deterministically breaks tie';
is feed('nested-first',<S A B B X>).elems,1,'nested first policies agree on one result';
is feed('nested-last',<S A B B X>)[0]<others>.elems,2,'nested last policies preserve latest result';
event Overlap { pattern TOP { <items=.event(:type<A>)>+! } }
my @overlap;
({type=>'A',timestamp=>0},{type=>'A',timestamp=>1}).Supply.match(Overlap).tap(-> $v {@overlap.push($v)});
is-deeply @overlap.map(*.<items>.elems).Array,[2,1],'last selection independent per start';
my $source=Supplier.new; my @cancelled;
my $tap=$source.Supply.match(Overlap).tap(-> $v {@cancelled.push($v)});
$source.emit({type=>'A',timestamp=>0}); $tap.close; $source.done;
is @cancelled.elems,0,'cancellation drops retained last results';
$r=EEL::Runner.new(:patterns[Policies],:rule<plus-last>);
$r.process({type=>'S',timestamp=>0});
$r.process(%(type=>'A',timestamp=>$_)) for 1..10;
is $r.pending,2,'last retains one dominated-result replacement plus one extension';
is $r.finish[0]<items>.elems,10,'compaction preserves last full result';
done-testing;
