use Event::AST;
unit class Event::AST::EventMatcher does Event::AST;

has Str $.id;
has Str $.name is required;
has     @.conds;