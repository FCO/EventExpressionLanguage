# use EELParser;
# use EventTranslator;
# use Event::Runner;
# use Event::AST;
# unit class EEL;
# 
# has Supply          $.input;
# has EELParser       $.parser .= new;
# has EventTranslator $.trans;
# has Str             $.file;
# has Str             $.code;
# has Event::AST:D    @.ast     = $!file.defined
#         ?? $!parser.parse-file: $!file
#         !! $!parser.parse: $!code
# ;
# has                 @.rules   = EventTranslator.new.translate: @!ast;
# has Event::Runner   $.runner .= new: :$!input, :@!rules;
# has Supply:D        $.output handles * = $!runner.run;
# 
# proto eel ($, :$code, :$file) is export {*}
# multi eel(@inputs, |c) { nextwith Supply.merge(@inputs), |c }
# multi eel(Supply:D $input, :$code! --> EEL) {
#     EEL.new: :$input, :$code
# }
# multi eel(Supply:D $input, :$file! --> EEL) {
#         EEL.new: :$input, :$file
# }

use MetamodelX::Event;

my package EXPORTHOW {
    package DECLARE {
        constant event = MetamodelX::Event;
    }
}
