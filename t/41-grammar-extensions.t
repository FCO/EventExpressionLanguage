use lib 'lib';
use Test;
use EEL;
use EEL::Runner;

event Extensions {
    has $.mark;
    pattern auxiliary-cut { <.event(:type<A>)> <?before [ <.event(:type<B>)> ::> <.event(:type<C>)> ] || [ <.event(:type<B>)> <.event(:type<D>)> ]> <.event(:type<B>)> }
    pattern separator-only { [] ** 2 % <.event(:type<S>)> }
    pattern separator-recursion { [] ** 2 % <separator-recursion> | <.event(:type<A>)> }
    pattern early-shuffle-cut { [ [ ::> <.event(:type<A>)> ] || <.event(:type<B>)> ] &&& <.event(:type<X>)> }
    pattern shuffled-start { [ ^^ <.event(:type<A>)> ] &&& <.event(:type<B>)> }
    pattern shuffled-cut { [ [ <.event(:type<A>)> ::> <.event(:type<B>)> ] || [ <.event(:type<A>)> <.event(:type<C>)> ] ] &&& <.event(:type<X>)> }
    pattern capture-quantifier { $<batch> = <item=.event(:type<A>)>+ % <separator=.event(:type<S>)> <.event(:type<Z>)> }
    pattern throwing { <.event(:type<A>)> <?{ die 'guard failed' }> }
    pattern action-false { <.event(:type<A>)> { False } }
    pattern zero-anchored { ^^ :!ignore-unexpected <.event(:type<A>)>* %% <.event(:type<S>)> <.event(:type<Z>)> }
    pattern positive { <a=.event(:type<A>)> <?{ $<a>.value > 2 }> }
    pattern negative { <a=.event(:type<A>)> <!{ $<a>.value > 2 }> }
    pattern local-test { :my $n = 2; <.event(:type<A>)> <?{ $n == 2 }> }
    pattern separated { :!ignore-unexpected <item=.event(:type<A>)>+ % <sep=.event(:type<S>)> <.event(:type<Z>)> }
    pattern trailing { :!ignore-unexpected <item=.event(:type<A>)>+ %% <sep=.event(:type<S>)> <.event(:type<Z>)> }
    pattern bounded { :!ignore-unexpected <item=.event(:type<A>)> ** 2..3 % <.event(:type<S>)> <.event(:type<Z>)> }
    pattern named { $<exchange> = [ <a=.event(:type<A>)> <b=.event(:type<B>)> ] }
    pattern names { [ $<pair> = [ <a=.event(:type<A>)> <b=.event(:type<B>)> ] ]+ <.event(:type<Z>)> }
    pattern whole { ^^ :!ignore-unexpected <.event(:type<A>)> <.event(:type<B>)> $$ }
    pattern ending { <.event(:type<A>)> $$ { $!mark = 'end' } }
    pattern start { ^^ <.event(:type<A>)> }
    pattern middle-start { <.event(:type<A>)> ^^ <.event(:type<B>)> }
    pattern cut {
        [ <.event(:type<A>)> ::> <.event(:type<B>)> ]
        || [ <.event(:type<A>)> <.event(:type<C>)> ]
    }
    pattern uncut {
        [ <.event(:type<A>)> <.event(:type<B>)> ]
        || [ <.event(:type<A>)> <.event(:type<C>)> ]
    }
    pattern captured-repeat { $<batch> = [ <item=.event(:type<A>)>+ % <sep=.event(:type<S>)> ] <.event(:type<Z>)> }
    pattern zero { :!ignore-unexpected <.event(:type<A>)>* %% <.event(:type<S>)> <.event(:type<Z>)> }
    pattern partition-end { :partition{ .<key> } <.event(:type<A>)> $$ }
    pattern window-end { :2s <.event(:type<A>)> $$ }
    pattern end-absence { <.event(:type<A>)> <absence=!B> <?{ $<absence>.reason eq 'eof' }> }
    pattern B { <.event(:type<B>)> }
    pattern named-fork { $<pair> = [ <a=.event(:type<A>)> [ <b=.event(:type<B>)> | <c=.event(:type<C>)> ] ] }
    pattern isolated-cut {
        [ <.event(:type<A>)> [ [ <.event(:type<B>)> ::> <.event(:type<C>)> ] || <.event(:type<D>)> ] ]
        || [ <.event(:type<A>)> <.event(:type<B>)> <.event(:type<E>)> ]
    }
    pattern partition-cut {
        :partition{ .<key> }
        [ <.event(:type<A>)> ::> <.event(:type<B>)> ] || [ <.event(:type<A>)> <.event(:type<C>)> ]
    }
    pattern invalid-cut { <.event(:type<A>)> ::> }
    pattern early-cut { [ ::> <.event(:type<A>)> ] || <.event(:type<B>)> }
    pattern cut-suffix { [ <.event(:type<A>)> ::> ] || <.event(:type<B>)> <.event(:type<C>)> }
    pattern assertion-end { <.event(:type<A>)> <?before <.event(:type<B>)> $> <.event(:type<B>)> }
    pattern past-end { <.event(:type<A>)> <?after <.event(:type<A>)> $> }

}
sub runner($rule) { EEL::Runner.new(:patterns[Extensions],:$rule) }
sub feed($rule,@types) {
    my $r=runner($rule); my @out;
    for @types.kv -> $timestamp,$type { @out.append($r.process({:$type,:$timestamp,value=>3})) }
    @out.append($r.finish); @out.List
}
is feed('positive',['A']).elems,1,'positive code assertion accepts true';
is feed('negative',['A']).elems,0,'negative code assertion rejects true';
my $negative=runner('negative');
is $negative.process({type=>'A',value=>1}).elems,1,'negative code assertion accepts false';
is feed('local-test',['A']).elems,1,'assertion sees lexical state';
is feed('separated',<A S A Z>).elems,1,'separator between items';
is feed('separated',<A Z>).elems,1,'one item needs no separator';
is feed('separated',<A A Z>).elems,1,'strict gap kills first start but second remains';
is feed('separated',<A S Z>).elems,0,'percent forbids trailing separator';
is feed('trailing',<A S Z>).elems,1,'double percent allows trailing separator';
is feed('trailing',<A S A S Z>).elems,1,'double percent allows repeated items and trailing separator';
is feed('trailing',<A Z>).elems,1,'trailing separator is optional';
is feed('bounded',<A S A Z>).elems,1,'bounded separated repeat accepts lower bound';
is feed('bounded',<A Z>).elems,0,'bounded separated repeat enforces minimum';
my @named=feed('named',<A B>);
is @named.elems,1,'named expression recognized';
is @named[0]<exchange><a>.type,'A','named capture retains nested captures';
is @named[0]<exchange><b>.type,'B','named capture retains final capture';
my @names=feed('names',<A B A B Z>);
is @names.elems,1,'repeated named capture completes';
is @names[0]<pair>.elems,2,'named captures accumulate under repetition';
is @names[0]<pair>[1]<a>.type,'A','each repeated group retains its captures';
is feed('whole',<A B>).elems,1,'anchors match entire finite input';
is feed('whole',<X A B>).elems,0,'start anchor rejects preceding input';
is feed('whole',<A B X>).elems,0,'end anchor rejects following input';
is feed('start',<X A>).elems,0,'cached starter cannot move start anchor';
is feed('middle-start',<A B>).elems,0,'start anchor fails after consumption';
my $end=runner('ending');
is $end.process({type=>'A',timestamp=>0}).elems,0,'end anchor waits for EOF';
my @end=$end.finish;
is @end.elems,1,'EOF releases end anchor';
is @end[0].mark,'end','trailing action runs at EOF';
my $cancel=runner('ending'); $cancel.process({type=>'A'}); $cancel.close;
is $cancel.finish.elems,0,'cancellation does not confirm end anchor';
is feed('uncut',<A C>).elems,1,'ordered fallback wins without cut';
is feed('cut',<A C>).elems,0,'cut discards fallback even if committed branch fails';
is feed('cut',<A B>).elems,1,'committed branch can succeed';
my @batch=feed('captured-repeat',<A S A S A Z>);
is @batch[0]<batch><item>.elems,3,'named group retains repeated item array';
is @batch[0]<batch><sep>.elems,2,'separators accumulate as repeated captures';
is @batch[0]<batch><sep>[0].type,'S','separator captures retain data';
is feed('zero',['Z']).elems,1,'zero items permit no separator';
is feed('zero',<S Z>).elems,1,'unanchored zero repeat may start at Z';
my @forked=feed('named-fork',<A C>);
is @forked[0]<pair><c>.type,'C','fork remaps pending named capture marker';
my $partition=runner('partition-end');
$partition.process({type=>'A',key=>1,timestamp=>0});
$partition.process({type=>'X',key=>2,timestamp=>1});
is $partition.finish.elems,1,'other partition does not invalidate end wait';
my $window=runner('window-end');
$window.process({type=>'A',timestamp=>0});
is $window.process({type=>'X',timestamp=>2}).elems,0,'window expiration does not confirm end anchor';
is $window.finish.elems,0,'expired end wait cannot revive at EOF';
is feed('end-absence',['A']).elems,1,'code assertion sees confirmed terminal absence';
is feed('end-absence',<A B>).elems,0,'terminal negative witness still rejects';
is feed('isolated-cut',<A B E>).elems,1,'inner commit leaves outer ordered fallback alive';
is feed('isolated-cut',<A B C>).elems,1,'nested committed branch succeeds';
my $partcut=runner('partition-cut'); my @partcut;
for [{type=>'A',key=>1},{type=>'A',key=>2},{type=>'C',key=>1},{type=>'B',key=>2}].kv -> $timestamp,%event {
    @partcut.append($partcut.process(%(|%event,:$timestamp)));
}
@partcut.append($partcut.finish);
is @partcut.elems,1,'commits have independent choice IDs across starts and partitions';
is @partcut[0].data<key>,2,'other partition can finish committed branch';
is feed('invalid-cut',['A']).elems,1,'ordered cut outside active choice is a no-op';
is feed('early-cut',['A']).elems,1,'ordered cut is allowed before first consumption';
is feed('assertion-end',<A B>).elems,1,'positive assertion can wait for real EOF and replay suffix';
is feed('assertion-end',<A B X>).elems,0,'positive assertion end anchor rejects subsequent input';
is feed('past-end',['A']).elems,0,'lookbehind boundary is not subscription EOF';
is feed('shuffled-start',<A B>).elems,1,'start anchor works within shuffle branch';
is feed('shuffled-start',<B A>).elems,0,'shuffle cannot delay start-anchored branch';
is feed('shuffled-start',<X A B>).elems,0,'shuffle cannot move subscription start';
is feed('shuffled-cut',<A X B>).elems,1,'shuffle remaps active choice scope for cut';
is feed('shuffled-cut',<A X C>).elems,0,'cut in shuffle rejects fallback';
my @capture-quantifier=feed('capture-quantifier',<A S A Z>);
is @capture-quantifier[0]<batch><item>.elems,2,'named assignment includes entire quantified expression';
is @capture-quantifier[0]<batch><separator>.elems,1,'named assignment includes separator captures';
is feed('zero-anchored',<S Z>).elems,0,'zero items cannot consume a trailing separator';
is feed('action-false',['A']).elems,1,'ordinary false action does not reject path';
throws-like { feed('throwing',['A']) },Exception,message=>/'guard failed'/,'assertion exceptions propagate';
is feed('separator-only',['S']).elems,1,'finite nullable items may consume through separators';
throws-like { runner('separator-recursion') },Exception,message=>/'without consuming'/,'validation detects recursion through nullable item and separator';
is feed('early-shuffle-cut',<A X>).elems,1,'ordered cut before consumption also works in shuffle';
is feed('auxiliary-cut',<A B C>).elems,1,'cut works inside isolated positive recognizer';
is feed('auxiliary-cut',<A B D>).elems,0,'auxiliary recognizer cannot revive committed-away fallback';
done-testing;
