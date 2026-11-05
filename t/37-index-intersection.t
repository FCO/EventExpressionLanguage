use lib 'lib';
use Test;
use EEL::SearchIndex;
use EEL::Query;
use EEL::Condition;
my $index=EEL::SearchIndex.new;
my @queries;
for ^20 -> $a {
 for ^20 -> $b {
  my $q=EEL::Query.new(:conditions{a=>$a,b=>$b,v=>EEL::Condition.definedness(True, *.defined)});
  @queries.push($q); $index.add(@queries.elems,$q.index-plans);
 }
}
for %(a=>3,b=>7,v=>0), %(a=>3,b=>7,v=>Any), %(a=>3,b=>7), %(a=>50,b=>7,v=>1) -> $input {
 my @expected=(^@queries.elems).grep({ @queries[$_].matches($input) }).map(*+1);
 is-deeply $index.candidates($input).Array,@expected.Array,'conjunctive restrictions intersect without final predicate';
}
is $index.candidates({a=>3,b=>7,v=>1}).elems,1,'one matching combination';
ok $index.stats<pruned> > 0,'secondary restrictions prune anchor hits';
ok $index.stats<intersected> > 0,'secondary checks counted';
my $or=EEL::Condition.junction('any', EEL::Condition.literal(3), EEL::Condition.literal(8));
my $q=EEL::Query.new(:conditions{a=>$or,b=>7});
$index.add(999,$q.index-plans);
ok 999 eq any($index.candidates({a=>8,b=>7})),'disjunctive plans are unioned';
ok !(999 eq any($index.candidates({a=>8,b=>6}))),'intersection is local to each conjunction';
$index.remove(999);
ok !(999 eq any($index.candidates({a=>8,b=>7}))),'removal clears intersected plans';
$index.clear;
is $index.elems,0,'clear empties index';
is $index.stats<pruned>,0,'clear resets intersection statistics';
class UndefinedValue { method defined { False } }
$index=EEL::SearchIndex.new;
$index.add($_+1,@queries[$_].index-plans) for ^@queries.elems;
for ^30 -> $i {
 my %input=a=>($i % 20),b=>(($i*7) % 20),v=>($i % 3 ?? 0 !! UndefinedValue.new);
 my @actual=$index.candidates(%input).grep({ @queries[$_-1].matches(%input) });
 my @expected=(^@queries.elems).grep({ @queries[$_].matches(%input) }).map(*+1);
 is-deeply @actual.Array,@expected.Array,'adaptive indexed results agree with linear evaluation';
}
my $calls=0;
my $opaque=EEL::Query.new(:conditions{a=>3,v=>-> $v { $calls++; True }});
$index.add(999,$opaque.index-plans);
$index.candidates({a=>3,v=>1});
is $calls,0,'secondary intersection never invokes an opaque predicate';
class Parent {}
class Child is Parent { has $.a = 3 }
my $typed=EEL::Query.new(:conditions{type=>Parent,a=>3});
$index.clear;
$index.add(1,$typed.index-plans);
is-deeply $index.candidates(Child.new).Array,[1],'type restriction preserves subclasses';
$index.clear;
for ^200 -> $id { $index.add($id,EEL::Query.new(:conditions{a=>1,b=>1}).index-plans) }
for ^40 {
 my $input=%(a=>1,b=>1);
 is $index.candidates($input).elems,200,'low-yield adaptation preserves matching plans';
}
is $index.stats<intersected>,0,'low-yield workload skips secondary checks between probes';
done-testing;
