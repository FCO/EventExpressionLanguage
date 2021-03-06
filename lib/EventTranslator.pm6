use Event::AST;
use Event::AST::QuantifierMatcher;
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
        $root
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
    my Bool $*first = True;
    my %*store = $ast.store;
    self.translate: [
        |$ast.body,
        %( :type(ast $ast.name), |$ast.attrs ),
    ]
}

multi method prepare-event-matcher(Event::AST::EventMatcher $ast, %next) {
    my Event::AST::Condition @conds = Array[Event::AST::Condition].new: $ast.conds;
    @conds .= grep: { not .opt } if $*first--;
    %(
        :cmd<query>,
        |(:id($_) with $ast.id),
        |(:store($_) with %*store{ $ast.id // "" }.?unique),
        |(
            :query(%(
                |@conds.map({ self.translate: $_ }),
                |(:type("==" => $_) with $ast.name),
            ))
        ),
        :%next,
    )
}

multi method translate([Event::AST::Infix $ast where .op eq "&", *@next]) {
    my %store := %*store;
    my $first := $*first;
    $ast.values.permutations.map: {
        my %*store := %store;
        my $*first = $first;
        self.translate: [|$_, |@next]
    }
}

multi method translate([Event::AST::QuantifierMatcher $ast  , *@next]) {
    my @rules;
    my $first = $*first;

    for $ast.min .. $ast.max {
        my $*first = $first;
        @rules.push: self.translate: [
            |($ast.matcher xx $_),
            |@next
        ];
    }
    @rules
}

multi method translate([Event::AST::Group $ast, *@next]) {
    self.translate: [ |$ast.body, |@next ]
}

multi method translate([Event::AST::Matcher $ast, *@next]) {
    my %store := %*store;
    my $first = $*first;
    $*first--;
    do given self.translate: @next {
        when Positional | Sequence {
            .self.map: {
                my %*store := %store;
                my $*first := $first;
                self.prepare-event-matcher: $ast, $_
            }
        }
        default {
            my %*store := %store;
            my $*first := $first;
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