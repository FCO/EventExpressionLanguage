use Event::AST;
unit class Event::AST::Value does Event::AST;

has $.value is required;

proto ast-value($) is export          { *             }
multi ast-value(Event::AST::Value $_) { .value.return }
multi ast-value($_)                   { .self         }

proto ast($ --> Event::AST) is export   { *                              }
multi ast(Event::AST $_ --> Event::AST) { .self                          }
multi ast($value --> Event::AST)        { Event::AST::Value.new: :$value }

multi method gist(::?CLASS:D:) { $!value.gist }