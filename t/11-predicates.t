use lib 'lib';
use Test;
use EEL;
use EEL::Query;

my $whatever = EEL::Query.new(:conditions{value => (* > 40)});
my $block = EEL::Query.new(:conditions{value => { $_ > 40 }});
for $whatever, $block -> $query {
    ok $query.matches({value => 41}), 'predicate accepts the field value';
    ok !$query.matches({value => 40}), 'predicate rejects boundary';
    ok !$query.matches({}), 'missing field does not match';
}
my $calls = 0;
my $present = EEL::Query.new(:conditions{value => -> $value { $calls++; !$value.defined }});
ok !$present.matches({}), 'missing field does not invoke predicate';
is $calls, 0, 'predicate not run for absence';
ok $present.matches({value => Any}), 'present undefined field is passed to predicate';
is $calls, 1, 'predicate called once for a present field';
ok EEL::Query.new(:conditions{value => { 7 }}).matches({value => 1}), 'truthy return accepts';
ok !EEL::Query.new(:conditions{value => { 0 }}).matches({value => 1}), 'false return rejects';
my &nested-predicate = * > 40;
ok EEL::Query.new(:conditions(%('nested.value' => &nested-predicate))).matches(%(nested => %(value => 41))),
    'predicate supports dotted fields';
throws-like { EEL::Query.new(:conditions{value => { die 'bad predicate' }}).matches({value => 1}) },
    X::AdHoc, message => /'bad predicate'/, 'predicate errors propagate';

event MapForm { pattern TOP { <.event(:value({'>' => 40}))> } }
event WhateverForm { pattern TOP { <.event(:value(* > 40))> } }
event BlockForm { pattern TOP { <.event(:value{$_ > 40})> } }
class Reading { has $.value }
for {value => 41}, Reading.new(:value(41)) -> $input {
    my @out;
    ($input,).Supply.match(MapForm, WhateverForm, BlockForm).tap(-> $event { @out.push($event.^name) });
    is-deeply @out.List, ('MapForm','WhateverForm','BlockForm'), 'all three syntaxes recognize hashes and objects';
}

event Threshold {
    has $.limit;
    pattern TOP {
        <setting=.event(:type<setting>)>
        :my $limit = $<setting>.data<limit>;
        <reading=.event(:type<reading>, :value(* > $limit))>
        { $!limit = $limit }
    }
}
my @limits;
(
    {type => 'setting', limit => 40}, {type => 'setting', limit => 50},
    {type => 'reading', value => 45}, {type => 'reading', value => 55},
).Supply.match(Threshold).tap(-> $event { @limits.push($event.limit) });
is-deeply @limits.List, (40,50), 'predicates retain independent capture-dependent thresholds';

event Forked {
    has $.value;
    pattern TOP {
        <.event(:type<start>)>
        :my $limit = 40;
        [ { $limit++ } <.event(:value(* > $limit))> | { $limit += 10 } <.event(:value{$_ > $limit})> ]
        { $!value = $limit }
    }
}
my @forks;
({type => 'start'}, {value => 45}, {value => 55}).Supply.match(Forked)
    .tap(-> $event { @forks.push($event.value) });
is-deeply @forks.List, (41,50), 'forks bind predicate closures to their own local state';

my $evaluations = 0;
event Counted { pattern TOP { <.event(:value{ $evaluations++; $_ > 40 })> } }
my @reemit;
({value => 41}, {value => 1}, {other => 2}).Supply.match(Counted, :reemit)
    .tap(-> $event { @reemit.push($event) });
is $evaluations, 2, 'reemit does not evaluate predicates again';
is @reemit.elems, 4, 'predicate only controls derived output';
my @errors;
event BrokenPredicate { pattern TOP { <.event(:value{ die 'predicate failed' })> } }
({value => 1},).Supply.match(BrokenPredicate).tap(quit => -> $error { @errors.push($error.message) });
like @errors[0], /'predicate failed'/, 'Supply quits with the original predicate error';
done-testing;
