#!/usr/bin/env perl6
use lib "lib";
use EELParser;

multi MAIN(Str $file where .IO.f) {
    CATCH {
        default {
            .message.note;
            exit 1
        }
    }
    say EELParser.new.parse-file: $file
}

multi MAIN(Str :$e) {
    CATCH {
        default {
            .message.note;
            exit 1
        }
    }
    say EELParser.new.parse: $e
}