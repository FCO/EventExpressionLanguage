use lib 'lib';
use Test;
use EEL;
use EEL::Runner;

event Counts {
    has $.count is rw = 0;
    pattern star { :3s [ <items=.event> { $!count++ } ]* }
    pattern star-min { :3s [ <items=.event> { $!count++ } ]*? }
    pattern star-every { :3s [ <items=.event> { $!count++ } ]*! }
    pattern plus { :3s [ <items=.event> { $!count++ } ]+ }
    pattern plus-min { :3s [ <items=.event> { $!count++ } ]+? }
    pattern plus-every { :3s [ <items=.event> { $!count++ } ]+! }
    pattern optional { :3s [ <items=.event> { $!count++ } ]? }
    pattern optional-min { :3s [ <items=.event> { $!count++ } ]?? }
    pattern optional-every { :3s [ <items=.event> { $!count++ } ]?! }
    pattern bounded { :3s [ <items=.event> { $!count++ } ] ** 2..3 }
    pattern bounded-min { :3s [ <items=.event> { $!count++ } ] ** 2..3? }
    pattern bounded-every { :3s [ <items=.event> { $!count++ } ] ** 2..3! }
    pattern exact { :3s [ <items=.event> { $!count++ } ] ** 2 }
    pattern exact-min { :3s [ <items=.event> { $!count++ } ] ** 2? }
    pattern exact-every { :3s [ <items=.event> { $!count++ } ] ** 2! }
    pattern open-min { :3s [ <items=.event> { $!count++ } ] ** 0..*? }
    pattern partitioned { :3s :partition{ .<key> } [ <items=.event> { $!count++ } ]+ }
}

for
    'star' => [[1],[2],[3],[3],[3]],
    'star-min' => [[0],[0],[0],[0],[0]],
    'star-every' => [[0,1],[0,1,2],[0,1,2,3],[0,1,2,3],[0,1,2,3]],
    'plus' => [[1],[2],[3],[3],[3]],
    'plus-min' => [[1],[1],[1],[1],[1]],
    'plus-every' => [[1],[1,2],[1,2,3],[1,2,3],[1,2,3]],
    'optional' => [[1],[1],[1],[1],[1]],
    'optional-min' => [[0],[0],[0],[0],[0]],
    'optional-every' => [[0,1],[0,1],[0,1],[0,1],[0,1]],
    'bounded' => [[],[2],[3],[3],[3]],
    'bounded-min' => [[],[2],[2],[2],[2]],
    'bounded-every' => [[],[2],[2,3],[2,3],[2,3]],
    'exact' => [[],[2],[2],[2],[2]],
    'exact-min' => [[],[2],[2],[2],[2]],
    'exact-every' => [[],[2],[2],[2],[2]],
    'open-min' => [[0],[0],[0],[0],[0]]
-> $case {
    my $runner=EEL::Runner.new(:patterns[Counts], :rule($case.key));
    my @rounds;
    my @saved;
    for ^5 -> $timestamp {
        my @matches=$runner.process({:$timestamp});
        @saved.append(@matches);
        @rounds.push(@matches.map(*.count).sort.Array);
        for @matches -> $match {
            is $match<items>.elems, $match.count, "{$case.key}: captures agree with isolated counter";
        }
    }
    is-deeply @rounds, $case.value, "{$case.key}: select within each event";
    is-deeply @saved.map(*.count).sort.Array, $case.value.map(*.list).flat.sort.Array,
        "{$case.key}: emitted matches remain immutable";
    is $runner.pending, 3, "{$case.key}: losing starts keep evolving" if $case.key eq any(<star star-min star-every plus plus-min plus-every open-min>);
    is $runner.finish.elems, 0, "{$case.key}: EOF does not emit losers";
}
my $runner=EEL::Runner.new(:patterns[Counts], :rule<star>);
my @matches;
@matches.append($runner.process(%(timestamp=>$_))) for ^5;
is-deeply @matches.map({ .<items>.map(*.data<timestamp>).Array }).Array,
    [[0],[0,1],[0,1,2],[1,2,3],[2,3,4]], 'expired winner is replaced by equal-sized successor';
is $runner.pending, 3, 'all three live start continuations remain in storage';
my $partitioned=EEL::Runner.new(:patterns[Counts], :rule<partitioned>);
is-deeply ( ^4 ).map(-> $timestamp {
    $partitioned.process({:$timestamp, key=>($timestamp % 2 ?? 'b' !! 'a')}).map(*.count).Array
}).Array, [[1],[1],[2],[2]], 'partitions evolve independently';
event OnlyEmpty { pattern TOP { <empty> }; pattern empty { } }
throws-like { EEL::Runner.new(:patterns[OnlyEmpty]) }, X::AdHoc,
    message => /'must consume'/, 'nullable subpattern alone is not a consuming entry';
event ZeroOnly { pattern TOP { <.event> ** 0 } }
throws-like { EEL::Runner.new(:patterns[ZeroOnly]) }, X::AdHoc,
    message => /'must consume'/, 'zero-only repeat cannot consume an input';
done-testing;
