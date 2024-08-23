use Event::AST::Matcher;
unit class Event::AST::EventMatcher does Event::AST::Matcher;

has Str $.id;
has Str $.name is required;
has     @.conds;