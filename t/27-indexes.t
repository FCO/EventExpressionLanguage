use lib 'lib';
use Test;
use EEL::IntervalIndex;
use EEL::DeadlineQueue;
use EEL::MemoryStorage;
use EEL::Condition;
use EEL::Query;
use EEL;
use EEL::Runner;

my $tree=EEL::IntervalIndex.new;
my %intervals;
srand(731);
for ^250 -> $id {
    my $low=100.rand.Int-50;
    my $high=$low+20.rand.Int;
    my $lo=so $id % 2; my $hi=so $id % 3;
    %intervals{$id}=[$low,$high,$lo,$hi];
    $tree.add($id,:$low,:$high,:low-open($lo),:high-open($hi));
}
my $correct=True;
for -55..75 -> $point {
    my @expected=%intervals.keys.grep(-> $id {
        my ($lo,$hi,$open-lo,$open-hi)=%intervals{$id}.list;
        ($point > $lo || (!$open-lo && $point == $lo)) && ($point < $hi || (!$open-hi && $point == $hi))
    }).map(*.Int).sort;
    $correct &&= $tree.search($point).sort.List eqv @expected.List;
}
ok $correct,'AVL point search agrees with linear intervals, including empty intervals';
for ^250 -> $id {
    ok $tree.remove($id), "remove interval $id" if $id == 0 || $id == 249;
    $tree.remove($id) unless $id == 0 || $id == 249;
}
is $tree.elems,0,'all rotations/deletions release nodes';
ok !$tree.remove(3),'duplicate removal is harmless';
for ^1000 -> $id { $tree.add($id,:low($id*10),:high($id*10+1)) }
is-deeply $tree.search(5000), (500,), 'selective point lookup';
ok $tree.visited < 30,'interval lookup prunes unrelated subtrees';
$tree.clear;
my $heap=EEL::DeadlineQueue.new;
$heap.add(4,1); $heap.add(2,2); $heap.add(4,3);
is-deeply $heap.expired(2), (2,),'deadline expires at its boundary';
is-deeply $heap.expired(3), ().List, 'earliest deadline expires first';
is-deeply $heap.expired(5).sort.List,(1,3),'duplicate deadlines retained';

my $storage=EEL::MemoryStorage.new;
my @queries;
for ^200 -> $id {
    my $q=EEL::Query.new(:conditions{id=>$id,value=>{'>' => $id-1,'<='=>$id+10}});
    @queries.push($q); $storage.register($q,$id);
}
my $q=EEL::Query.new(:conditions{value=>-> $v { $v %% 2 }});
@queries.push($q); $storage.register($q,200);
my $equal=True;
for ^40 -> $i {
    my %e=id=>($i*7)%200,value=>($i*7)%200;
    my @expected=@queries.kv.map(-> $j,$q { $q.matches(%e) ?? $j !! Empty }).List;
    $equal &&= $storage.search(%e)».continuation.List eqv @expected.List;
}
ok $equal,'indexed query conjunctions and opaque fallback agree with linear scan';
is $storage.candidates({id=>42,value=>42}).elems,2,'intersection prunes all but exact candidate and opaque fallback';
my $nested=EEL::MemoryStorage.new;
$nested.register(EEL::Query.new(:conditions{'a.b'=>7}),'nested');
is $nested.search({'a.b'=>7,a=>{b=>9}}).elems,1,'literal dotted key has priority in index';
is $nested.search({a=>{b=>7}}).elems,1,'index traverses nested fields';
is $nested.search({a=>7}).elems,0,'missing nested field excluded';
my $types=EEL::MemoryStorage.new;
class Base { has $.x }
class Child is Base {}
$types.register(EEL::Query.new(:conditions{type=>Base}),'base');
is $types.search(Child.new(:x(1))).elems,1,'type index includes ancestors';
is $types.search({type=>'Base'}).elems,1,'type index accepts named raw tag';
is $types.search({type=>'Child'}).elems,0,'raw tag does not imply inheritance';
my $temporal=EEL::MemoryStorage.new;
$temporal.register(EEL::Query.new,'a',:waits[%(query=>EEL::Query.new,low=>0,high=>5).item],:deadline(5));
is $temporal.temporal(5).elems,1,'temporal interval end inclusive';
is $temporal.temporal(6).elems,0,'temporal interval rejects later events';
is $temporal.expired(5).elems,1,'heap expires at deadline boundary';
is $temporal.expired(6).elems,0,'heap does not expire a subscription twice';
$temporal.remove(1);
is $temporal.temporal(3).elems,0,'removal clears temporal references';

# Slang extraction and Junction evaluation are exercised through actual waits.
event Indexed {
 pattern TOP {
  :5s :partition{ .<session> }
  <start=.event(:type<S>)>
  <end=.event(:type<E>,:value(1 < * <= $<start>.limit),:kind(any('x','y')))>
 }
}
event Junctions {
 pattern TOP { <.event(:value(any(1,5,* > 40)))> }
 pattern all { <.event(:value(all(* > 1,* <= 42)))> }
 pattern one { <.event(:value(one(* > 1,* < 5)))> }
 pattern none { <.event(:value(none(1,5)))> }
 pattern comparison { <.event(:value(* == any(1,5)))> }
}
sub run($type,@events,Str :$rule='TOP',Bool :$linear=False) {
    my $r=EEL::Runner.new(:patterns[$type],:$rule);
    $r.EEL-linear-search($linear);
    my @results;
    for @events -> $e { @results.append($r.process($e)) }
    @results.append($r.finish);
    [@results.map({ .data<value> }).Array,$r.EEL-candidates]
}
my @events=(0,1,2,5,42,43).map({ %(value=>$_,timestamp=>0) }).Array;
is-deeply run(Junctions,@events)[0],[1,5,42,43],'explicit any supports values and predicates';
is-deeply run(Junctions,@events,:rule<all>)[0],[2,5,42],'all combines comparisons';
is-deeply run(Junctions,@events,:rule<one>)[0],[0,1,5,42,43],'one evaluates exactly one successful member';
is-deeply run(Junctions,@events,:rule<none>)[0],[0,2,42,43],'none rejects matching members';
is-deeply run(Junctions,@events,:rule<comparison>)[0],[1,5],'comparison with Junction preserves numeric equality';
my $opaque=any(1,5);
ok EEL::Query.new(:conditions{value=>$opaque}).matches({value=>5}),'opaque Junction evaluated without introspection';
ok !EEL::Query.new(:conditions{value=>$opaque}).matches({value=>'5'}),'opaque Junction preserves typed equality';
my @workflow;
for ^100 -> $id { @workflow.push(%(type=>'S',session=>$id,limit=>42,timestamp=>0)) }
@workflow.push(%(type=>'E',session=>42,value=>10,kind=>'x',timestamp=>1));
my @indexed=run(Indexed,@workflow);
my @linear=run(Indexed,@workflow,:linear);
is-deeply @indexed[0],@linear[0],'indexed runtime matches linear oracle';
is-deeply @indexed[0],[10],'capture-dependent interval and partition find correct match';
ok @indexed[1] < @linear[1] div 10,'candidate selection avoids unrelated active paths';

# Keep metadata visible to test compilation rather than relying on timing.
my $definition=Indexed.^find_method('TOP').instantiate(Indexed.new);
sub walk($n) { gather { take $n; .take for $n.children.map({ |walk($_) }) } }
my $partition=walk($definition).first(*.kind eq 'partition');
ok $partition.properties<share-extractor>,'simple topic-only extractor can share evaluation';
my $call=walk($definition).grep({ .kind eq 'call' && .name eq 'event' }).tail;
# Materialization requires captures, so the runtime differential above checks it.
done-testing;
