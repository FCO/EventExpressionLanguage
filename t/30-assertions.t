use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
use EEL::Absence;
sub run($type,@types,Str :$rule='TOP',Bool :$linear=False,Bool :$finish=True) {
    my $r=EEL::Runner.new(:patterns[$type],:$rule); $r.EEL-linear-search($linear);
    my @out;
    for @types.kv -> $time,$type { @out.append($r.process(%(:$type,timestamp=>$time))) }
    @out.append($r.finish) if $finish;
    @out.Array
}
event Neg {
 pattern TOP { <a=.event(:type<A>)> <absence=!event: :type<B>> <c=.event(:type<C>)> }
 pattern strict { :!ignore-unexpected <a=.event(:type<A>)> <absence=!event(:type<B>)> <c=.event(:type<C>)> }
 pattern sequence { <a=.event(:type<A>)> <absence=!pair> <c=.event(:type<C>)> }
 pattern pair { <.event(:type<B>)> <.event(:type<C>)> }
 pattern consecutive { <.event(:type<A>)> <x=!event(:type<X>)> <y=!event(:type<Y>)> <.event(:type<C>)> }
}
is run(Neg,<A C>).elems,1,'negative accepts next positive step';
is run(Neg,<A X C>).elems,1,'negative ignores unrelated event in skip mode';
is run(Neg,<A B C>).elems,0,'forbidden input fails path';
is run(Neg,<A X B C>).elems,0,'forbidden event after noise still fails';
is run(Neg,<A C>,:rule<strict>).elems,1,'strict negative reuses same C occurrence';
is run(Neg,<A X C>,:rule<strict>).elems,0,'strict path fails when next occurrence cannot consume C';
is run(Neg,<A B C>,:rule<sequence>).elems,0,'sequence completing at C wins over positive C';
is run(Neg,<A B X C>,:rule<sequence>).elems,0,'negative sequence inherits skip mode';
is run(Neg,<A C B C>,:rule<sequence>).elems,1,'partial sequence is canceled at first consuming boundary';
my $n=run(Neg,<A X C>)[0];
isa-ok $n<absence>,EEL::Absence,'named negation captures evidence';
is $n<absence>.pattern,'event','absence identifies target';
is $n<absence>.reason,'next-step','absence records boundary';
is $n<absence>.started-at,Instant.from-posix(0),'absence starts at A timestamp';
is $n<absence>.confirmed-at,Instant.from-posix(2),'absence confirmed at C timestamp';
is $n<absence>.witness<type>,'C','witness is the actual raw C event';
is $n.data<type>,'C','main data comes from consuming step';
my $con=run(Neg,<A C>,:rule<consecutive>)[0];
isa-ok $con<x>,EEL::Absence,'first consecutive absence captured';
isa-ok $con<y>,EEL::Absence,'second consecutive absence captured';
is run(Neg,<A Y C>,:rule<consecutive>).elems,0,'any open prohibition can invalidate path';

event Pos {
 has $.seen;
 pattern TOP { <a=.event(:type<A>)> <data=?pair> { $!seen=$<data>.data<type> } <b=.event(:type<B>)> }
 pattern pair { <b=.event(:type<B>)> <c=.event(:type<C>)> }
 pattern strict { :!ignore-unexpected <.event(:type<A>)> <?pair> <.event(:type<B>)> }
 pattern simple { <a=.event(:type<A>)> <data=?event: :type<B>> <b=.event(:type<B>)> }
 pattern nested { <.event(:type<A>)> <?inner> <.event(:type<B>)> <.event(:type<C>)> }
 pattern inner { <?pair> <.event(:type<B>)> }
 pattern twice { <.event(:type<A>)> <?pair> <?pair> <.event(:type<B>)> <.event(:type<C>)> }
}
my $r=EEL::Runner.new(:patterns[Pos]);
is $r.process({type=>'A',timestamp=>0}).elems,0,'A starts positive assertion';
is $r.process({type=>'B',timestamp=>1}).elems,0,'B alone cannot publish before positive pair completes';
my @positive=$r.process({type=>'C',timestamp=>2});
is @positive.elems,1,'C confirms assertion and publishes deferred B result';
is @positive[0].timestamp,Instant.from-posix(1),'main result timestamp belongs to consumed B';
is @positive[0]<b>.EEL-index,2,'replay preserves original ordinal';
is @positive[0]<data><c>.EEL-index,3,'assertion capture has sequence captures';
is @positive[0].seen,'C','action after positive assertion sees confirmed capture';
$r.finish;
is run(Pos,<A B>).elems,0,'EOF does not turn incomplete positive into success';
is run(Pos,<A B B C>,:rule<strict>).elems,0,'strict positive does not restart after a failed prefix';
is run(Pos,<A X B C>).elems,1,'skip positive can search through noise';
is run(Pos,<A B>,:rule<simple>).elems,1,'single B serves assertion and consuming step';
is run(Pos,<A B C>,:rule<nested>).elems,1,'nested positive replays without reinjection';
is run(Pos,<A B C>,:rule<twice>).elems,1,'consecutive positives can reuse same history';

event Terminal {
 has $.reason;
 pattern TOP { :2s <a=.event(:type<A>)> <absence=!pair> { $!reason=$<absence>.reason } }
 pattern pair { <.event(:type<B>)> <.event(:type<C>)> }
 pattern unlimited { <a=.event(:type<A>)> <absence=!event(:type<B>)> { $!reason=$<absence>.reason } }
}
is run(Terminal,['A']).elems,1,'EOF confirms terminal absence';
is run(Terminal,<A B>).elems,1,'incomplete forbidden prefix permits EOF absence';
is run(Terminal,<A B C>).elems,0,'completed sequence rejects terminal absence';
is run(Terminal,<A X>)[0].reason,'eof','trailing action runs with confirmed absence';
$r=EEL::Runner.new(:patterns[Terminal]);
$r.process({type=>'A',timestamp=>0});
is $r.pending,1,'terminal absence remains pending during idle';
is $r.process({type=>'X',timestamp=>2}).elems,0,'deadline is inclusive';
my @window=$r.process({type=>'X',timestamp=>3});
is @window.elems,1,'watermark beyond deadline confirms terminal absence';
is @window[0]<absence>.reason,'window','window reason captured';
is @window[0]<absence>.confirmed-at,Instant.from-posix(2),'window confirmation uses deadline';
ok @window[0]<absence>.witness === Nil,'window has Nil witness';
is @window[0].reason,'window','trailing action waits for window confirmation';
$r.finish;
$r=EEL::Runner.new(:patterns[Terminal],:rule<unlimited>);
$r.process({type=>'A',timestamp=>0}); $r.close;
is $r.finish.elems,0,'cancellation does not confirm absence';
my $eof=run(Terminal,<A X>,:rule<unlimited>)[0]<absence>;
is $eof.confirmed-at,Instant.from-posix(1),'EOF uses last processed event time';
ok $eof.witness === Nil,'EOF has Nil witness';
for <TOP sequence strict> -> $rule {
    is-deeply run(Neg,<A X B C>,:$rule,:linear).map(*.hash.keys.sort.Array).Array,
        run(Neg,<A X B C>,:$rule).map(*.hash.keys.sort.Array).Array,"negative $rule agrees with linear routing";
}
done-testing;
