use Event::AST;
use Event::AST::EventDeclaration;
use Event::AST::EventMatcher;
use Event::AST::Condition;
use Event::AST::LocalVar;
use Event::AST::Group;
use Event::AST::Infix;
use Event::AST::Value;
unit class EventTranslator;

multi method translate(Event::AST @ast --> Array()) {
#    say $?LINE;
#    dd @ast;
    @ = @ast.map: { self.translate: $_ }
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
}

multi method translate(Event::AST::EventDeclaration $ast --> Hash()) {
#    say $?LINE;
    my %*store = $ast.store;
    self.translate: $ast.body, (self.translate: %( :type(ast $ast.name), |$_ ) with $ast.attrs)
}

multi method translate([Event::AST::EventMatcher $_, *@next ($)], %disp?) {
#    say $?LINE;
    %(
        |self.translate($_),
        :next(self.translate: @next, %disp)
    )
}

multi method translate([Event::AST::EventMatcher $_], %disp?) { self.translate: $_, %disp }

multi method translate(Event::AST::EventMatcher $_, %next?) {
#    say $?LINE;
    %(
        :cmd<query>,
        |(:id($_) with .id),
        |(:store($_) with %*store{ .id }),
        |(
            :query(%(
                |(:type("==" => $_) with .name),
                |.conds.map({ self.translate: $_ })
            )) if .conds
        ),
        :%next,
    )
}

multi method translate([]) {}

multi method translate(Event::AST::Condition $_) {
#    say $?LINE;
    .var => (.op => self.translate: .value)
}

multi method translate(Event::AST::Value $_) {
#    say $?LINE;
    .&ast-value
}

multi method translate(Event::AST:D $_) {
#    say $?LINE;
#    .&dd;
    {
        cmd      => "query",
        query    => %(
            :type("==" => "request"),
            :path("==" => "/login"),
            :method("==" => "GET"),
            :status("==" => 200),
        ),
        id       => "#get",
        store    => < req-id >,
        next     => {
            cmd      => "query",
            query    => %(
            :type("==" => "request"),
                    :path("==" => "/login"),
                    :method("==" => "POST"),
                    :req-id("==" => -> %state { %state<#get><req-id> }),
                    :status("==" => 200),
            ),
            id       => "#post",
            store    => < session-id timestamp >,
            next     => {
                cmd      => "dispatch",
                data     => -> %state --> Hash() {
                    :type<login>,
                    :session-id(%state<#post><session-id>),
                    :timestamp(%state<#post><timestamp>),
                },
            }
        }
    },
}