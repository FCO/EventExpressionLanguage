use QueryStorage::BTree;
use Test;

my $btree = class :: is QueryStorage::BTree {method func($a, $b) {$a > $b}}.new;

is-deeply $btree.search(42).sort, ();

$btree.add: 0, "ok1";
is-deeply $btree.search(42).sort, ("ok1",);
is-deeply $btree.search(0) .sort, ();

$btree.add: 0, "ok2";
is-deeply $btree.search(42).sort, ("ok1", "ok2");
is-deeply $btree.search(0) .sort, ();

$btree.add: 10, "ok3";
is-deeply $btree.search(42).sort, ("ok1", "ok2", "ok3");
is-deeply $btree.search(9) .sort, ("ok1", "ok2");
is-deeply $btree.search(0) .sort, ();

$btree.add: 50, "ok4";
is-deeply $btree.search(42).sort, ("ok1", "ok2", "ok3");
is-deeply $btree.search(60).sort, ("ok1", "ok2", "ok3", "ok4");

$btree.del-not-matching(9);
is-deeply $btree.search(60).sort, ("ok1", "ok2");

$btree.add: 49, "ok6";
is-deeply $btree.search(60).sort, ("ok1", "ok2", "ok6");
is-deeply $btree.search(49).sort, ("ok1", "ok2");

$btree.add: 47, "ok7";
is-deeply $btree.search(60).sort, ("ok1", "ok2", "ok6", "ok7");
is-deeply $btree.search(49).sort, ("ok1", "ok2", "ok7");
is-deeply $btree.search(47).sort, ("ok1", "ok2");

$btree.add: 48, "ok8";
is-deeply $btree.search(60).sort, ("ok1", "ok2", "ok6", "ok7", "ok8");
is-deeply $btree.search(49).sort, ("ok1", "ok2", "ok7", "ok8");
is-deeply $btree.search(48).sort, ("ok1", "ok2", "ok7");
is-deeply $btree.search(47).sort, ("ok1", "ok2");

$btree.del-not-matching(-Inf);
is-deeply $btree.search(Inf).sort, ();

(^100).pick(*).map: { $btree.add: $_, "ok{ $_ }" };
is-deeply $btree.search(Inf).sort, (^100).map({ "ok{ $_ }" }).sort;
todo "Make it work every time";
is-deeply $btree.search(50).sort, (^50).map({ "ok{ $_ }" }).sort;

done-testing;
