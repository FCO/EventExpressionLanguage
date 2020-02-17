#!/usr/bin/env perl6
use lib "lib";
use EventGrammar;
use EventAction;

multi MAIN(Str $file where .IO.f) {
    CATCH {
        default {
            .message.note;
            exit 1
        }
    }
    say EventGrammar.parsefile($file, :actions(EventAction)).made
}

multi MAIN(Str :$e) {
    CATCH {
        default {
            .message.note;
            exit 1
        }
    }
    say EventGrammar.parse($e, :actions(EventAction)).made
}