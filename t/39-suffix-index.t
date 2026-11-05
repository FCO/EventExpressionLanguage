use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
use EEL::Query;
use EEL::Condition;
use EEL::SearchIndex;
event Suffix {
 pattern TOP { <.event(:path(*.ends-with('/api/')))> }
}
my $condition=Suffix.new.TOP.children[0].children[0].code.().hash<path>;
isa-ok $condition,EEL::Condition,'literal suffix compiled to descriptor';
is $condition.kind,'suffix','suffix descriptor selected';
my $r=EEL::Runner.new(:patterns[Suffix]);
is $r.process({path=>'upload/api/',timestamp=>0}).elems,1,'suffix accepts path';
is $r.process({path=>'/other',timestamp=>1}).elems,0,'suffix rejects unrelated path';
is $r.process({timestamp=>2}).elems,0,'missing path rejected';
my $index=EEL::SearchIndex.new;
my @suffixes='', '/a', '/api/', 'upload/api/', 'é', "e\x[301]", '👩‍💻', "a", "a\x[301]";
my @queries=@suffixes.map({ EEL::Query.new(:conditions(%(path=>EEL::Condition.suffix($_)))) });
$index.add($_+1,@queries[$_].index-plans) for ^@queries.elems;
for '', 'upload/api/', 'users/api/', '/else', 'clairé', "claire\x[301]", 'work/👩‍💻', "bca\x[301]" -> $path {
 my @expected=(^@queries.elems).grep({ @queries[$_].matches({:$path}) }).map(*+1);
 is-deeply $index.candidates({:$path}).Array,@expected.Array,'trie agrees with ends-with including Unicode and empty suffix';
}
class Custom {
 has $.calls;
 method ends-with($suffix) { self.calls.(); $suffix eq '/api/' }
}
my $calls=0;
my $value=Custom.new(:calls({$calls++}));
my @candidates=$index.candidates({path=>$value});
is $calls,0,'index does not invoke custom method';
is @candidates.elems,@queries.elems,'nontext values retain all potential suffixes';
is @candidates.grep({ @queries[$_-1].matches({path=>$value}) }).elems,1,'custom method decides final match';
$index.remove($_+1) for ^@queries.elems;
is $index.stats<suffix-nodes>,0,'removal prunes trie nodes';
is $index.stats<tokens>,0,'removal releases tokens';
for ^1000 -> $i { $index.add($i,EEL::Query.new(:conditions{path=>EEL::Condition.suffix("/endpoint/$i/")}).index-plans) }
is $index.candidates({path=>'file/endpoint/42/'}).elems,1,'one candidate among a thousand suffixes';
ok $index.visited < 40,'lookup follows input path rather than scanning every suffix';
$index.clear;
is $index.stats<suffix-nodes>,0,'clear releases trie';
is $index.elems,0,'clear removes registrations';
event DynamicSuffix {
 pattern TOP {
  <s=.event(:type<S>)>
  <p=.event(:path(*.ends-with($<s>.data<suffix>)))>
 }
}
$r=EEL::Runner.new(:patterns[DynamicSuffix]);
$r.process({type=>'S',suffix=>'/dynamic/',timestamp=>0});
is $r.process({path=>'value/dynamic/',timestamp=>1}).elems,1,'dynamic suffix retains callable fallback';
class Throws { method ends-with($suffix) { die 'suffix exception' } }
$index.add(1,EEL::Query.new(:conditions{path=>EEL::Condition.suffix('/api/')}).index-plans);
lives-ok { $index.candidates({path=>Throws.new}) },'lookup does not execute custom exceptions';
throws-like { @queries[2].matches({path=>Throws.new}) },X::AdHoc,
 message=>/'suffix exception'/,'final predicate preserves exceptions';
$index.clear;
for ^300 -> $i {
 $index.add($i,EEL::Query.new(:conditions{path=>EEL::Condition.suffix("/temporary/$i/")}).index-plans);
 $index.remove($i);
}
is $index.stats<suffix-nodes>,0,'registration churn leaves no trie nodes';
event Mixed {
 pattern TOP { <.event(:path(all(*.starts-with('/api/'), *.ends-with('.json'))))> }
}
$r=EEL::Runner.new(:patterns[Mixed]);
is $r.process({path=>'/api/report.json',timestamp=>0}).elems,1,'prefix and suffix can constrain the same field';
is $r.process({path=>'/api/report.txt',timestamp=>1}).elems,0,'combined condition rejects wrong suffix';
is $r.process({path=>'/else/report.json',timestamp=>2}).elems,0,'combined condition rejects wrong prefix';
done-testing;
