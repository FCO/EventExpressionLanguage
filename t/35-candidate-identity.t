use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
use JSON::Fast;

event Windowed {
    has UInt $.count = 0;
    pattern TOP { :3s [ <items=.event> { $!count++ } ]+ }
    pattern every { :3s [ <items=.event> { $!count++ } ]+! }
}
my $runner=EEL::Runner.new(:patterns[Windowed]);
my @matches;
@matches.append($runner.process(%(timestamp=>$_))) for ^5;
is-deeply @matches.map(*.count).Array, [1,2,3,3,3], 'window selects growing candidates';
is-deeply @matches.head(3).map(*.event-id).unique.Array, [@matches[0].event-id],
    'growth of the first candidate preserves its identity';
isnt @matches[3].event-id, @matches[2].event-id, 'expiry promotes a different candidate ID';
isnt @matches[4].event-id, @matches[3].event-id, 'next expiry promotes another candidate ID';
is @matches.map(*.event-id).unique.elems, 3, 'three winning starts have three identities';
is-deeply @matches.map(*.timestamp).Array, (^5).map({ Instant.from-posix($_) }).Array,
    'stable identity still has the timestamp of each conclusion';
is $runner.finish.elems, 0, 'EOF does not replay candidate snapshots';

$runner=EEL::Runner.new(:patterns[Windowed], :rule<every>);
my %ids;
my @saved;
for ^5 -> $timestamp {
    for $runner.process({:$timestamp}) -> $match {
        my $start=$match<items>[0].data<timestamp>;
        if %ids{$start}:exists {
            is $match.event-id, %ids{$start}, "candidate $start keeps its ID when extended";
        } else {
            nok $match.event-id eq any(%ids.values), "start $start has a new candidate ID";
            %ids{$start}=$match.event-id;
        }
        @saved.push([$match,$match.event-id,$match.count,$match.timestamp]);
    }
}
for @saved -> ($match,$id,$count,$time) {
    is-deeply [$match.event-id,$match.count,$match.timestamp], [$id,$count,$time],
        'later growth does not mutate a previously emitted snapshot';
}
is %ids.elems, 5, 'each input started a distinct candidate';

# Exercise the exact inline CLI path, including lookahead and partition binding.
my $source=q:to/PATTERN/;
event DistroUpload {
    has Str $.distro;
    has UInt $.tries = 0;
    pattern TOP {
        :1h :ignore-unexpected :partition{.<distro>}
        <event=?event: :distro(*.defined)> { $!distro = $<event>.distro }
        [ <event: :$!distro> { $!tries++ } ]+
    }
}
PATTERN
my $proc=run $*EXECUTABLE, '-Ilib', 'bin/eel.raku', '-e', $source, :in, :out, :err;
for <bla bla ble bla ble> -> $distro { $proc.in.say(to-json({:$distro}, :!pretty)) }
$proc.in.close;
my @out=$proc.out.lines.map({ from-json($_) }).Array;
my $err=$proc.err.slurp(:close);
is $proc.exitcode, 0, 'inline CLI example succeeds';
is $err, '', 'inline CLI example has no diagnostics';
is-deeply @out.map(*.<tries>).Array, [1,2,1,3,2], 'CLI emits the largest candidate per partition';
is @out.grep(*.<distro> eq 'bla').map(*.<event-id>).unique.elems, 1,
    'CLI preserves the bla candidate ID across emissions';
is @out.grep(*.<distro> eq 'ble').map(*.<event-id>).unique.elems, 1,
    'CLI preserves the ble candidate ID across emissions';
is @out.map(*.<event-id>).unique.elems, 2, 'different partition candidates have different IDs';
done-testing;
