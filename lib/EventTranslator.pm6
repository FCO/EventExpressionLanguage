use Event::AST;
use Event::AST::EventDeclaration;
use Event::AST::EventMatcher;
use Event::AST::Condition;
use Event::AST::LocalVar;
use Event::AST::Infix;
use Event::AST::Group;
use Event::AST::Infix;
use Event::AST::Value;

unit class EventTranslator;

multi method translate(Event::AST @ast --> Array()) {
    my @rules;
    for @ast {
        for self.translate: $_ -> %rule {
            @rules.push: %rule
        }
    }
    @rules
}

multi method translate(Event::AST::LocalVar $ast) {
    -> %state {
#        dd [:%state, :$ast];
        my $root = %state{ $ast.var-id };
        for $ast.path -> $next {
            $root = $root{ $next } // Nil
        }
        $root<>
    }
}

multi method translate(%attrs) {
#    say $?LINE;
    my %attrs-callable = %attrs.kv.map: -> $key, $value {
        $key => self.translate: $value
    }
    %(
        :cmd<dispatch>,
        :data(-> %state {
            %attrs-callable.kv.map(-> $key, $value {
                $key => do given $value {
                    when Callable {
                        .(%state)
                    }
                    default {
                        .self
                    }
                }
            }).Hash
        })
    )
}

multi method translate(Event::AST::EventDeclaration $_ where not .body) {
#    say $?LINE;
    Empty
}

multi method translate(Event::AST::EventDeclaration $ast) {
#    say $?LINE;
    my %*store = $ast.store;
    self.translate: [
        |$ast.body,
        %( :type(ast $ast.name), |$ast.attrs ),
    ]
}

multi method prepare-event-matcher(Event::AST::EventMatcher $ast, %next) {
#    dd %*store;
    %(
        :cmd<query>,
        |(:id($_) with $ast.id),
        |(:store($_) with %*store{ $ast.id }),
        |(
            :query(%(
                |(:type("==" => $_) with $ast.name),
                |$ast.conds.map({ self.translate: $_ })
            )) if $ast.conds
        ),
        :%next,
    )
}

multi method translate([Event::AST::Infix $ast where .op eq "&", *@next]) {
    my %store := %*store;
    $ast.values.permutations.map: {
        my %*store = %store;
        self.translate: [|$_, |@next]
    }
}

multi method translate([Event::AST::Matcher $ast, *@next]) {
#    say $?LINE;
    do given self.translate: @next {
        when Positional {
            .self.map: {
                self.prepare-event-matcher: $ast, $_
            }
        }
        default {
            self.prepare-event-matcher: $ast, $_
        }
    }
}

multi method translate([%next]) { self.translate: %next }

multi method translate([]) {}

multi method translate(Event::AST::Condition $_) {
#    say $?LINE;
    .var => (.op => self.translate: .value)
}

multi method translate(Event::AST::Value $_) {
#    say $?LINE;
    .&ast-value
}