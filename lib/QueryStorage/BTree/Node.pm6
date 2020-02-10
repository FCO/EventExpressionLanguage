unit class QueryStorage::BTree::Node;

has          $.tree;
has ::?CLASS $.left  is rw;
has ::?CLASS $.right is rw;
has          $.value;
has          @.stored;

multi method add($value, $stored) { self.add: ::?CLASS.new: :$!tree, :$value, :$stored }

multi method add(::?CLASS $node where { $!tree.func: $node.value, .value with $!right }) {
    $!right.add: $node
}

multi method add(::?CLASS $node where { $!tree.func: .value, $node.value with $!left }) {
    $!left.add: $node
}

multi method add(::?CLASS $node where $!tree.func: $!value, $node.value) {
    $node.left = $!left;
    $!left     = $node
}

multi method add(::?CLASS $node where $!tree.func: $node.value, $!value) {
    $node.right = $!right;
    $!right     = $node
}

multi method add(::?CLASS $node where $node.value == $!value) {
    @!stored.append: |$node.stored
}

multi method search($val where { $!tree.func($val, .value) with $!left }) {
    .search: $val with $!left;
    .take for @!stored;
    .search: $val with $!right;
}
multi method search($val where $!tree.func($_, $!value)) {
    .take for @!stored;
    .search: $val with $!right
}
multi method search($val) {
    .search: $val with $!right
}