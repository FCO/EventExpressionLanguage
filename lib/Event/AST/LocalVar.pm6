use Event::AST;
unit class Event::AST::LocalVar does Event::AST;

has $.var-id is required;
has @.path;