use lib 'lib';
use Test;
use EEL;
use EEL::Runner;

event Cuts {
    pattern unordered-control { <A> & <A> }
    pattern unordered-cut { [ <A> <commit> ] & <A> }
    pattern repeated-starts { :!ignore-unexpected [ <A> <commit> <B> ] | [ <A> <C> ] }
    pattern rule-end { <A> ::: $ }
    pattern shuffle-control { [ <A> <B> ] &&& [ <A> <C> ] }
    pattern shuffle-match { [ <A> <commit> <B> ] &&& [ <A> <C> ] }
    pattern shuffle-local { [ [ <A> :: <B> ] | [ <A> <D> ] ] &&& [ <A> <C> ] }
    pattern held { [ <A> <B> <commit> <C> ] || [ <A> <D> ] }
    pattern lower-cut { [ <A> <B> ] || [ <A> <D> ::> ] }
    pattern bad-type { <A> <commit(42)> }
    pattern early-fallback { [ ::> <B> ] || <A> }
    pattern plain { [ <A> :: <B> ] | [ <A> <C> ] }
    pattern ordered { [ <A> ::> <B> ] || [ <A> <C> ] }
    pattern wrong-plain { [ <A> :: <B> ] || [ <A> <C> ] }
    pattern wrong-ordered { [ <A> ::> <B> ] | [ <A> <C> ] }
    pattern plain-call { [ <prefix> <B> ] | [ <A> <C> ] }
    pattern prefix { <A> :: }
    pattern ordered-call { [ <ordered-prefix> <B> ] || [ <A> <C> ] }
    pattern ordered-prefix { <A> ::> }
    pattern rule-cut { [ <inner-rule> <C> ] || [ <A> <D> ] }
    pattern inner-rule { [ <A> ::: <B> ] | [ <A> <D> ] }
    pattern match-cut { [ <inner-match> <C> ] || [ <A> <D> ] }
    pattern inner-match { [ <A> <commit> <B> ] | [ <A> <D> ] }
    pattern named-cut { [ <named-inner> <C> ] || [ <A> <D> ] }
    pattern named-inner { [ <A> <commit('named-cut')> <B> ] | [ <A> <D> ] }
    pattern named-local { [ <named-local-inner> <C> ] || [ <A> <D> ] }
    pattern named-local-inner { [ <A> <commit: 'named-local-inner'> <B> ] | [ <A> <D> ] }
    pattern inner-no-cut { [ <A> <B> ] | [ <A> <D> ] }
    pattern no-rule-cut { [ <inner-no-cut> <C> ] || [ <A> <D> ] }
    pattern completed-choice { :!ignore-unexpected [ <A> | <A> <B> ] ::: <C> }
    pattern repeat-cut { ^ :!ignore-unexpected <A>+! ::: <B> }
    pattern repeat-control { ^ :!ignore-unexpected <A>+! <B> }
    pattern after-cut { <A> ::: [ <B> | <C> ] }
    pattern nested-plain { [ <A> [ <B> :: <C> | <B> <D> ] ] | [ <A> <B> <E> ] }
    pattern cross-kind { [ <A> [ <B> :: <C> || <B> <D> ] ] | [ <A> <B> <E> ] }
    pattern cross-ordered { [ <A> [ <B> ::> <C> | <B> <D> ] ] || [ <A> <B> <E> ] }
    pattern all-noop { :: ::> ::: <commit> <A> }
    pattern bad-name { <A> <commit('missing')> }
    pattern bad-args { <A> <commit('one', 'two')> }
    pattern partitioned {
        :partition{ .<key> }
        [ <A> <commit> <B> ] | [ <A> <C> ]
    }
    pattern timed { :2s [ <A> ::: <B> ] | [ <A> <C> ] }
    pattern at-end { [ <A> <commit> $ ] | [ <A> <B> ] }
    pattern A { <.event(:type<A>)> }
    pattern B { <.event(:type<B>)> }
    pattern C { <.event(:type<C>)> }
    pattern D { <.event(:type<D>)> }
    pattern E { <.event(:type<E>)> }
}
sub runner($rule) { EEL::Runner.new(:patterns[Cuts],:$rule) }
sub feed($rule,@types) {
    my $r=runner($rule); my @out;
    for @types.kv -> $timestamp,$type { @out.append($r.process(%(:$type,:$timestamp))) }
    @out.append($r.finish); @out.List
}
is feed('plain',<A C>).elems,0,'double colon cuts independent alternative';
is feed('plain',<A B>).elems,1,'double colon permits chosen branch';
is feed('ordered',<A C>).elems,0,'temporal cut drops ordered fallback';
is feed('ordered',<A B>).elems,1,'temporal cut permits chosen branch';
is feed('wrong-plain',<A C>).elems,1,'double colon does nothing without active independent alternative';
is feed('wrong-ordered',<A C>).elems,1,'temporal cut does nothing without active ordered alternative';
is feed('plain-call',<A C>).elems,0,'double colon finds dynamic caller alternative';
is feed('ordered-call',<A C>).elems,0,'temporal cut finds dynamic caller alternative';
is feed('rule-cut',<A D>).elems,1,'triple colon preserves caller fallback';
is feed('no-rule-cut',<A D C>).elems,1,'uncut child can choose its second branch';
is feed('rule-cut',<A D C>).elems,1,'caller fallback remains after child cut failure';
is feed('match-cut',<A D>).elems,0,'match cut drops caller fallback';
is feed('match-cut',<A B C>).elems,1,'match cut keeps chosen child and caller suffix';
is feed('named-cut',<A D>).elems,0,'named match cut can target caller frame';
is feed('named-local',<A D>).elems,1,'named local cut preserves caller choices';
is feed('completed-choice',<A B C>).elems,0,'triple colon removes choices even after alternative scope ended';
is feed('completed-choice',<A C>).elems,1,'completed-choice cut keeps current path';
is feed('repeat-control',<A A B>).elems,1,'uncut repeat can grow to consume second item';
is feed('repeat-cut',<A A B>).elems,0,'triple colon commits repeat exit and removes growth path';
is feed('repeat-cut',<A B>).elems,1,'repeat exit can complete after cut';
is feed('after-cut',<A B C>).elems,2,'choices created after cut remain available';
is feed('nested-plain',<A B E>).elems,1,'inner independent cut leaves outer independent choice';
is feed('cross-kind',<A B E>).elems,0,'double colon skips inner ordered scope and cuts outer independent scope';
is feed('cross-ordered',<A B E>).elems,0,'temporal cut skips inner independent scope and cuts outer ordered scope';
is feed('all-noop',['A']).elems,1,'cuts without saved choice points succeed before consumption';
throws-like { feed('bad-name',['A']) },Exception,message=>/'no active pattern'/,'unknown named commit reports error';
throws-like { feed('bad-args',['A']) },Exception,message=>/'at most one'/,'extra commit arguments rejected';
my $r=runner('partitioned'); my @partitioned;
for [{type=>'A',key=>1},{type=>'A',key=>2},{type=>'C',key=>1},{type=>'B',key=>2}].kv -> $timestamp,%event {
    @partitioned.append($r.process(%(|%event,:$timestamp)));
}
@partitioned.append($r.finish);
is @partitioned.elems,1,'match cut is independent per candidate and partition';
is @partitioned[0].data<key>,2,'other partition survives cut failure';
is feed('timed',<A C>).elems,0,'triple colon cuts paths inside window';
is feed('at-end',['A']).elems,1,'match cut works with EOF wait';
is feed('at-end',<A B>).elems,0,'failure after match cut cannot revive fallback';
is feed('shuffle-control',<A A B C>).elems,2,'ambiguous shuffle keeps both assignments without cut';
is feed('shuffle-match',<A A B C>).elems,1,'match cut discards alternative shuffle assignment';
is feed('shuffle-local',<A A B C>).elems,2,'local alternative cut preserves independent shuffle assignments';
is feed('held',<A D B C>).elems,1,'match cut can discard already held fallback';
is feed('held',<A D B E>).elems,0,'held fallback stays discarded after chosen branch fails';
is feed('lower-cut',<A D>).elems,1,'first executed cut can commit a lower-priority branch';
is feed('early-fallback',['A']).elems,0,'cut before consumption prunes sibling starter';
throws-like { feed('bad-type',['A']) },Exception,message=>/'defined Str'/,'commit validates target type';
is feed('unordered-control',<A A>).elems,2,'unordered operands keep both order choices';
is feed('unordered-cut',<A A>).elems,1,'match cut commits unordered operand order';
is feed('repeated-starts',<A C A B>).elems,1,'later start gets fresh decision IDs after committed path fails';
is feed('rule-end',['A']).elems,1,'triple colon also works before EOF without alternative';
my $cancel=runner('at-end'); $cancel.process({type=>'A'}); $cancel.close;
is $cancel.finish.elems,0,'cancellation does not publish a committed EOF wait';
done-testing;
