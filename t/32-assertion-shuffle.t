use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
event Observing {
 pattern TOP { <.event(:type<A>)> [ [ <proof=?pair> <b=.event(:type<B>)> ] &&& <d=.event(:type<D>)> ] }
 pattern pair { <.event(:type<B>)> <.event(:type<C>)> }
}
my $r=EEL::Runner.new(:patterns[Observing]); my @out;
for <A B D C>.kv -> $time,$type { @out.append($r.process(%(:$type,timestamp=>$time))) }
@out.append($r.finish);
is @out.elems,1,'lookahead in shuffle completes with interleaved sibling';
is @out[0].timestamp,Instant.from-posix(2),'assertion confirmation does not replace last consumed timestamp';
is @out[0].data<type>,'D','result data comes from latest consumed sibling event';
is @out[0]<b>.EEL-index,2,'replayed branch preserves original consumed ordinal';
is @out[0]<proof>.data<type>,'C','proof still includes observed C';
ok !@out[0].hash.keys.first(*.starts-with('__eel-')).defined,'private monitor captures do not leak';

event SharedObservation {
 pattern TOP { <.event(:type<A>)> [ [ <?pair> <b=.event(:type<B>)> ] &&& <c=.event(:type<C>)> ] }
 pattern pair { <.event(:type<B>)> <.event(:type<C>)> }
}
$r=EEL::Runner.new(:patterns[SharedObservation]); @out=();
for <A B C>.kv -> $time,$type { @out.append($r.process(%(:$type,timestamp=>$time))) }
@out.append($r.finish);
ok @out.elems > 0,'assertion can observe an occurrence assigned to another branch';
is @out[0]<b>.EEL-index,2,'first branch consumes B';
is @out[0]<c>.EEL-index,3,'second branch consumes C';

event Exclusive {
 pattern TOP { <.event(:type<A>)> [ [ <?pair> <b=.event(:type<B>)> <c=.event(:type<C>)> ] &&& <other=.event(:type<C>)> ] }
 pattern pair { <.event(:type<B>)> <.event(:type<C>)> }
}
sub feed(@types) {
 my $runner=EEL::Runner.new(:patterns[Exclusive]); my @results;
 for @types.kv -> $time,$type { @results.append($runner.process(%(:$type,timestamp=>$time))) }
 @results.append($runner.finish); @results.Array
}
is feed(<A B C>).elems,0,'replay cannot assign one C to two consuming branches';
my @distinct=feed(<A B C C>);
ok @distinct.elems > 0,'two distinct C occurrences permit both branches';
ok @distinct.map({ .<c>.EEL-index != .<other>.EEL-index }).all,'each successful path uses distinct C ordinals';

event ProhibitedSibling {
 pattern TOP { <.event(:type<A>)> [ [ <abs=!event(:type<X>)> <b=.event(:type<B>)> ] &&& <x=.event(:type<X>)> ] }
}
$r=EEL::Runner.new(:patterns[ProhibitedSibling]); @out=();
for <A X B>.kv -> $time,$type { @out.append($r.process(%(:$type,timestamp=>$time))) }
@out.append($r.finish);
is @out.elems,0,'negative assertion observes a forbidden occurrence consumed by sibling';
event PrefixGuard {
 pattern TOP { <.event(:type<A>)> <absence=!event(:type<X>)> [ [ <?pair> <e=.event(:type<E>)> ] &&& <d=.event(:type<D>)> ] }
 pattern pair { <.event(:type<B>)> <.event(:type<C>)> }
}
$r=EEL::Runner.new(:patterns[PrefixGuard]); @out=();
for <A B X D C E>.kv -> $time,$type { @out.append($r.process(%(:$type,timestamp=>$time))) }
@out.append($r.finish);
is @out.elems,0,'outer negative does not close on a probe with no actual main consumption';

event EarlierBoundary {
 pattern TOP { <.event(:type<A>)> <absence=!event(:type<X>)> [ [ <?pair> <b=.event(:type<B>)> ] &&& <d=.event(:type<D>)> ] }
 pattern pair { <.event(:type<B>)> <.event(:type<C>)> }
}
$r=EEL::Runner.new(:patterns[EarlierBoundary]); @out=();
for <A B X D C>.kv -> $time,$type { @out.append($r.process(%(:$type,timestamp=>$time))) }
@out.append($r.finish);
is @out.elems,1,'outer negative can close on an earlier replayed main occurrence';
is @out[0]<absence>.witness<type>,'B','absence evidence uses actual replay boundary';

event ImmediateProof {
 pattern TOP { <.event(:type<A>)> [ [ <?pair> <b=.event(:type<B>)> ] &&& <d=.event(:type<D>)> ] }
 pattern pair { <.event(:type<B>)> <.event(:type<D>)> }
}
$r=EEL::Runner.new(:patterns[ImmediateProof]);
$r.process({type=>'A',timestamp=>0}); $r.process({type=>'B',timestamp=>1});
is $r.process({type=>'D',timestamp=>2}).elems,1,'observers in sibling branches update in the same round';
$r.finish;
done-testing;
