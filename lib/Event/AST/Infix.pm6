use Event::AST;
unit class Event::AST::Infix does Event::AST;

has Event::AST $.left;
has Event::AST $.right;
has Str        $.op;