use QueryStorage::BTree;
use Test;

my $btree = class :: is QueryStorage::BTree {method func($a, $b) {$a > $b}}.new;

is-deeply $btree.search(42), ();
$btree.add: 0, "ok1";
is-deeply $btree.search(42), ("ok1",);
$btree.add: 0, "ok2";
is-deeply $btree.search(42), ("ok1", "ok2");
$btree.add: 10, "ok3";
is-deeply $btree.search(42), ("ok1", "ok2", "ok3");
$btree.add: 50, "ok4";
is-deeply $btree.search(42), ("ok1", "ok2", "ok3");

done-testing;
