use Event::AST;
unit class Event::AST::Condition does Event::AST;
has Bool $.opt = False;
has Str  $.var;
has Str  $.op;
has      $.value;

multi method gist(::?CLASS:D:) { "{ $!opt ?? "?" !! "" }{ $!var } { $!op } { $!value.gist }" }