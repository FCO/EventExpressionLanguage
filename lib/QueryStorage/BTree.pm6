use QueryStorage::List;
use QueryStorage::BTree::Node;
unit class QueryStorage::BTree does QueryStorage::List;

method op { !!! }
multi method func($, $ --> False) {!!!}
multi method func(Nil, $ --> False) {}
multi method func($, Nil --> False) {}

has QueryStorage::BTree::Node $.btree;
multi method add($test, \value) {
    with $!btree {
        $!btree.add: $test, value;
    } else {
        $!btree .= new: :tree(self), :value($test), :stored(value)
    }
    self
}
method search($val) {
    gather { .search: $val with $!btree }
}