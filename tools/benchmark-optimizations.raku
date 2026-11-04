#!/usr/bin/env raku
use lib 'lib';
use EEL;
use Event;
use EEL::Runner;
use EEL::MemoryStorage;
use EEL::Query;
use EEL::Input;
use EEL::InputQueue;
use JSON::Fast;

event Starter { pattern TOP { <.event(:type<hit>)> } }
event Forks { pattern TOP { <.event(:type<A>)> [<b=.event(:type<B>)> | <c=.event(:type<B>)> | <e=.event(:type<B>)> | <f=.event(:type<B>)> | <g=.event(:type<B>)> | <h=.event(:type<B>)> | <i=.event(:type<B>)> | <j=.event(:type<B>)>] <.event(:type<D>)> } }
event Last { pattern TOP { :partition{ .<session> } :!ignore-unexpected <.event(:type<S>)> <a=.event(:type<A>)>+! } }
sub median(@values) { @values.sort[@values.elems div 2] }
sub measure(&code,Int $repeats) {
    code(); # warmup; timed repetitions use fresh mutable fixtures when needed
    my @times;
    for ^$repeats { my $start=now; code(); @times.push((now - $start).Num) }
    median(@times)
}
sub MAIN(Int :$size=1000,Int :$repeats=7,Int :$rounds=10,Str :$only='all') {
    die 'unknown scenario' unless $only eq any(<all anchor interval overlap opaque buffer starters forks retained>);
    die 'positive size, repeats and rounds required' unless $size > 0 && $repeats > 0 && $rounds > 0;
    my @results;
    sub report($name,$optimized,$reference,%work={}) {
        my %result=:$name,:$size,:$optimized,:$reference,speedup=>$reference/max(1e-9,$optimized),work=>%work;
        @results.push(%result);
        say to-json(%result,:!pretty); $*OUT.flush;
    }
    for <anchor interval overlap opaque>.grep({ $only eq 'all' || $only eq $_ }) -> $scenario {
        note "Measuring $scenario ($size)";
        my $storage=EEL::MemoryStorage.new;
        for ^$size -> $id {
            my %conditions=do given $scenario {
                when 'anchor' { %(type=>'response',id=>$id) }
                when 'interval' { %(value=>{'>='=>$id*10,'<='=>$id*10+1}) }
                when 'overlap' { %(value=>{'>='=>0,'<='=>$size*10}) }
                default { %(value=>-> $v { $v >= 0 }) }
            };
            $storage.register(EEL::Query.new(:%conditions),$id);
        }
        my $view=snapshot({type=>'response',id=>$size div 2,value=>($size div 2)*10,timestamp=>0});
        my $optimized=measure({ $storage.search($view) for ^$rounds },$repeats);
        my %work=$storage.stats;
        $storage.reference;
        my $reference=measure({ $storage.search($view) for ^$rounds },$repeats);
        report($scenario,$optimized,$reference,%work);
        $storage.clear;
    }
    return if $only eq any(<anchor interval overlap opaque>);
    if $only eq any(<all buffer>) {
    note "Measuring buffer ($size)";
    my @input=(^$size).map({ [($_*7919)%max(1,$size div 2),$_,$_] }).Array;
    sub heap-buffer {
        my $heap=EEL::InputQueue.new;
        # Hold the window open: every arrival would otherwise re-sort it.
        $heap.push($_) for @input;
        $heap.shift while $heap;
    }
    sub sorted-buffer {
        my @queue;
        for @input -> $item {
            @queue.push($item);
            @queue=@queue.sort({$^a[0] <=> $^b[0] || $^a[1] <=> $^b[1]});
        }
        @queue.shift while @queue;
    }
    report('buffer',measure(&heap-buffer,$repeats),measure(&sorted-buffer,$repeats));
    }
    return if $only eq 'buffer';
    if $only eq any(<all starters>) {
    note "Measuring starters ($size)";
    my @patterns;
    for ^$size -> $id {
        my $type=Metamodel::ClassHOW.new_type(:name("BenchStarter$id"));
        $type.^add_parent(Starter); @patterns.push($type.^compose);
    }
    # Separate lazy initialization from the steady-state starter lookup.
    my $fast=EEL::Runner.new(:patterns(@patterns)); my $slow=EEL::Runner.new(:patterns(@patterns));
    $slow.EEL-linear-search;
    $fast.process(%(type=>'noise',timestamp=>0)); $slow.process(%(type=>'noise',timestamp=>0));
    report('starters',measure({$fast.process(%(type=>'noise',timestamp=>0)) for ^$rounds},$repeats),
        measure({$slow.process(%(type=>'noise',timestamp=>0)) for ^$rounds},$repeats),
        {optimized=>$fast.EEL-work,reference=>$slow.EEL-work});
    $fast.close; $slow.close;
    }
    return if $only eq 'starters';
    sub forks(Bool $reference) {
        my $r=EEL::Runner.new(:patterns[Forks]); $r.EEL-reference-forks($reference);
        for ^$rounds { $r.process(%(type=>$_,timestamp=>0)) for <A B D> }
        $r.finish; $r.EEL-work
    }
    if $only eq any(<all forks>) {
    note "Measuring forks ($size)";
    report('forks',measure({forks(False)},$repeats),measure({forks(True)},$repeats),
        {optimized=>forks(False),reference=>forks(True)});
    }
    return if $only eq 'forks';
    sub retained(Bool $reference) {
        my $r=EEL::Runner.new(:patterns[Last]);
        for ^$size -> $session { $r.process(%(type=>$_,:$session,timestamp=>0)) for <S A> }
        $r.EEL-reference-retained($reference);
        $r
    }
    note "Measuring retained ($size)";
    my $rf=retained(False); my $rs=retained(True);
    my $before=$rf.EEL-work<retained>;
    my $reference-before=$rs.EEL-work<retained>;
    my $optimized=measure({$rf.process(%(type=>'noise',session=>$size+1,timestamp=>1)) for ^$rounds},$repeats);
    my $reference=measure({$rs.process(%(type=>'noise',session=>$size+1,timestamp=>1)) for ^$rounds},$repeats);
    report('retained', $optimized,$reference,{optimized=>$rf.EEL-work<retained>-$before,reference=>$rs.EEL-work<retained>-$reference-before});
    $rf.close; $rs.close;
}
