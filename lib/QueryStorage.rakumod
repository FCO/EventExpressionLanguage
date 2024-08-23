use QueryStorage::Branch;
unit class QueryStorage;

has QueryStorage::Branch %.branches{Str};

multi method add(%tests, \value) {
#    say "ADD: %tests.gist(), { value.gist }";
    my %branches := %!branches;
    my $value;
    # TODO: Fix, do not override.
    for %tests.pairs.sort.kv -> UInt $i, (:$key, :value($test)) {
        $value = $i + 1 == %tests ?? value !! ::?CLASS.new;
        %branches{$key} .= add: $test, $value;
        %branches := $value.branches if $value ~~ ::?CLASS
    }
    self
}

method search(%obj) {
    gather for %!branches.keys -> $key {
        for %!branches{ $key }.search: %obj{ $key } {
            when ::?CLASS {
                .take for .search: %obj
            }
            default {
                .take
            }
        }
    }
}