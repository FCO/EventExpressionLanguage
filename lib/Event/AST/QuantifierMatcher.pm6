use Event::AST::Matcher;
unit class Event::AST::QuantifierMatcher does Event::AST::Matcher;

has Event::AST::Matcher $.matcher;
has UInt                $.min;
has UInt                $.max;
