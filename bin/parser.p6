#!/usr/bin/env perl6
use lib "lib";
use EventGrammar;
use EventAction;

multi MAIN(Str $file where .IO.f) {
    say EventGrammar.parsefile($file, :actions(EventAction)).made
}

multi MAIN(Str :$e) {
    say EventGrammar.parse($e, :actions(EventAction)).made
}