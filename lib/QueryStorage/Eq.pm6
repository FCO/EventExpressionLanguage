use QueryStorage::List;
unit class QueryStorage::Eq does QueryStorage::List;

has %.eq;
method op { "==" }
multi method add($test, \value) {
    %!eq{ $test } = value;
    self
}
multi method search($val where .defined) {
    gather { .take with %!eq{$val} }
}

multi method search($) { Empty }