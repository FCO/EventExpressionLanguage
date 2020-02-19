use Event::AST;
use Event::AST::EventDeclaration;
use Event::AST::EventMatcher;
use Event::AST::Condition;
use Event::AST::Group;
use Event::AST::Infix;
use Event::AST::Value;
unit class EventTranslator;

multi method translate(Event::AST @ast --> Array()) {
    say $?LINE;
    dd @ast;
    @ = @ast.map: { self.translate: $_ }
}

multi method translate(%attrs) {
    say $?LINE;
    %(
        :cmd<dispatch>,
        :data(-> %state { %() })
    )
}

multi method translate(Event::AST::EventDeclaration $_ where not .body) {
    say $?LINE;
}

multi method translate(Event::AST::EventDeclaration $_ --> Hash()) {
    say $?LINE;
    self.translate: .body, (self.translate: $_ with .attrs)
}

multi method translate([Event::AST::EventMatcher $_, *@next ($)], %disp?) {
    say $?LINE;
    %(
        |self.translate($_),
        :next(self.translate: @next, %disp)
    )
}

multi method translate([Event::AST::EventMatcher $_], %disp?) { self.translate: $_, %disp }

multi method translate(Event::AST::EventMatcher $_, %next?) {
    say $?LINE;
    %(
        :cmd<query>,
        |(:id($_) with .id),
        :store,
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
    say $?LINE;
    .var => (.op => self.translate: .value)
}

multi method translate(Event::AST::Value $_) {
    say $?LINE;
    .&ast-value
}

multi method translate(Event::AST:D $_) {
    say $?LINE;
    .&dd;
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