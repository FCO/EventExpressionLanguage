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

#proto method translate(\data) {
#    say "Input: ";
#    dd data;
#    my \ret = {*};
#    say "Return: ";
#    dd [ :data(data), :ret(ret) ];
#    say "-" x 30;
#    ret
#}

multi method translate(Event::AST @ast --> Array()) {
    my @rules;
    for @ast {
        given self.translate: $_ {
            when Positional | Sequence {
                for .self -> %rule {
                    @rules.push: %rule
                }
            }
            default {
                @rules.push: .self
            }
        }
    }
    @rules
}

multi method translate(Event::AST::LocalVar $ast) {
    -> %state {
        my $root = %state{ $ast.var-id };
        for $ast.path -> $next {
            $root = $root{ $next } // Nil
        }
        $root<>
    }
}

multi method translate(%attrs) {
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
    Empty
}

multi method translate(Event::AST::EventDeclaration $ast) {
    my %*store = $ast.store;
    self.translate: [
        |$ast.body,
        %( :type(ast $ast.name), |$ast.attrs ),
    ]
}

multi method prepare-event-matcher(Event::AST::EventMatcher $ast, %next) {
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
    do given self.translate: @next {
        when Positional | Sequence {
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
    .var => (.op => self.translate: .value)
}

multi method translate(Event::AST::Value $_) {
    .&ast-value
}