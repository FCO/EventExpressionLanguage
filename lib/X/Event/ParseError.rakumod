unit class X::Event::ParseError is Exception;

has Str   $.file  = "-e";
has Match $.match is required;
has Str   $.msg   = "Error parsing code";

method message {
    my @prematch  = $!match.prematch.lines;
    my $parsed    = @prematch.tail.trim-leading;
    my $notparsed = $!match.target.substr: $!match.pos, min($!match.pos + 15, $!match.target.index: "\n");
    my $line      = "\o33[32m{$parsed}\o33[33m⏏\o33[31m{$!match.Str}\o33[m{$notparsed}";
    (
        "PARSING ERROR : $!msg",
        "ERROR         : $line",
        "FILE          : $!file",
        "LINE          : { +@prematch }",
    ).join: "\n"
}