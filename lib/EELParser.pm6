use EventGrammar;
use EventAction;
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
    $!grammar.parsefile: $file, :$!actions
}

method parse($code) {
    my $*EEL-FILE = "-e";
    @!files.push: "-e";
    my %*events := %!events;
    $!grammar.parse: $code, :$!actions
}