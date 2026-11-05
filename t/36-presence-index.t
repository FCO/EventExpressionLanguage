use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
use EEL::Query;
use EEL::MemoryStorage;
use EEL::Condition;
use EEL::SearchIndex;
event Forms {
 pattern TOP { <.event(:v(*.defined))> }
 pattern negative { <.event(:v(!*.defined))> }
 pattern not-method { <.event(:v(*.defined.not))> }
}
for <TOP negative not-method> -> $rule {
 my $r=EEL::Runner.new(:patterns[Forms],:$rule);
 is $r.process({timestamp=>0}).elems,0,"$rule rejects absence";
 is $r.process({v=>Any,timestamp=>1}).elems,($rule eq 'TOP' ?? 0 !! 1),"$rule undefined";
 is $r.process({v=>0,timestamp=>2}).elems,($rule eq 'TOP' ?? 1 !! 0),"$rule zero";
}
my $s=EEL::MemoryStorage.new;
for ^100 -> $i { $s.register(EEL::Query.new(:conditions{"field$i" => -> $v { True }}),$i) }
is $s.search({unrelated=>1}).elems,0,'missing fields excluded';
is $s.stats<query><visited>,0,'presence avoids visiting unrelated subscriptions';
is $s.search({field42=>False}).elems,1,'false is present';
$s.clear;
is $s.stats<query><tokens>,0,'clear removes state tokens';
class Custom { method defined { False } }
my $condition=EEL::Condition.definedness(False, !*.defined);
$s.register(EEL::Query.new(:conditions{v=>$condition}),1);
is $s.search({v=>Custom.new}).elems,1,'custom defined retained conservatively';
is $s.search({v=>Any}).elems,1,'undefined primitive found';
is $s.search({v=>''}).elems,0,'empty string remains defined';
$s.clear;
my $index=EEL::SearchIndex.new;
my @queries;
for <v nested.v> -> $field {
    @queries.append([
        EEL::Query.new(:conditions{$field=>EEL::Condition.definedness(True, *.defined)}),
        EEL::Query.new(:conditions{$field=>EEL::Condition.definedness(False, !*.defined)}),
        EEL::Query.new(:conditions{$field=>-> $v { True }}),
    ]);
}
$index.add($_+1,@queries[$_].index-plans) for ^@queries.elems;
for {}, {v=>Any}, {v=>False}, {v=>0}, {v=>''}, {v=>Custom.new},
    %(nested=>%(v=>Any)), %(nested=>%(v=>1)),
    %('nested.v'=>Any,nested=>%(v=>1)) -> $input {
    my @expected=(^@queries.elems).grep({ @queries[$_].matches($input) }).map(*+1);
    my @actual=$index.candidates($input).grep({ @queries[$_-1].matches($input) });
    is-deeply @actual.Array,@expected.Array,'indexed and linear semantics agree';
}
$index.clear;
for ^100 -> $id {
    $index.add($id, EEL::Query.new(:conditions{v=>EEL::Condition.definedness(True, *.defined)}).index-plans);
}
is $index.candidates({v=>Any}).elems,0,'undefined input skips defined subscriptions';
is $index.visited,0,'opposite definition bucket is not traversed';
$index.remove($_) for ^100;
is $index.stats<tokens>,0,'removal releases definition buckets';
is $index.stats<fields>,0,'removal releases field references';
my $calls=0;
class Observable {
    has $.calls;
    method defined { self.calls.(); False }
}
my $value=Observable.new(:calls({ $calls++ }));
$index.add(1,EEL::Query.new(:conditions{v=>EEL::Condition.definedness(False, !*.defined)}).index-plans);
is $index.candidates({v=>$value}).elems,1,'custom value remains a candidate';
is $calls,0,'index does not execute custom defined';
is @queries[1].matches({v=>$value}),True,'final predicate executes custom method';
is $calls,1,'custom method called exactly once';
class Explosive { method defined { die 'custom defined failure' } }
my $explosive=Explosive.new;
lives-ok { $index.candidates({v=>$explosive}) },'index does not trigger custom exceptions';
throws-like { @queries[1].matches({v=>$explosive}) }, X::AdHoc,
    message=>/'custom defined failure'/, 'final predicate preserves custom exceptions';
done-testing;
