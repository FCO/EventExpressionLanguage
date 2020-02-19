use EventGrammar;
use EventAction;
use Event::AST;
unit class EELParser;

has EventGrammar $.grammar;
has EventAction  $.actions;
has              %.events;
has              @.ast;
has              @.files;

method parse-file($file) {
    my $*EEL-FILE = $file;
    @!files.push: $file;
    my %*events := %!events;
    Array[Event::AST].new: $!grammar.parsefile($file, :$!actions).ast;
}

method parse($code) {
    my $*EEL-FILE = "-e";
    @!files.push: "-e";
    my %*events := %!events;
    Array[Event::AST].new: $!grammar.parse($code, :$!actions).ast
}