use QueryStorage::BTree;

class QueryStorage::Gt is QueryStorage::BTree {
    method op { ">" }
    multi method func($ where not .defined, $ --> False) {}
    multi method func($, $ where not .defined --> False) {}
    multi method func(Numeric() $a, Numeric() $b) { $a > $b }
}

class QueryStorage::Lt is QueryStorage::BTree {
    method op { "<" }
    multi method func($ where not .defined, $ --> False) {}
    multi method func($, $ where not .defined --> False) {}
    multi method func(Numeric() $a, Numeric() $b) { $a < $b }
}

class QueryStorage::Ge is QueryStorage::BTree {
    method op { ">=" }
    multi method func($ where not .defined, $ --> False) {}
    multi method func($, $ where not .defined --> False) {}
    multi method func(Numeric() $a, Numeric() $b) { $a >= $b }
}

class QueryStorage::Le is QueryStorage::BTree {
    method op { "<=" }
    multi method func($ where not .defined, $ --> False) {}
    multi method func($, $ where not .defined --> False) {}
    multi method func(Numeric() $a, Numeric() $b) { $a <= $b }
}
