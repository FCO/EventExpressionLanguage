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
$storage.add: { :attr1(">" => 40), :attr2("<" => 10) }, "ok5";
is-deeply $storage.search({ :attr1(50), :attr2(5) }).sort, ("ok3", "ok4", "ok5");
$storage.add: { :attr1(">" => 40), :attr2("<" => 10), :attr3("==" => "bla") }, "ok6";
is-deeply $storage.search({ :attr1(50), :attr2(5), :attr3<bla> }).sort, ("ok3", "ok4", "ok5", "ok6");
$storage.add: { :attr1(">" => 40), :attr2("<" => 10), :attr3("==" => "ble") }, "ok7";
is-deeply $storage.search({ :attr1(50), :attr2(5), :attr3<ble> }).sort, ("ok3", "ok4", "ok5", "ok7");
is-deeply $storage.search({ :attr1(50), :attr2(5), :attr3<bla> }).sort, ("ok3", "ok4", "ok5", "ok6");
is-deeply $storage.search({ :attr1(50), :attr2(5) }).sort, ("ok3", "ok4", "ok5");
$storage.add: { :attr1(">" => 40), :attr2("<" => 10), :attr4(">=" => 15) }, "ok8";
is-deeply $storage.search({ :attr1(50), :attr2(5), :attr3<ble>, :attr4(15) }).sort, ("ok3", "ok4", "ok5", "ok7", "ok8");
is-deeply $storage.search({ :attr1(50), :attr2(5), :attr3<ble> }).sort, ("ok3", "ok4", "ok5", "ok7");
is-deeply $storage.search({ :attr1(50), :attr2(5), :attr3<bla> }).sort, ("ok3", "ok4", "ok5", "ok6");
is-deeply $storage.search({ :attr1(50), :attr2(5) }).sort, ("ok3", "ok4", "ok5");
is-deeply $storage.search({ :attr4(15) }).sort, ();

done-testing;
