use lib 'lib';
use Test;
use EEL;
use Event;
use EEL::Runner;
use EEL::SearchIndex;
use EEL::MemoryStorage;
use EEL::Query;
use EEL::Condition;
use EEL::Input;
use EEL::InputQueue;
use EEL::State;

my $index=EEL::SearchIndex.new;
for ^1000 -> $id {
    $index.add($id,EEL::Query.new(:conditions{type=>'response',id=>$id}).index-plans);
}
is-deeply $index.candidates({type=>'response',id=>42}),(42,),'selective anchor finds ID within broad type bucket';
ok $index.visited < 10,'one candidate does not conceal a broad type scan';
# Registration rebalances anchors without merging independent subscriptions.
for ^1000 -> $id { $index.remove($id) }
is $index.stats<tokens>,0,'anchor removals release references';
is $index.candidates({type=>'response',id=>42}).elems,0,'rebalanced removal leaves no stale query';
$index.clear;
$index.add(1,EEL::Query.new(:conditions{value=>{'>'=>1,'<='=>42}}).index-plans);
is $index.stats<tokens>,1,'bounds merge into one interval node';
is-deeply $index.candidates({value=>42}),(1,),'merged high bound inclusive';
is $index.candidates({value=>1}).elems,0,'merged low bound exclusive';
$index.clear;
$index.add(1,EEL::Query.new(:conditions{value=>{'>'=>50,'<='=>42}}).index-plans);
is $index.candidates({value=>45}).elems,0,'contradictory exact interval has no candidates';
$index.clear;
# DNF conjunctions can share a leaf. Normalization must not mutate that leaf
# and accidentally narrow another disjunct.
my $gt0=EEL::Condition.comparison('>',0);
my $disjunction=EEL::Condition.junction('all',$gt0,EEL::Condition.junction('any',
    EEL::Condition.comparison('<',10),EEL::Condition.comparison('>',20)));
$index.add(1,EEL::Query.new(:conditions{value=>$disjunction}).index-plans);
is-deeply $index.candidates({value=>30}),(1,),'interval normalization keeps disjuncts independent';
is $index.candidates({value=>15}).elems,0,'gap between disjunctive intervals stays excluded';
$index.clear;

my $storage=EEL::MemoryStorage.new;
for ^100 -> $id { $storage.register(EEL::Query.new(:conditions{value=>-> $v { $v > 0 }}),$id) }
is $storage.search({value=>1}).elems,100,'opaque predicates preserve matches';
is $storage.stats<strategy>,'route','opaque population chooses scan';
$storage.clear;
for ^100 -> $id { $storage.register(EEL::Query.new(:conditions{id=>$id}),$id) }
$storage.search({id=>42}) for ^5;
is $storage.stats<strategy>,'query','selective population uses index';
# Scan mode periodically probes, so a changed workload can recover selectivity.
$storage.clear;
# Move from broad intervals to selective hits while keeping the same registry.
for ^100 -> $id { $storage.register(EEL::Query.new(:conditions{value=>{'>='=>$id*10,'<='=>$id*10+1}}),$id) }
$storage.search({value=>4e0}) for ^5; # non-exact inputs use residual candidates
is $storage.stats<strategy>,'route','broad residual workload switches to scan';
$storage.search({value=>420}) for ^140;
is $storage.stats<strategy>,'query','periodic probes recover selectivity after workload change';
$storage.clear;

my $heap=EEL::InputQueue.new;
srand(20261104);
my @entries=(^1000).map({ [100.rand.Int,$_,"payload-$_"] }).Array;
$heap.push($_) for @entries;
my @out; @out.push($heap.shift) while $heap;
is-deeply @out.Array,@entries.sort({$^a[0] <=> $^b[0] || $^a[1] <=> $^b[1]}).Array,'input heap matches stable temporal sort';
is $heap.elems,0,'input heap empties';
$heap.push([1,1,'discard']); $heap.clear;
is $heap.elems,0,'cancellation clears temporal buffer';
ok !$heap.shift.defined,'empty heap returns no input';

# Many types sharing the same code body still have distinct registrations.
event Template { pattern TOP { <.event(:type<hit>)> } }
my @patterns;
for ^100 -> $id {
    my $type=Metamodel::ClassHOW.new_type(:name("Starter$id"));
    $type.^add_parent(Template);
    @patterns.push($type.^compose);
}
# Reuse a compiled candidate, whose literal query is the same for each type.

my $starter=EEL::Runner.new(:patterns(@patterns));
is $starter.process({type=>'noise',timestamp=>0}).elems,0,'irrelevant input starts no matches';
is $starter.EEL-work<starters>,0,'initial waits are indexed before applicability checks';
is $starter.process({type=>'hit',timestamp=>0}).elems,100,'shared definition starts each event type independently';
$starter.finish;

event SafeFork {
 pattern TOP { <a=.event(:type<A>)> [<b=.event(:type<B>)> | <c=.event(:type<C>)>] <d=.event(:type<D>)> }
}
event MutableFork {
 has $.count;
 pattern TOP {
  :my %state = count=>0;
  :my $alias = %state;
  <.event(:type<A>)>
  [ <b=.event(:type<B>)> {$alias<count>++} | <c=.event(:type<B>)> {%state<count>+=2} ]
  <.event(:type<D>)> { $!count=%state<count> }
 }
}
sub run-forks($type,$reference) {
    my $r=EEL::Runner.new(:patterns[$type]); $r.EEL-reference-forks($reference);
    my @out;
    for <A B D>.kv -> $time,$type { @out.append($r.process({:$type,timestamp=>$time})) }
    @out.append($r.finish);
    [@out.map({.hash.keys.sort.Array}).Array,@out.map({try .count}).Array,$r.EEL-work]
}
my $fast=run-forks(SafeFork,False); my $slow=run-forks(SafeFork,True);
is-deeply $fast[0],$slow[0],'shared definitions preserve captures and source order';
ok $fast[2]<shared> > 0,'context-free frame shares compiled definition';
ok $fast[2]<rematerialized> < $slow[2]<rematerialized>,'safe forks avoid rematerialization';
my $mutable=run-forks(MutableFork,False);
is-deeply $mutable[1],[1,2],'aliases preserved within each mutable fork';
is $mutable[2]<shared>,0,'mutable/code frames retain conservative factory path';
my %cycle; %cycle<self> := %cycle;
my $copier=EEL::State.new; my $copy=$copier.copy(%cycle);
ok $copy<self> === $copy,'copier retains cyclic aliases';
ok $copy !=== %cycle,'copier isolates mutable source';

event Retained {
 pattern TOP { :partition{ .<session> } :!ignore-unexpected <.event(:type<S>)> <a=.event(:type<A>)>+! }
}
sub retained($reference) {
    my $r=EEL::Runner.new(:patterns[Retained]); $r.EEL-reference-retained($reference);
    for ^100 -> $id {
        $r.process({type=>'S',session=>$id,timestamp=>0});
        $r.process({type=>'A',session=>$id,timestamp=>0});
    }
    my $before=$r.EEL-work<retained>;
    $r.process({type=>'noise',session=>1000,timestamp=>1}) for ^10;
    my $after=$r.EEL-work<retained>;
    my @out=$r.finish;
    [@out.map(*.data<session>).Array,$after-$before]
}
my $retained=retained(False); my $reference=retained(True);
is-deeply $retained[0],$reference[0],'group-indexed results preserve EOF order';
is $retained[1],0,'unrelated events do not inspect retained results';
ok $reference[1] >= 1000,'reference scan exercises retained baseline';
done-testing;
