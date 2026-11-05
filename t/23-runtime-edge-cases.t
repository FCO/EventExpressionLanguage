use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
sub collect($type,@input) {
 my @out; my $failure;
 @input.Supply.match($type).tap(-> $v {@out.push($v)},quit=>-> $e {$failure=$e});
 $failure.throw if $failure.defined;
 @out
}
event Repeated {
 pattern TOP { :!ignore-unexpected (<value=.event(:type<A>)>)+ <.event(:type<end>)> }
}
my @repeat=collect(Repeated,[{type=>'A',id=>1},{type=>'A',id=>2},{type=>'end'}]);
my $two=@repeat.first({ .list[0] ~~ Array && .list[0].elems == 2 });
ok $two.defined,'repeated positional groups accumulate';
is $two[0][0]<value>.id,1,'first repeated group contains its own named capture';
is $two[0][1]<value>.id,2,'second repeated group excludes prior iteration';
my @single=collect(Repeated,[{type=>'A',id=>3},{type=>'end'}]);
isa-ok @single[0][0],Array,'quantified positional group is an array even for one occurrence';
is @single[0][0][0]<value>.id,3,'single quantified group retains input';
event Nested {
 pattern TOP { ( <a=.event(:type<A>)> ( <b=.event(:type<B>)> ) ) }
}
my @nested=collect(Nested,[{type=>'A',id=>1},{type=>'B',id=>2}]);
is @nested[0][0][1]<b>.id,2,'outer capture preserves nested source-numbered positional group';
event Tuple {
 pattern TOP { :partition{ .<a>,.<b> } :!ignore-unexpected <.event(:type<A>)> <.event(:type<B>)> }
}
is collect(Tuple,[{type=>'A',a=>'a b',b=>'c'},{type=>'B',a=>'a',b=>'b c'},{type=>'B',a=>'a b',b=>'c'}]).elems,1,'tuple keys do not collide through string concatenation';
is collect(Tuple,[{type=>'A',a=>1,b=>'x'},{type=>'B',a=>'1',b=>'x'}]).elems,0,'numeric and string key components remain distinct';
event PerSubpattern {
 pattern TOP { :partition{.<customer>} :!ignore-unexpected <start=.event(:type<start>)> <payment> <.event(:type<finish>)> }
 pattern payment { :partition{.<order>} [<.event(:type<paid>)> | <.event(:type<paid>)>] }
}
is collect(PerSubpattern,[{type=>'start',customer=>1,order=>4},{type=>'paid',customer=>2,order=>4},{type=>'finish',customer=>1}]).elems,2,'subpattern partition restores caller across forks';
event Cyclic {
 pattern TOP { :partition{ .<key> } <.event> }
}
my %cycle; %cycle<self> := %cycle;
throws-like { collect(Cyclic,[{key=>%cycle}]) },X::AdHoc,message=>/'Cyclic partition key'/,'cyclic keys rejected';
event PriorityWindow {
 pattern TOP { [ :1s <.event(:type<A>)> <.event(:type<B>)>] || <.event(:type<A>)> }
}
my $time=0;
my $window=EEL::Runner.new(:patterns[PriorityWindow]);
is $window.process({type=>'A',timestamp=>0}).elems,0,'windowed higher-priority path blocks fallback';
$time=2_000_000_000;
is $window.process({type=>'noise',timestamp=>2}).elems,1,'expiration releases fallback in next round';
my $cancel=EEL::Runner.new(:patterns[PriorityWindow]);
$cancel.process({type=>'A'}); $cancel.close;
is $cancel.finish.elems,0,'cancellation discards buffered fallback';
event EqualOperands { pattern TOP { <.event(:type<A>)> & <.event(:type<A>)> } }
is collect(EqualOperands,[{type=>'A'}]).elems,0,'one occurrence cannot fill two conjunction operands';
is collect(EqualOperands,[{type=>'A'},{type=>'A'}]).elems,2,'distinct operand permutations remain independent recognitions';
my $source=Supplier.new;
my $tap; my $done=0; my $emitted=0;
$tap=$source.Supply.match(PriorityWindow).tap(-> $v { $emitted++; $tap.close },done=>{ $done++ });
$source.emit({type=>'A'}); $source.done;
is $emitted,1,'EOF can emit a buffered result';
is $done,0,'cancelling during EOF output suppresses done callback';
event CaptureScope {
 pattern TOP { <outside=.event(:type<start>)> ( <inside=.event(:type<A>)> | <inside=.event(:type<B>)> ) }
}
my @scoped=collect(CaptureScope,[{type=>'start'},{type=>'A'}]);
ok !(@scoped[0][0].hash<outside>:exists),'forked positional capture excludes names from before the group';
is @scoped[0][0]<inside>.data<type>,'A','forked positional capture retains its own name';
event FirstKeyAcrossFork {
 pattern TOP { :partition{ .<ip> } :!ignore-unexpected [ <.event(:type<A>)> | <.event(:type<A>)> ] <.event(:type<B>)> }
}
my @bound=collect(FirstKeyAcrossFork,[{type=>'A',ip=>1},{type=>'B',ip=>2},{type=>'B',ip=>1}]);
is @bound.elems,2,'first key binding survives group restoration after a fork';
ok @bound.map(*.data<ip>).all == 1,'other partition cannot complete either fork';
done-testing;
