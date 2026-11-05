use lib 'lib';
use Test;
use EEL::Query;
use EEL::MemoryStorage;

my $storage = EEL::MemoryStorage.new;
my $query = EEL::Query.new(:conditions{type => 'finish', id => 42});
is $storage.elems, 0, 'storage starts empty';
my $first = $storage.register($query, 'first');
my $second = $storage.register($query, 'second');
isnt $first, $second, 'identical predicates get independent IDs';
is-deeply $storage.search({type => 'finish', id => 42})».continuation.List,
    ('first', 'second'), 'all payloads for identical predicates are returned in registration order';
is $storage.search({type => 'finish', id => 9}).elems, 0, 'nonmatching event has no results';
my $snapshot = $storage.snapshot;
ok $storage.remove($first), 'remove an existing subscription';
is-deeply $snapshot».continuation.List, ('first', 'second'), 'snapshot survives removal';
my $third = $storage.register($query, 'third');
is $snapshot.elems, 2, 'snapshot excludes later registrations';
is-deeply $storage.search({type => 'finish', id => 42})».continuation.List,
    ('second', 'third'), 'remove affects only one ID';
ok !$storage.remove($first), 'removing an absent ID returns False';
$storage.clear;
is $storage.elems, 0, 'clear releases all waits';
ok $storage.register($query, 'after-clear') > $third, 'IDs are not recycled';

ok EEL::Query.new.matches({a => 1}), 'empty query accepts any event';
ok !$query.matches({id => 42}), 'missing required field does not match';
ok !$query.matches({type => 'finish', id => '42'}), 'equality preserves types';
ok EEL::Query.new(:conditions{value => Nil}).matches({value => Nil}), 'explicit undefined field can match';
ok !EEL::Query.new(:conditions{value => Nil}).matches({}), 'undefined expected value still requires a field';
for '==' => 7, '!=' => 6, '>' => 6, '>=' => 7, '<' => 8, '<=' => 7 -> $comparison {
    ok EEL::Query.new(:conditions{value => Map.new($comparison)}).matches({value => 7}), "supports {$comparison.key}";
}
ok EEL::Query.new(:conditions{value => {'>=' => 3, '<' => 9}}).matches({value => 7}), 'multiple comparisons are conjoined';
ok !EEL::Query.new(:conditions{value => {'>=' => 3, '<' => 7}}).matches({value => 7}), 'all comparisons must pass';
ok !EEL::Query.new(:conditions{value => {'>' => 3}}).matches({value => '7'}), 'ordering requires numeric values';
my $nested = EEL::Query.new(:conditions{'headers.session' => 'abc'});
ok $nested.matches({headers => {session => 'abc'}}), 'dotted paths traverse hashes';
ok !$nested.matches({headers => 42}), 'non-associative intermediate value does not match';
ok !$nested.matches({headers => {}}), 'missing nested field does not match';
ok $nested.matches({'headers.session' => 'abc'}), 'literal dotted field takes priority';
throws-like { EEL::Query.new(:conditions{value => {'approximately' => 7}}) },
    X::AdHoc, message => /'operator'/, 'unknown query operators are rejected';
done-testing;
