unit class QueryStorage::BTree::Node;

has          $.tree;
has ::?CLASS $.left   is rw;
has ::?CLASS $.right  is rw;
has          $.value;
has          @.stored;

multi method add($value, $stored) { self.add: ::?CLASS.new: :$!tree, :$value, :$stored }

multi method add(::?CLASS $node where { $!tree.func: $node.?value, .value with $!right }) {
    $!right.add: $node
}

multi method add(::?CLASS $node where { $!tree.func: .value, $node.?value with $!left }) {
    $!left.add: $node
}

multi method add(::?CLASS $node where $!tree.func: $!value, $node.?value) {
    $node.left   = $!left;
    $!left       = $node
}

multi method add(::?CLASS $node where $!tree.func: $node.value, $!value) {
    $node.right  = $!right;
    $!right      = $node
}

multi method add(::?CLASS $node where $node.value == $!value) {
    @!stored.append: |$node.stored
}

method take-all {
    .take-all with $!left;
    .take for @!stored;
    .take-all with $!right
}

multi method search($val where $!tree.func($_, $!value)) {
    .take-all with $!left;
    .take for @!stored;
    .search: $val with $!right;
}
multi method search($val where { $!tree.func($val, .value) with $!left }) {
    .take-all with $!left;
    .take for @!stored
}
multi method search($val) {
    .search: $val with $!right
}

multi method del-not-matching(::?CLASS:D: $val where { not $!tree.func: $val, $_ with $!value }) {
    return .?del-not-matching: $val with $!left;
    ::?CLASS
}

multi method del-not-matching(::?CLASS:D: $val where { not $!tree.func: $val, $_ with $!left }) {
    $!left = .?del-not-matching: $val with $!left;
    ::?CLASS
}

multi method del-not-matching(::?CLASS:D: $val) {
    $!right = .?del-not-matching: $val with $!right;
    self
}