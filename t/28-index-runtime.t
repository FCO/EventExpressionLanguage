use lib 'lib';
use Test;
use EEL;
use Event;
use EEL::Runner;
use EEL::Query;
use EEL::Condition;
use EEL::MemoryStorage;

# Compare complete traces rather than generated event IDs.
event IndexedPaths {
 pattern TOP { :3s :partition{ .<session> } <s=.event(:type<S>)> [ <a=.event(:type<A>,:value(1 < * <= $<s>.limit))> | <b=.event(:type<B>)> ] <e=.event(:type<E>)> }
 pattern strict { :3s :partition{ .<session> } :!ignore-unexpected <s=.event(:type<S>)> <a=.event(:type<A>)>+! <e=.event(:type<E>)> }
 pattern shuffle { :4s :partition{ .<session> } <s=.event(:type<S>)> [ <a=.event(:type<A>)> <b=.event(:type<B>)> ] &&& [ <c=.event(:type<C>)> <e=.event(:type<E>)> ] }
 pattern priority { :3s :partition{ .<session> } [<s=.event(:type<S>)> <a=.event(:type<A>)> <e=.event(:type<E>)>] || [<s=.event(:type<S>)> <b=.event(:type<B>)>] }
 pattern tuple { :3s :partition{ .<session>, .<kind> } :!ignore-unexpected <s=.event(:type<S>)> <e=.event(:type<E>)> }
 pattern dynamic { :3s <s=.event(:type<S>)> :partition{ .<session> + $<s>.offset } <e=.event(:type<E>)> }
 pattern local-window { <s=.event(:type<S>)> [ :1s <a=.event(:type<A>)> <b=.event(:type<B>)> ] <e=.event(:type<E>)> }
}
sub signature($value) {
    return $value.map({signature($_)}).Array if $value ~~ Array;
    return $value.EEL-index if $value ~~ Event;
    $value
}
sub trace($rule,@events,$linear) {
    my $runner=EEL::Runner.new(:patterns[IndexedPaths],:$rule,:lateness(1));
    $runner.EEL-linear-search($linear);
    my @out;
    for @events -> $event { @out.append($runner.process($event)) }
    @out.append($runner.finish);
    @out.map({ %(captures=>.hash.map({ .key => signature(.value) }).Hash, data=>.data<ordinal>, timestamp=>.timestamp.Str) }).Array
}
srand(43019);
my @types=<S A B C E noise>;
my @input;
for ^120 -> $i {
    @input.push(%(type=>@types[$i % 6],session=>(^4).pick,kind=>(^2).pick,offset=>1,value=>(^10).pick,limit=>5,timestamp=>$i div 6,ordinal=>$i));
}
# Guaranteed completions plus overlapping starts, then a jump to expire windows.
@input.append([
 %(type=>'S',session=>7,kind=>1,offset=>1,limit=>5,timestamp=>21,ordinal=>120),
 %(type=>'A',session=>7,kind=>1,value=>4,timestamp=>22,ordinal=>121),
 %(type=>'B',session=>7,kind=>1,timestamp=>22,ordinal=>122),
 %(type=>'C',session=>7,kind=>1,timestamp=>22,ordinal=>123),
 %(type=>'E',session=>7,kind=>1,timestamp=>23,ordinal=>124),
 %(type=>'noise',timestamp=>30,ordinal=>125)
]);
for <TOP strict shuffle priority tuple dynamic local-window> -> $rule {
    is-deeply trace($rule,@input,False),trace($rule,@input,True),"indexed and linear traces agree for $rule";
}

# Explicit extraction yields descriptors, not an opaque WhateverCode.
event Bounds {
 pattern TOP { <.event(:value(1 < * <= 42))> }
}
sub calls($node) { gather { take $node if $node.kind eq 'call'; for $node.children { .take for calls($_) } } }
my $definition=Bounds.^find_method('TOP').instantiate(Bounds.new);
my $expected=calls($definition)[0].code.().hash<value>;
isa-ok $expected,EEL::Condition,'slang preserves comparison structure';
is $expected.plans('value')[0].elems,2,'chained comparisons have both interval restrictions';
{
    sub infix:«>»($a,$b) { True }
    event CustomOperator { pattern TOP { <.event(:value(* > 100))> } }
    my $r=EEL::Runner.new(:patterns[CustomOperator]);
    is $r.process({value=>0,timestamp=>0}).elems,1,'custom lexical comparison retains original semantics';
    $r.finish;
}
{
    sub any(*@values) { -> $v { $v == 99 } }
    event CustomJunction { pattern TOP { <.event(:value(any(1,5)))> } }
    my $r=EEL::Runner.new(:patterns[CustomJunction]);
    is $r.process({value=>99,timestamp=>0}).elems,1,'custom lexical any is not rewritten';
    $r.finish;
}
event SymbolicJunction {
 pattern TOP { <.event(:value(1 | 5))> }
 pattern comparison { <.event(:value(* == (1 | 5)))> }
}
for <TOP comparison> -> $rule {
    my $r=EEL::Runner.new(:patterns[SymbolicJunction],:$rule);
    is $r.process({value=>5,timestamp=>0}).elems,1,"symbolic Junction supports $rule";
    is $r.process({value=>2,timestamp=>0}).elems,0,"symbolic Junction rejects unrelated $rule";
    $r.finish;
}
# Unsupported numeric representations retain coercive native comparison.
my $s=EEL::MemoryStorage.new;
my $comparison=EEL::Condition.comparison('>',3);
for ^40 -> $id { $s.register(EEL::Query.new(:conditions{value=>$comparison}),$id) }
is $s.search({value=>'4'}).elems,40,'coercive string comparison falls back safely';
is $s.search({value=>4e0}).elems,40,'Num comparison falls back safely';
is $s.search({value=>3}).elems,0,'exact boundary excluded by index';
for ^40 -> $id { $s.remove($id+1) }
is $s.stats<slots>,0,'all wait slots released';
is $s.stats<query><tokens>,0,'all predicate index references released';
is $s.stats<temporal>,0,'all temporal tree nodes released';
$s.clear;
is $s.stats<deadlines>,0,'clear releases deadline tombstones';
my $type-storage=EEL::MemoryStorage.new;
class IndexBase {}
class IndexChild is IndexBase {}
for ^40 -> $i { $type-storage.register(EEL::Query.new(:conditions{type=>IndexBase}),$i) }
is $type-storage.search({type=>IndexBase}).elems,40,'type object posting is deduplicated across exact name and MRO';
is $type-storage.search({type=>IndexChild}).elems,40,'raw subtype object finds ancestor posting';
$type-storage.clear;
# Removal churn must not accumulate unbounded deadline entries.
for ^500 -> $i {
    my $id=$s.register(EEL::Query.new,$i,:deadline($i));
    $s.remove($id);
}
ok $s.stats<deadlines> <= 64,'deadline tombstones compact under churn';
$s.clear;
done-testing;
