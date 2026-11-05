use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
sub matches($type,@input) {
 my @out; my $error;
 @input.Supply.match($type).tap(-> $v {@out.push($v)},quit=>-> $e {$error=$e});
 $error.throw if $error.defined;
 @out
}
event Positions {
 has $.id;
 pattern TOP { (<a=.event(:type<A>)>) (<b=.event(:type<B>)>) { $!id=$0<a>.id } }
}
my @p=matches(Positions,[{type=>'A',id=>1},{type=>'B',id=>2}]);
is @p[0].id,1,'$0 available to action';
is @p[0][1]<b>.id,2,'second positional capture';
event Both {
 pattern TOP { :!ignore-unexpected [<.event(:type<A>)> <.event(:type<B>)>] & [<.event(:type<C>)> <.event(:type<D>)>] }
}
is matches(Both,<A B C D>.map({{type=>$_}}).Array).elems,1,'conjunction forward order';
is matches(Both,<C D A B>.map({{type=>$_}}).Array).elems,1,'conjunction reverse order';
is matches(Both,<A C B D>.map({{type=>$_}}).Array).elems,0,'conjunction does not interleave operands';
event Partition {
 pattern TOP { :partition{.<ip>} :!ignore-unexpected <start=.event(:type<A>)> <end=.event(:type<B>)> }
}
my @partition=matches(Partition,[{type=>'A',ip=>1},{type=>'A',ip=>2},{type=>'B',ip=>1},{type=>'B',ip=>2}]);
is @partition.elems,2,'strict matches isolated by partition';
is-deeply @partition.map(*.<end>.ip).Array,[1,2],'partition keys retained across forks';
is matches(Partition,[{type=>'A'},{type=>'B'}]).elems,1,'undefined keys form a partition';
event Change {
 pattern TOP {
  :partition{.<customer>} :!ignore-unexpected <start=.event(:type<start>)>
  [ :partition{.<order>} <payment=.event(:type<paid>)> ]
  <finish=.event(:type<finish>)>
 }
}
my @change=matches(Change,[{type=>'start',customer=>1,order=>4},{type=>'paid',customer=>2,order=>4},{type=>'finish',customer=>1}]);
is @change.elems,1,'dynamic partition change and restoration';
event Priority {
 pattern TOP { :!ignore-unexpected [<value=.event(:type<A>)> <.event(:type<B>)>] || <value=.event(:type<A>)> }
}
my $r=EEL::Runner.new(:patterns[Priority]);
is $r.process({type=>'A',id=>8}).elems,0,'right result held while left remains viable';
is $r.finish[0]<value>.id,8,'EOF releases fallback result';
my $left=EEL::Runner.new(:patterns[Priority]);
$left.process({type=>'A'});
is $left.process({type=>'B'}).elems,1,'left completion wins';
is $left.finish.elems,0,'losing right result discarded';
event Retry {
 pattern TOP { :!ignore-unexpected [<.event(:type<A>)> || [<.event(:type<A>)> <.event(:type<B>)>]] <.event(:type<C>)> }
}
is matches(Retry,<A B C>.map({{type=>$_}}).Array).elems,1,'right alternative survives failure of left suffix';
done-testing;
