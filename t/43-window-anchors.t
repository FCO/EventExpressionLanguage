use lib 'lib';
use Test;
use EEL;
use EEL::Runner;

event WindowAnchors {
    has $.count = 0;
    has $.mark;
    pattern TOP {
        :1h ^ :partition{ .<distro> }
        <first=.event(:distro(*.defined))>
        [ <item=.event> <?{ ++$!count <= 4 }> ]+
    }
    pattern bounded { :10s ^ [ <item=.event(:type<A>)> { ++$!count } ] ** 1..4 }
    pattern growing { :10s ^ <item=.event(:type<A>)>+ { $!count=$<item>.elems } }
    pattern delayed {
        :10s ^ <first=.event(:type<A>)>
        <last=.event(:type<B>, :id($<first>.id))>
    }
    pattern simultaneous { :10s ^ <first=.event(:type<A>)> <.event(:type<B>)> }
    pattern end { :2s <first=.event(:type<A>)> $ { $!mark='closed' } }
    pattern absolute-end { :2s <.event(:type<A>)> $$ { $!mark='EOF' } }
    pattern absolute-start { :2s ^^ <.event(:type<A>)> }
    pattern absolute { ^^ <.event(:type<A>)> $$ }
    pattern stream { ^ <.event(:type<A>)> $ }
    pattern final { :2s ^ <item=.event(:type<A>)>+ $ { $!count=$<item>.elems } }
    pattern middle { :2s <.event(:type<A>)> ^ <.event(:type<B>)> }
    pattern nested { :10s <.event(:type<A>)> [ :2s ^ <.event(:type<B>)> $ { $!mark='inner' } ] }
    pattern outer-end { :2s <.event(:type<A>)> [ :10s <.event(:type<B>)> $ ] }
    pattern partition-end { :2s :partition{ .<key> } <.event(:type<A>)> $ }
    pattern mixed-size {
        :10s ^ <first=.event(:type<A>)>
        <items=.event(:type<I>, :id($<first>.id))>+ <.event(:type<Z>)>
    }
    pattern held { :10s ^ <first=.event(:type<A>)> [ <.event(:type<B>)> || <.event(:type<C>)> ] }
    pattern alternatives { :10s ^ <first=.event(:type<A>)> [ <.event(:type<B>)> | <.event(:type<C>)> ] }
    pattern sub { :2s ^ <.event(:type<A>)> $ }
    pattern subcall { <sub> }
    pattern shuffle { [ :2s ^ <.event(:type<A>)> $ ] &&& <.event(:type<B>)> }
}
sub runner($rule='TOP') { EEL::Runner.new(:patterns[WindowAnchors], :$rule) }
sub input($r,$time,$type='A',*%fields) { $r.process({timestamp=>$time,:$type,|%fields}) }
my $r=runner;
my @out;
for ^50 -> $timestamp { @out.append($r.process({:$timestamp,distro=>'bla'})) }
is-deeply @out.map(*.count).Array,[1,2,3,4],'50 inputs emit only four snapshots';
is @out.map(*.event-id).unique.elems,1,'winner keeps identity';
is $r.finish.elems,0,'EOF does not replay suppressed snapshots';

my $g=runner('growing');
my @a=input($g,0); my @b=input($g,1);
is @b[0].count,2,'oldest completed start grows';
is @b[0].event-id,@a[0].event-id,'same winner publishes updates';
is input($g,10,'X').elems,0,'expiration alone does not publish old completion';
my @promoted=input($g,10.5);
is @promoted.elems,1,'successor emits on new match';
is @promoted[0].count,2,'successor retains suppressed growth';
isnt @promoted[0].event-id,@a[0].event-id,'successor has its own identity';
is @b[0].count,2,'saved snapshot remains unchanged';

my $d=runner('delayed');
input($d,0,'A',:id(1)); input($d,1,'A',:id(2));
my @won=input($d,2,'B',:id(2));
is @won.elems,1,'incomplete older start does not block';
is @won[0]<first>.id,2,'newer complete candidate wins';
is input($d,3,'B',:id(1)).elems,0,'older incomplete candidate was discarded';
my $s=runner('simultaneous');
input($s,0); input($s,1);
my @ties=input($s,2,'B');
is @ties.elems,1,'one simultaneous winner';
is @ties[0]<first>.data<timestamp>,0,'earliest initial timestamp wins';
my $tie=runner('simultaneous'); input($tie,0,'A',:id(1)); input($tie,0,'A',:id(2));
is input($tie,1,'B')[0]<first>.id,1,'equal timestamps use stable input order';

my $parts=runner;
my @parts;
for ^6 -> $time {
    @parts.append($parts.process({timestamp=>$time,distro=>'a'}));
    @parts.append($parts.process({timestamp=>$time,distro=>'b'}));
}
is-deeply @parts.grep(*.data<distro> eq 'a').map(*.count).Array,[1,2,3,4],'partition a has independent winner';
is-deeply @parts.grep(*.data<distro> eq 'b').map(*.count).Array,[1,2,3,4],'partition b has independent winner';

my $end=runner('end');
is input($end,0).elems,0,'dollar waits';
my @closed=input($end,2,'X');
is @closed.elems,1,'window closure confirms dollar at exclusive limit';
is @closed[0].mark,'closed','suffix runs after closure';
is @closed[0].timestamp,Instant.from-posix(0),'result keeps last consumed timestamp';
my $noise=runner('end'); input($noise,0); input($noise,1,'X');
is input($noise,2,'X').elems,0,'intervening partition input invalidates end wait';
my $early=runner('end'); input($early,0);
is $early.finish.elems,1,'EOF can close dollar before deadline';
my $cancel=runner('end'); input($cancel,0); $cancel.close;
is $cancel.finish.elems,0,'cancellation does not confirm dollar';
my $absolute=runner('absolute-end'); input($absolute,0);
is input($absolute,2,'X').elems,0,'window expiration does not confirm double dollar';
is $absolute.finish.elems,0,'expired EOF wait cannot revive';
my $eof=runner('absolute-end'); input($eof,0);
is $eof.finish[0].mark,'EOF','double dollar confirms real EOF';
for <absolute stream> -> $rule {
    my $whole=runner($rule); input($whole,0);
    is $whole.finish.elems,1,"$rule: complete stream";
    my $shifted=runner($rule); input($shifted,0,'X'); input($shifted,1);
    is $shifted.finish.elems,0,"$rule: cannot shift past stream start";
}
my $start=runner('absolute-start'); input($start,0,'X');
is input($start,1).elems,0,'double caret cannot shift inside a window';
my $middle=runner('middle'); input($middle,0);
is input($middle,1,'B').elems,0,'caret cannot follow consumption in same window';
my $final=runner('final'); input($final,0); input($final,1);
my @final=input($final,2,'X');
is @final.elems,1,'caret and dollar publish at closure';
is @final[0].count,2,'closed match contains final accumulated state';
my $nested=runner('nested'); input($nested,0); input($nested,1,'B');
is input($nested,3,'X')[0].mark,'inner','anchors use innermost active window';
my $outer=runner('outer-end'); input($outer,0); input($outer,1,'B');
is input($outer,2,'X').elems,0,'earlier outer expiration cannot confirm inner dollar';
my $partition=runner('partition-end'); input($partition,0,'A',:key<a>); input($partition,1,'X',:key<b>);
is input($partition,2,'X',:key<b>).elems,1,'other partition does not invalidate closure';
my $alt=runner('alternatives'); input($alt,0); input($alt,1);
is input($alt,2,'C')[0]<first>.data<timestamp>,0,'alternative forks preserve window priority';
my $call=runner('subcall'); input($call,0);
is input($call,2,'X').elems,1,'subpattern preserves window closing wait';
my $shuffle=runner('shuffle'); input($shuffle,0); input($shuffle,1,'B');
is input($shuffle,2,'X').elems,1,'window anchor works in shuffle';
my $mixed=runner('mixed-size');
input($mixed,0,'A',:id(1)); input($mixed,1,'A',:id(2));
input($mixed,2,'I',:id(1)); input($mixed,3,'I',:id(2)); input($mixed,4,'I',:id(2));
my @mixed=input($mixed,5,'Z');
is @mixed.elems,1,'one winner when repeat sizes differ';
is @mixed[0]<first>.id,1,'window priority precedes repeat size across starts';
my $held=runner('held'); input($held,0); input($held,1,'B');
input($held,2); input($held,3,'C');
is input($held,10,'X').elems,0,'promotion cannot release suppressed ordered alternative';
is input($held,12,'X').elems,0,'later alternative resolution cannot replay suppressed match';
my $after-noise=runner('growing'); input($after-noise,0,'X');
is input($after-noise,1)[0].count,1,'window caret can start after unrelated stream input';
my $bounded=runner('bounded'); my @bounded;
for ^8 -> $time { @bounded.append(input($bounded,$time)) }
is-deeply @bounded.map(*.count).Array,[1,2,3,4],'reaching a repeat bound retains window ownership';
my $buffered=EEL::Runner.new(:patterns[WindowAnchors],:rule<end>,:lateness(2));
is input($buffered,0).elems,0,'lateness buffers the initial event';
is input($buffered,3,'X').elems,0,'watermark before deadline leaves end wait pending';
is input($buffered,4,'X').elems,1,'watermark reaching deadline confirms dollar without consuming future input';
done-testing;
