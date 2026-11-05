use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
use EEL::Query;
use EEL::Condition;
use EEL::SearchIndex;
my $index=EEL::SearchIndex.new;
my @queries;
for ^30 -> $threshold {
 my $q=EEL::Query.new(:conditions{
  gate=>1,
  temperature=>EEL::Condition.comparison('>',$threshold),
  humidity=>EEL::Condition.comparison('<=',30-$threshold)
 });
 @queries.push($q); $index.add(@queries.elems,$q.index-plans);
}
for 0, 10, 10.5, 20.FatRat, 30, '20', 20e0 -> $temperature {
 my %input=gate=>1,:$temperature,humidity=>10;
 my @expected=(^@queries.elems).grep({ @queries[$_].matches(%input) }).map(*+1);
 my @actual=$index.candidates(%input).grep({ @queries[$_-1].matches(%input) });
 is-deeply @actual.Array,@expected.Array,'indexed and linear intervals agree for exact and coercive values';
}
$index.candidates({gate=>1,temperature=>15,humidity=>10});
ok $index.stats<pruned> > 0,'range restrictions prune equality anchor hits';
ok $index.stats<intersected> > 0,'range checks participate in adaptive intersection';
# Same range field, distinct bounds: caching per field would lose matches.
$index.clear;
my @bounds;
for 0,10,20,30 -> $low {
 my $q=EEL::Query.new(:conditions{gate=>1,v=>{'>='=>$low,'<='=>$low+5}});
 @bounds.push($q); $index.add(@bounds.elems,$q.index-plans);
}
for 0,5,10,15,20,25,30,35,36 -> $v {
 is-deeply $index.candidates({gate=>1,:$v}).Array,
  (^@bounds.elems).grep({ @bounds[$_].matches({gate=>1,:$v}) }).map(*+1).Array,
  'cache distinguishes lower and upper bounds';
}
$index.clear;
my @edges;
for '>', '>=' -> $op {
 my $q=EEL::Query.new(:conditions{gate=>1,v=>{$op=>10}});
 @edges.push($q); $index.add(@edges.elems,$q.index-plans);
}
is-deeply $index.candidates({gate=>1,v=>10}).Array,[2],'cache distinguishes open and closed endpoints';
event Reading {
 pattern TOP { <.event(:type<reading>,:temperature(* > 40),:humidity(* < 20))> }
}
my $runner=EEL::Runner.new(:patterns[Reading]);
is $runner.process({type=>'reading',temperature=>41,humidity=>19,timestamp=>0}).elems,1,'runtime accepts intersected ranges';
is $runner.process({type=>'reading',temperature=>40,humidity=>19,timestamp=>1}).elems,0,'runtime excludes open boundary';
is $runner.process({type=>'reading',temperature=>41,humidity=>20,timestamp=>2}).elems,0,'runtime applies second interval';
is $runner.process({type=>'reading',temperature=>'41',humidity=>'19',timestamp=>3}).elems,1,'runtime preserves coercive comparisons';
$index.remove(1); $index.remove(2);
is $index.stats<tokens>,0,'removal releases intersected registrations';
$index.clear;
is $index.stats<intersected>,0,'clear resets counters';
my $calls=0;
class Box {
 has $.calls;
 method Real { self.calls.(); 42 }
}
my $boxed=Box.new(:calls({$calls++}));
my $custom=EEL::Query.new(:conditions{gate=>1,v=>EEL::Condition.comparison('>',40)});
$index.add(1,$custom.index-plans);
is-deeply $index.candidates({gate=>1,v=>$boxed}).Array,[1],'custom numeric retains candidate';
is $calls,0,'secondary index never invokes Real';
ok $custom.matches({gate=>1,v=>$boxed}),'original comparison handles custom numeric';
is $calls,1,'Real runs only in final predicate';
class BrokenNumeric { method Real { die 'numeric failure' } }
lives-ok { $index.candidates({gate=>1,v=>BrokenNumeric.new}) },'index preserves deferred numeric exceptions';
throws-like { $custom.matches({gate=>1,v=>BrokenNumeric.new}) },X::AdHoc,
 message=>/'numeric failure'/,'final predicate propagates numeric exception';
for Inf, -Inf, NaN -> $v {
 my @actual=$index.candidates({gate=>1,:$v}).grep({ $custom.matches({gate=>1,:$v}) });
 is @actual.elems, ($custom.matches({gate=>1,:$v}) ?? 1 !! 0),'non-finite Num uses final comparison';
}
my $missing=$index.candidates({gate=>1});
is $missing.elems,0,'missing range field excluded';
$index.clear;
done-testing;
