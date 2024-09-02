use QueryStorage::List;
use QueryStorage::BTrees;
use QueryStorage::Eq;

unit class QueryStorage::Branch;
has QueryStorage::List %.lists;
has @.types = QueryStorage::Eq, QueryStorage::Gt, QueryStorage::Lt, QueryStorage::Ge, QueryStorage::Le;
has %!map   = |@!types.map: { .op => $_ }

method map($op) { %!map{$op}.new }

multi method add(::?CLASS:U: %test, $value) {
    my ::?CLASS $obj .= new;
    $obj.add: %test.pairs.head, $value;
    $obj
}
multi method add(::?CLASS:D: (:$key, :$value), $value2) {
    (%!lists{$key} //= self.map: $key) .= add: $value, $value2;
    self
}
method search(|c) {
    gather for %!lists.values {
        .take for .search: |c
    }
}
