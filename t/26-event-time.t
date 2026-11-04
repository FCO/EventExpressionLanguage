use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
event Zero { pattern TOP { :0s <.event(:type<S>)> <.event(:type<A>)> } }
my $r=EEL::Runner.new(:patterns[Zero]);
$r.process({type=>'S',timestamp=>2});
is $r.process({type=>'A',timestamp=>2}).elems,1,'equal timestamps are accepted at an inclusive zero deadline';
$r=EEL::Runner.new(:patterns[Zero]); $r.process({type=>'S',timestamp=>2});
is $r.process({type=>'A',timestamp=>2.000000001}).elems,0,'one nanosecond beyond deadline expires';
event Flow { pattern TOP { :5s <.event(:type<S>)> <.event(:type<A>)> } }
my $diagnostic=$*TMPDIR.add("eel-late-{$*PID}.txt");
LEAVE { $diagnostic.unlink if $diagnostic.defined && $diagnostic.e }
my $handle=$diagnostic.open(:w);
my @out;
{
 my $*ERR=$handle;
 ({type=>'S',timestamp=>10},{type=>'A',timestamp=>9},{type=>'A',timestamp=>11}).Supply.match(Flow,:reemit).tap(-> $v {@out.push($v)});
}
$handle.close;
is-deeply @out.grep(Associative).map(*.<timestamp>).Array,[10,11],'late input is not reemitted';
is @out.grep(Flow).elems,1,'discarding late event does not poison matching';
like $diagnostic.slurp,/'Late event'/,'late event diagnostic';
like $diagnostic.slurp,/'watermark'/,'diagnostic identifies confirmed time frontier';
$r=EEL::Runner.new(:patterns[Flow],:lateness(2));
$r.process({type=>'S',timestamp=>10});
is $r.pending,1,'pending includes temporal input queue';
is $r.finish.elems,0,'EOF drains queued input without inventing a match';
event Scoped {
 pattern inner { :1s <.event(:type<A>)> <.event(:type<B>)> }
 pattern TOP { :10s <.event(:type<S>)> <inner> <.event(:type<C>)> }
}
$r=EEL::Runner.new(:patterns[Scoped]);
$r.process({type=>'S',timestamp=>0}); $r.process({type=>'A',timestamp=>2}); $r.process({type=>'B',timestamp=>3});
is $r.process({type=>'C',timestamp=>9}).elems,1,'subpattern window ends independently of outer deadline';
event ShuffleTime {
 pattern TOP { :5s [ :1s <.event(:type<A>)> <.event(:type<B>)> ] &&& [ :4s <.event(:type<C>)> <.event(:type<D>)> ] }
}
sub timed($type,$end) {
 my @out; my $failure;
 ({type=>'C',timestamp=>0},{type=>'A',timestamp=>2},{type=>'D',timestamp=>3},{type=>'B',timestamp=>$end}).Supply.match($type).tap(-> $v {@out.push($v)},quit=>-> $e {$failure=$e});
 $failure.throw if $failure.defined; @out
}
is timed(ShuffleTime,3).elems,1,'each shuffled operand starts its window at its own first event';
is timed(ShuffleTime,3.000000001).elems,0,'expired operand prevents whole shuffle';
event CompletedWindow {
 pattern TOP { :5s [ :10s <.event(:type<A>)> <.event(:type<B>)> ] &&& [ :1s <.event(:type<C>)> <.event(:type<D>)> ] }
}
my @completed;
({type=>'C',timestamp=>0},{type=>'D',timestamp=>1},{type=>'A',timestamp=>2},{type=>'B',timestamp=>4}).Supply.match(CompletedWindow).tap(-> $v {@completed.push($v)});
is @completed.elems,1,'completed branch window does not invalidate later sibling completion';
for 'ms millisecond milliseconds'=>1/1000, 's sec second seconds'=>1, 'min minute minutes'=>60,
 'h hour hours'=>3600, 'd day days'=>86400, 'm month months'=>2592000, 'y year years'=>31536000 -> $units {
 for $units.key.words -> $unit {
  my $p=run $*EXECUTABLE,'-Ilib','-e',"use EEL; event U \{ pattern TOP \{ :1$unit <.event> \} \}; say U.new.TOP.children[0].children[0].properties<seconds>",:out,:err;
  is +$p.out.slurp(:close),$units.value,"alias $unit";
  is $p.err.slurp(:close),'',"$unit compiles quietly";
  is $p.exitcode,0,"$unit supported";
 }
}
event EOFError { pattern TOP { <.event(:type<X>)> { die 'buffered action error' } } }
$r=EEL::Runner.new(:patterns[EOFError],:lateness(1));
$r.process({type=>'X',timestamp=>2});
throws-like { $r.finish },X::AdHoc,message=>/'buffered action error'/,'EOF propagates queued action error';
is $r.pending,0,'EOF failure clears buffered state';
throws-like { $r.process({type=>'X',timestamp=>3}) },X::AdHoc,message=>/'failed'/,'failed EOF runner cannot be reused';
done-testing;
