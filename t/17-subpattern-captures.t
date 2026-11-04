use lib 'lib';
use Test;
use EEL;
event Collision {
    has $.id;
    has $.observed;
    pattern TOP {
        <requests=.request>+
        <.event(:type<finish>)>
        { $!id = $<requests>[0].id; $!observed = $<requests>[0].made }
    }
    pattern request {
        <inner=.nested>
        { $!id = 'internal' }
    }
    pattern nested { <raw=.event(:type<start>)> }
}
my @out;
({type=>'start',id=>'payload'},{type=>'start',id=>'second'},{type=>'finish'}).Supply.match(Collision).tap(-> $v { @out.push($v) });
is @out.elems,3,'repetition and overlapping matches remain independent';
is @out[0].id,'payload','derived attribute is assigned from delegated payload field';
is Collision.new(:made('action result')).EEL-capture.made,'action result','made is retained by capture view';
is @out[0]<requests>[0].id,'payload','internal domain attribute does not shadow payload';
is @out[0]<requests>[0]<inner>.id,'payload','nested capture delegates';
is @out[0]<requests>[0]<inner><raw>.id,'payload','raw capture delegates';
is @out.first({ .<requests>.elems == 2 })<requests>[1].id,'second','repeated captures retain separate data';
is @out[0]<requests>[0].data<id>,'payload','explicit data stays available';
my $p=run $*EXECUTABLE,'-Ilib','examples/login',:out,:err;
is $p.out.slurp(:close),"login session: 2 tries\n",'login example works with direct session-id';
is $p.err.slurp(:close),'','login has no uninitialized warning';
is $p.exitcode,0,'login exits successfully';
event Timed {
    has DateTime() $.start;
    has DateTime() $.end;
    pattern TOP {
        <first=.request>
        <last=.request>
        { $!start = $<first>.timestamp; $!end = $<last>.timestamp }
    }
    pattern request { <.event(:type<timed>)> }
}
my @timed;
({type=>'timed',timestamp=>DateTime.new('2026-01-01T00:00:00Z')},
 {type=>'timed',timestamp=>DateTime.new('2026-01-01T00:00:02Z')}).Supply.match(Timed).tap(-> $v { @timed.push($v) });
is @timed.elems,1,'direct timestamps can populate DateTime attributes';
isa-ok @timed[0].start,DateTime,'start coerces Instant to DateTime';
is @timed[0].start.Str,'2026-01-01T00:00:00Z','start timestamp retained';
is @timed[0].end.Str,'2026-01-01T00:00:02Z','end timestamp retained';
done-testing;
