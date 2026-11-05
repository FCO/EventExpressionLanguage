use lib 'lib';
use Test;
use EEL;
sub matches($type,@input) {
 my @out; my $error;
 @input.Supply.match($type).tap(-> $v {@out.push($v)},quit=>-> $e {$error=$e});
 $error.throw if $error.defined; @out
}
event Interleave {
 pattern TOP { :!ignore-unexpected [ <a=.event(:type<A>)> <b=.event(:type<B>)> ] &&& [ <c=.event(:type<C>)> <d=.event(:type<D>)> ] }
}
for <ABCD ACBD ACDB CABD CADB CDAB> -> $order {
 my @out=matches(Interleave,$order.comb.map({%(type=>$_)}).Array);
 is @out.elems,1,"accepts $order";
 is @out[0]<a>.data<type>,'A','left capture retained';
 is @out[0]<d>.data<type>,'D','right capture retained';
}
is matches(Interleave,<A D B C>.map({%(type=>$_)}).Array).elems,0,'each operand retains internal order';
event Equal { pattern TOP { <.event(:type<A>)> &&& <.event(:type<A>)> } }
is matches(Equal,[{type=>'A'}]).elems,0,'one occurrence belongs to one branch';
is matches(Equal,[{type=>'A'},{type=>'A'}]).elems,2,'ambiguous assignments create distinct paths';
event Nested {
 pattern TOP { :!ignore-unexpected [ <.event(:type<A>)> &&& <.event(:type<B>)> ] &&& <.event(:type<C>)> }
}
for <ABC ACB BAC BCA CAB CBA> -> $order {
 is matches(Nested,$order.comb.map({%(type=>$_)}).Array).elems,1,"nested shuffle accepts $order";
}
event Calls {
 pattern left { <a=.event(:type<A>)> <b=.event(:type<B>)> }
 pattern right { <c=.event(:type<C>)> <d=.event(:type<D>)> }
 pattern TOP { :!ignore-unexpected &&& <left> &&& <right> }
}
my @calls=matches(Calls,<A C B D>.map({%(type=>$_)}).Array);
is @calls.elems,1,'subpattern calls interleave';
is @calls[0]<left><b>.data<type>,'B','nested captures retained';
event Parts {
 pattern left { :partition{.<order>} <paid=.event(:type<paid>)> }
 pattern right { <sent=.event(:type<sent>)> }
 pattern TOP { :partition{.<customer>} :!ignore-unexpected <.event(:type<start>)> [ <left> &&& <right> ] <.event(:type<finish>)> }
}
my @parts=matches(Parts,[{type=>'start',customer=>1,order=>4},{type=>'paid',customer=>9,order=>99},
 {type=>'sent',customer=>1},{type=>'paid',customer=>9,order=>4},{type=>'finish',customer=>1}]);
is @parts.elems,1,'branches retain distinct partitions and restore outer scope';
is @parts[0]<left><paid>.order,4,'child partition anchors to last event before call';
event SharedName {
 pattern TOP { :!ignore-unexpected [ <x=.event(:type<A>)> <x=.event(:type<B>)> ] &&& [ <x=.event(:type<C>)> <x=.event(:type<D>)> ] }
}
my @same=matches(SharedName,<A C B D>.map({%(type=>$_)}).Array);
is-deeply @same[0]<x>.map(*.data<type>).Array,['A','C','B','D'],'repeated names preserve global input order';
event Fields {
 has $.left=0;
 has $.right=0;
 pattern TOP { [<.event(:type<A>)> { $!left=1 }] &&& [<.event(:type<B>)> { $!right=2 }] }
}
my @fields=matches(Fields,[{type=>'B'},{type=>'A'}]);
is @fields[0].left,1,'left branch action field retained';
is @fields[0].right,2,'right branch action field not overwritten by sibling default';
event OuterLocal {
 has $.count;
 pattern TOP {
  :my %state = count=>0;
  :my $alias = %state;
  [ [<.event(:type<A>)> { $alias<count>++ }] &&& [<.event(:type<B>)> { %state<count>++ }] ]
  { $!count = %state<count> }
 }
}
my @local=matches(OuterLocal,[{type=>'B'},{type=>'A'}]);
is @local[0].count,2,'outer lexical containers and aliases survive branch switching';
event PrefixActions {
 has $.count=0;
 has $.lexical;
 pattern TOP {
  :my $n=0;
  [ [ { $n++; $!count++ } <.event(:type<A>)> ] &&& [ { $n++; $!count++ } <.event(:type<B>)> ] ]
  { $!lexical=$n }
 }
}
my @prefix=matches(PrefixActions,[{type=>'B'},{type=>'A'}]);
is @prefix[0].count,2,'epsilon branch actions share domain state within the chosen path';
is @prefix[0].lexical,2,'epsilon branch actions preserve outer lexical state';
done-testing;
