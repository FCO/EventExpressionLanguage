use Event::AST::EventDeclatation;
use Event::AST::EventMatcher;
use Event::AST::Condition;
use Event::AST::LocalVar;
use Event::AST::NoValue;
use Event::AST::Group;
use Event::AST::Infix;
use Event::AST::Value;
unit class EventAction;

role Attr {}
role LocalVar {}


method TOP($/) { make $<declarator>>>.made.grep: *.defined }

method name($/) { make ~$/ }
method mp-name($/) {
    make Event::AST::LocalVar.new:
            :var-id(~$<local-var>),
            :path($<term>>>.made)
}

method term:sym<key>($/)   { make ~$<name> }
method term:sym<index>($/) { make +$<i>    }

method declarator:sym<event>($/) {
    my $name            = $<name>.made;
    my (@attrs, @body) := $<decl-body>.made;

    my %attrs = @attrs.reduce: -> %a, (:$key, :$value) {%( |%a, $key => $value )} if @attrs;
    make Event::AST::EventDeclaration.new:
            :$name,
            :%attrs,
            :@body,
    ;
}

method decl-body($/) {
    make ($<declare-attr>>>.made.grep(*.defined), $<match-block>.made // [])
}

method declare-attr:sym<setter>($/) {
    make $<event-attr>.made => $<setter>.made
}
method declare-attr:sym<nosetter>($/) {
    make $<event-attr>.map({ .made => Event::AST::NoValue }).Hash
}

method match-block($/) {
    make $<statement-time-mod>.grep(*.defined)>>.made
}

method time-unit:sym<s>($/)   { make 1 }
method time-unit:sym<min>($/) { make 60 }
method time-unit:sym<h>($/)   { make 60 * 60 }
method time-unit:sym<d>($/)   { make 24 * 60 * 60 }

method time-mod($/) { make $<val> * $<time-unit>.made }

method statement-time-mod($/) {
    make $<statement>.made
}

method statement:sym<event-match>($/) {
    say $<st-infix-op>;
    make $<st-infix-op>
        ?? Event::AST::Infix.new:
            :left($<event-match>.made),
            :right($<statement>.made),
            :op($<st-infix-op>.made)
        !! $<event-match>.made
}
method statement:sym<group>($/) {
    make Event::AST::Group.new: :body($<statement>>>.made)
}

method event-match($/) {
    make Event::AST::EventMatcher.new:
            :name(~$<name>),
            :id($<event-match-content>>>.made.first: Str),
            :conds[$<event-match-content>>>.made.grep: { .defined and $_ !~~ Str }],
    ;
}

method st-infix-op:sym<&>($/)  { make ~$/ }
method st-infix-op:sym<&&>($/) { make ~$/ }
method st-infix-op:sym<|>($/)  { make ~$/ }

method event-match-content:sym<id>($/) {
    make ~$/
}
method event-match-content:sym<condition>($/) {
    make Event::AST::Condition.new:
            :var($<name>.made),
            :op($<op>.made),
            :value($<lval>.made),
    ;
}
method event-match-content:sym<opt-condition>($/) {
    make Event::AST::Condition.new:
            :opt,
            :var($<name>.made),
            :op($<op>.made),
            :value($<lval>.made),
    ;
}
method local-var($/)  { make $<name>.made but LocalVar }
method event-attr($/) { make $<name>.made but Attr }

method vars($/) {}

method val:sym<num>($/) {
    make +$/
}
method val:sym<str>($/) {
    make ~$/
}
method val:sym<var>($/) {}

method lval:sym<operation>($/) {}
method lval:sym<val>($/)       { make ast $<val>.made }
method lval:sym<lvar>($/)      { make $<mp-name>.made }

method prefix-op:sym<not>($/) {}
method prefix-op:sym<so>($/)  {}

method infix-op:sym<plus>($/)  {}
method infix-op:sym<minus>($/) {}
method infix-op:sym<times>($/) {}
method infix-op:sym<div>($/)   {}

method operation:sym<prefix>($/) {}
method operation:sym<infix>($/)  {}

method op:sym<eq>($/) { make ~$/ }
method op:sym<gt>($/) { make ~$/ }
method op:sym<ge>($/) { make ~$/ }
method op:sym<lt>($/) { make ~$/ }
method op:sym<le>($/) { make ~$/ }