use Test;
use EventGrammar;
use X::Event::ParseError;

sub test-parse-error(&code, Str :$msg, UInt :$line, Str :$error) {
    subtest {
        CATCH {
            when X::Event::ParseError {
                my $message = .message;
                like $message, /^^ "PARSING ERROR" \s+ ":" \s+ $_ $$/,  "Right error message"   with $msg;
                like $message, /^^ "LINE"          \s+ ":" \s+ $_ $$/, "Right error line"       with $line;
                like $message, /^^ 'ERROR'         \s+ ":" \s+ .*? . "[33m⏏" . "[31m$_" . "[m"/ with $error;
            }
        }
        code();
        fail "Code did not die"
    }, "PARSE ERROR: $msg"
}

lives-ok {
    EventGrammar.parsefile: "./examples/fire-risk"
}

test-parse-error {
    EventGrammar.parsefile: "./examples/errors/redefine-event"
},
        :msg("Event 'new-event' already defined"),
        :line(2),
        :error<new-event>,
;

test-parse-error {
    EventGrammar.parsefile: "./examples/errors/redefine-event-attr-nosetter"
},
        :msg(Q{Event 'new-event' already defined an attr called '$value'}),
        :line(1),
        :error<$value>,
;

test-parse-error {
    EventGrammar.parsefile: "./examples/errors/redefine-event-attr-setter"
},
        :msg(Q{Event 'new-event' already defined an attr called '$value'}),
        :line(3),
        :error<$value>,
;

test-parse-error {
    EventGrammar.parsefile: "./examples/errors/redefine-event-attr-setter-and-nosetter"
},
        :msg(Q{Event 'new-event' already defined an attr called '$value'}),
        :line(3),
        :error<$value>,
;

#todo "Should work...";
#test-parse-error {
#    EventGrammar.parsefile: "./examples/errors/redefine-id"
#},
#        :msg(Q{Id '#ble' already in use}),
#        :line(6),
#        :error<#ble>,
#;

lives-ok {
    EventGrammar.parsefile: "./examples/fire-risk"
}, "Parses OK";

done-testing;