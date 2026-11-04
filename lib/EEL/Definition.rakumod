unit class EEL::Definition;

has Str $.kind is required;
has Str $.source = '';
has Str $.name = '';
has Int $.line = 1;
has Int $.column = 1;
has @.children;
has %.properties;
has $.code;
has $.factory;
has $.origin;
has $.read-state;
has $.write-state;
has $.arguments-code;
method gist { "$!kind" ~ ($!name ?? "($!name)" !! '') ~ (@!children ?? '[' ~ @!children>>.gist.join(', ') ~ ']' !! '') }

role CompiledPattern is export {
    has EEL::Definition $.definition is rw;
    method instantiate(Mu $event, |arguments) { self.($event, |arguments) }
}

method materialize($code, $read-state, $write-state, $arguments-code, *@children) {
    self.clone(:origin(self), :$code, :$read-state, :$write-state, :$arguments-code, :@children, :factory(Nil))
}
