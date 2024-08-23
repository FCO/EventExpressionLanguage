use Event::AST;
unit class Event::AST::EventDeclaration does Event::AST;
has Str $.name is required;
has     %.attrs;
has     $.body;
has     %.store;