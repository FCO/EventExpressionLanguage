#!/usr/bin/env raku
use lib 'lib';
use EEL::MemoryStorage;
use EEL::Query;
use EEL::Input;
use EEL;
use EEL::Runner;

    event Sessions {
        pattern TOP { :1s :partition{ .<session> } <.event(:type<S>)> <.event(:type<E>)> }
    }

sub MAIN(Int :$size=1000, Int :$rounds=50) {
    die 'size and rounds must be positive' unless $size > 0 && $rounds > 0;
    for <equality intervals overlap opaque> -> $scenario {
        my $storage=EEL::MemoryStorage.new;
        my @queries;
        for ^$size -> $id {
            my %conditions=do given $scenario {
                when 'equality' { %(id=>$id) }
                when 'intervals' { %(value=>{'>='=>$id*10,'<='=>$id*10+1}) }
                when 'overlap' { %(value=>{'>='=>0,'<='=>$size*10}) }
                default { %(value=>-> $v { $v >= 0 }) }
            };
            my $query=EEL::Query.new(:%conditions);
            @queries.push($query); $storage.register($query,$id);
        }
        my %event=id=>($size div 2),value=>($size div 2)*10,timestamp=>0;
        my $view=snapshot(%event);
        my $start=now;
        my $candidates=0;
        for ^$rounds { $storage.search($view); $candidates+=$storage.candidates-count }
        my $indexed=now - $start;
        $start=now;
        for ^$rounds { .matches($view) for @queries }
        my $linear=now - $start;
        say "$scenario: indexed={$indexed.round(0.001)}s linear={$linear.round(0.001)}s candidates={$candidates div $rounds}/$size";
        say "  index state: " ~ $storage.stats.raku;
        $storage.clear;
        die 'storage leaked' if $storage.stats<slots> || $storage.stats<query><tokens>;
    }
    my @input=(^$size).map({ %(type=>'S',session=>$_,timestamp=>0) }).Array;
    @input.push(%(type=>'E',session=>$size div 2,timestamp=>1));
    @input.push(%(type=>'noise',timestamp=>2));
    for False,True -> $linear {
        my $runner=EEL::Runner.new(:patterns[Sessions]); $runner.EEL-linear-search($linear);
        my $start=now;
        $runner.process($_) for @input;
        $runner.finish;
        say "partitions/expiry linear=$linear: elapsed={(now - $start).round(0.001)}s candidates={$runner.EEL-candidates}";
    }
}
