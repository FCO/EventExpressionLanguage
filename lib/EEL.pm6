use EventGrammar;
use EventAction;
#use EventTranslator;
use Event::Runner;
use Event::AST;
unit class EEL;

has Supply          $.input;
has EventGrammar    $.grammar;
has EventAction     $.actions;
#has EventTranslator $.trans;
has Str             $.code;
has Event::AST      $.ast   = $!grammar.parse($!code, :$!actions).ast;
has                 @!rules = #EventTranslator.new($!ast).translate; # just while there is no translator
    {
        cmd      => "query",
        query    => %(
            :type("==" => "request"),
            :path("==" => "/login"),
            :method("==" => "GET"),
            :status("==" => 200),
        ),
        id       => "#get",
        store    => < req-id >,
        next     => {
            cmd      => "query",
            query    => %(
                :type("==" => "request"),
                :path("==" => "/login"),
                :method("==" => "POST"),
                :req-id("==" => -> %state { %state<#get><req-id> }),
                :status("==" => 200),
            ),
            id       => "#post",
            store    => < session-id timestamp >,
            next     => {
                cmd      => "dispatch",
                data     => -> %state --> Hash() {
                    :type<login>,
                    :session-id(%state<#post><session-id>),
                    :timestamp(%state<#post><timestamp>),
                },
            }
        }
    },
;
has Event::Runner $.runner .= new: :$!input, :@!rules;
has Supply:D      $.output handles * = $!runner.run;

proto eel ($, :$code!) is export {*}
multi eel(@inputs, |c) { nextwith Supply.merge(@inputs), |c }
multi eel(Supply:D $input, :$code! --> EEL) {
    EEL.new: :$input, :$code
}