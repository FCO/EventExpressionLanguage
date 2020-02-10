#!/usr/bin/env perl6
use lib "lib";
use EventGrammar;

sub MAIN(Str $file where .IO.f) {
    say EventGrammar.parsefile: $file
}
