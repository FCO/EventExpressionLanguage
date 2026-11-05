use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
use EEL::Query;
use EEL::Condition;
use EEL::SearchIndex;
event Prefix {
 pattern TOP { <.event(:path(*.starts-with('/api/')))> }
}
my $condition=Prefix.new.TOP.children[0].children[0].code.().hash<path>;
isa-ok $condition,EEL::Condition,'literal prefix compiled to descriptor';
is $condition.kind,'prefix','prefix descriptor selected';
my $r=EEL::Runner.new(:patterns[Prefix]);
is $r.process({path=>'/api/upload',timestamp=>0}).elems,1,'prefix accepts path';
is $r.process({path=>'/other',timestamp=>1}).elems,0,'prefix rejects unrelated path';
is $r.process({timestamp=>2}).elems,0,'missing path rejected';
my $index=EEL::SearchIndex.new;
my @prefixes='', '/a', '/api/', '/api/upload', 'é', "e\x[301]", '👩‍💻', "a", "a\x[301]";
my @queries=@prefixes.map({ EEL::Query.new(:conditions(%(path=>EEL::Condition.prefix($_)))) });
$index.add($_+1,@queries[$_].index-plans) for ^@queries.elems;
for '', '/api/upload', '/api/users', '/else', 'éclair', "e\x[301]clair", '👩‍💻/work', "a\x[301]bc" -> $path {
 my @expected=(^@queries.elems).grep({ @queries[$_].matches({:$path}) }).map(*+1);
 is-deeply $index.candidates({:$path}).Array,@expected.Array,'trie agrees with starts-with including Unicode and empty prefix';
}
class Custom {
 has $.calls;
 method starts-with($prefix) { self.calls.(); $prefix eq '/api/' }
}
my $calls=0;
my $value=Custom.new(:calls({$calls++}));
my @candidates=$index.candidates({path=>$value});
is $calls,0,'index does not invoke custom method';
is @candidates.elems,@queries.elems,'nontext values retain all potential prefixes';
is @candidates.grep({ @queries[$_-1].matches({path=>$value}) }).elems,1,'custom method decides final match';
$index.remove($_+1) for ^@queries.elems;
is $index.stats<prefix-nodes>,0,'removal prunes trie nodes';
is $index.stats<tokens>,0,'removal releases tokens';
for ^1000 -> $i { $index.add($i,EEL::Query.new(:conditions{path=>EEL::Condition.prefix("/endpoint/$i/")}).index-plans) }
is $index.candidates({path=>'/endpoint/42/file'}).elems,1,'one candidate among a thousand prefixes';
ok $index.visited < 40,'lookup follows input path rather than scanning every prefix';
$index.clear;
is $index.stats<prefix-nodes>,0,'clear releases trie';
is $index.elems,0,'clear removes registrations';
event DynamicPrefix {
 pattern TOP {
  <s=.event(:type<S>)>
  <p=.event(:path(*.starts-with($<s>.data<prefix>)))>
 }
}
$r=EEL::Runner.new(:patterns[DynamicPrefix]);
$r.process({type=>'S',prefix=>'/dynamic/',timestamp=>0});
is $r.process({path=>'/dynamic/value',timestamp=>1}).elems,1,'dynamic prefix retains callable fallback';
class Throws { method starts-with($prefix) { die 'prefix exception' } }
$index.add(1,EEL::Query.new(:conditions{path=>EEL::Condition.prefix('/api/')}).index-plans);
lives-ok { $index.candidates({path=>Throws.new}) },'lookup does not execute custom exceptions';
throws-like { @queries[2].matches({path=>Throws.new}) },X::AdHoc,
 message=>/'prefix exception'/,'final predicate preserves exceptions';
$index.clear;
for ^300 -> $i {
 $index.add($i,EEL::Query.new(:conditions{path=>EEL::Condition.prefix("/temporary/$i/")}).index-plans);
 $index.remove($i);
}
is $index.stats<prefix-nodes>,0,'registration churn leaves no trie nodes';
done-testing;
