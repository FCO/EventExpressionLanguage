use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
event Look {
 pattern partitioned { :partition{ .<key> } <?after <.event(:type<A>)>> <.event(:type<B>)> }
 pattern future { <.event(:type<A>)> <?before <.event(:type<B>)> <.event(:type<C>)>> <.event(:type<B>)> }
 pattern negative { <.event(:type<A>)> <!before <.event(:type<X>)>> <.event(:type<B>)> }
 pattern past { <?after <.event(:type<A>)>> <.event(:type<B>)> }
 pattern no-past { <!after <.event(:type<A>)>> <.event(:type<B>)> }
 pattern sequence { <.event(:type<B>)> <?after <.event(:type<A>)> <.event(:type<B>)>> }
}
sub feed($rule,@types) {
 my $r=EEL::Runner.new(:patterns[Look],:$rule);
 my @out;
 for @types.kv -> $timestamp,$type { @out.append($r.process(%(:$type,:$timestamp))) }
 @out.append($r.finish); @out.elems
}
is feed('future',<A B C>),1,'inline positive replays suffix';
is feed('future',<A B>),0,'incomplete future fails';
is feed('negative',<A B>),1,'inline negative confirms at consumption';
is feed('negative',<A X B>),0,'inline negative rejects witness';
is feed('past',<A B>),1,'lookbehind sees history before candidate';
is feed('past',<A X B>),0,'lookbehind must end at boundary';
is feed('no-past',['B']),1,'negative lookbehind accepts empty history';
is feed('no-past',<A B>),0,'negative lookbehind rejects prior match';
is feed('sequence',<A B>),1,'lookbehind includes just consumed event';
is feed('sequence',<A X B>),1,'lookbehind allows internal noise';
my $r=EEL::Runner.new(:patterns[Look],:rule<partitioned>);
$r.process({type=>'A',key=>1,timestamp=>0});
$r.process({type=>'X',key=>2,timestamp=>1});
is $r.process({type=>'B',key=>1,timestamp=>2}).elems,1,'other partition does not move historical boundary';
my $other=EEL::Runner.new(:patterns[Look],:rule<partitioned>);
$other.process({type=>'A',key=>1,timestamp=>0});
is $other.process({type=>'B',key=>2,timestamp=>1}).elems,0,'initial lookbehind binds prospective partition';
done-testing;
