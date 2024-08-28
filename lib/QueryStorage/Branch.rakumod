use QueryStorage::List;
use QueryStorage::BTrees;
use QueryStorage::Eq;

unit class QueryStorage::Branch;
has QueryStorage::List %.lists;
has @.types = QueryStorage::Eq, QueryStorage::Gt, QueryStorage::Lt, QueryStorage::Ge, QueryStorage::Le;
has %!map   = |@!types.map: { .op => $_ }

method map($op) { %!map{$op}.new }

proto method add(|c) {note c; {*}}
multi method add(::?CLASS:U: Pair $test, $value) {
    note 1;
    my ::?CLASS $obj .= new;
    $obj.add: $test, $value;
    $obj
}
multi method add(::?CLASS:D: (:$key, :$value), $value2) {
    note 2;
    (%!lists{$key} //= self.map: $key) .= add: $value, $value2;
    self
}
method search(|c) {
    gather for %!lists.values {
        .take for .search: |c
    }
}
