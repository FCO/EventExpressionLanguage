use Event::AST::Matcher;
unit class Event::AST::QuantifierMatcher does Event::AST::Matcher;

has Event::AST::Matcher $.matcher;
has Int                 $.min;
has Int                 $.max;
