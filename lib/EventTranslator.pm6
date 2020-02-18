use Event::AST;
use Event::AST::EventMatcher;
unit class EventTranslator;

proto method translate(Event::AST $ast --> Array()) {*}
multi method translate(Event::AST::EventMatcher $_) {

}
multi method translate(Event::AST) {
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