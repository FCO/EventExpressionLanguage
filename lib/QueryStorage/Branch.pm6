use QueryStorage::List;
use QueryStorage::BTries;
use QueryStorage::Eq;

unit class QueryStorage::Branch;
has QueryStorage::List %.lists;
has @.types = QueryStorage::Eq, QueryStorage::Gt, QueryStorage::Lt, QueryStorage::Ge, QueryStorage::Le;
has %!map   = |@!types.map: { .op => $_ }

method map($op) { %!map{$op}.new }

multi method add(::?CLASS:U: |c) {
    my ::?CLASS $obj .= new;
    $obj.add: |c;
    $obj
}
multi method add(::?CLASS:D: (:$key, :$value), \value) {
    (%!lists{$key} //= self.map: $key) .= add: $value, value;
    self
}
method search(|c) {
    gather for %!lists.values {
        .take for .search: |c
    }
}