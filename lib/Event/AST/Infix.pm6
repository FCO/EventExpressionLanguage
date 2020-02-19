use Event::AST::Matcher;
unit class Event::AST::Infix does Event::AST::Matcher;

has Str $.op;
has     @.values;