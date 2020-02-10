use QueryStorage::List;
unit class QueryStorage::Eq does QueryStorage::List;

has %.eq;
method op { "==" }
multi method add($test, \value) {
    %!eq{ $test } = value;
    self
}
method search($val) {
    gather { .take with %!eq{$val} }
}