use EventGrammar;
use EventAction;
use EventTranslator;
use Event::Runner;
use Event::AST;
unit class EEL;

has Supply          $.input;
has EventGrammar    $.grammar;
has EventAction     $.actions;
has EventTranslator $.trans;
has Str             $.code;
has Event::AST      $.ast     = $!grammar.parse($!code, :$!actions).ast;
has                 @!rules   = EventTranslator.new.translate($!ast);
has Event::Runner   $.runner .= new: :$!input, :@!rules;
has Supply:D        $.output handles * = $!runner.run;

proto eel ($, :$code!) is export {*}
multi eel(@inputs, |c) { nextwith Supply.merge(@inputs), |c }
multi eel(Supply:D $input, :$code! --> EEL) {
    EEL.new: :$input, :$code
}