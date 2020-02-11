use QueryStorage;
use Test;

my QueryStorage $storage .= new;

is-deeply $storage.search({ :attr1(42) }), ();
$storage.add: { :attr1("==" => 42) }, "ok1";
is-deeply $storage.search({ :attr1(42) }), ("ok1",);
$storage.add: { :attr1("==" => 13) }, "ok2";
is-deeply $storage.search({ :attr1(42) }), ("ok1",);
is-deeply $storage.search({ :attr1(13) }), ("ok2",);
$storage.add: { :attr1(">" => 13) }, "ok3";
is-deeply $storage.search({ :attr1(42) }).sort, ("ok1", "ok3");
is-deeply $storage.search({ :attr1(13) }), ("ok2",);
is-deeply $storage.search({ :attr1(14) }), ("ok3",);
$storage.add: { :attr1(">" => 40) }, "ok4";
is-deeply $storage.search({ :attr1(42) }).sort, ("ok1", "ok3", "ok4");
is-deeply $storage.search({ :attr1(13) }), ("ok2",);
is-deeply $storage.search({ :attr1(14) }), ("ok3",);

done-testing;
