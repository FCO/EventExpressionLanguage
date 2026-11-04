use lib 'lib';
use Test;
use EEL;
event Choice {
    has $.value;
    pattern TOP {
        | <item=.event(:type<A>)> { $!value = $<item>.id }
        | <item=.event(:type<B>)> { $!value = $<item>.id }
    }
}
my @out;
({type=>'A',id=>1},{type=>'B',id=>2}).Supply.match(Choice).tap(-> $v { @out.push($v) });
is-deeply @out.map(*.value).Array,[1,2],'leading pipe recognizes both branches without empty alternative';
event Group {
    pattern TOP { [ | <.event(:type<A>)> | <.event(:type<B>)> ] <.event(:type<C>)> }
}
my @group;
({type=>'B'},{type=>'C'}).Supply.match(Group).tap(-> $v { @group.push($v) });
is @group.elems,1,'leading pipe works in nested group';
event One { pattern TOP { | <.event(:type<A>)> } }
my @one;
({type=>'A'},).Supply.match(One).tap(-> $v { @one.push($v) });
is @one.elems,1,'single branch permits leading pipe';
event Conjunction {
    pattern plain { <a> & <b> }
    pattern leading { & <a> & <b> }
    pattern ordered { && <.event(:type<A>)> && <.event(:type<B>)> }
    pattern TOP { [ & <a> & <b> ] | [ && <a> && <b> ] }
}
my $plain=Conjunction.new.plain.children[0].children[0];
my $leading=Conjunction.new.leading.children[0].children[0];
is $leading.kind,$plain.kind,'leading ampersand retains conjunction kind';
sub shape($node) { [$node.kind, $node.name, $node.children.map({ shape($_) }).Array] }
is-deeply shape($leading),shape($plain),'same conjunction operands without empty branch';
my @ordered;
({type=>'A'},{type=>'B'}).Supply.match(Conjunction,:rule<ordered>).tap(-> $v { @ordered.push($v) });
is @ordered.elems,1,'leading double ampersand executes ordered conjunction';
is Conjunction.new.TOP.kind,'pattern','both conjunction markers compile inside groups';
event OrderedChoice {
    pattern plain { <a> || <b> }
    pattern leading { || <a> || <b> }
    pattern mixed { || <a> | <b> || <c> }
}
my $ordered-plain=OrderedChoice.new.plain.children[0];
my $ordered-leading=OrderedChoice.new.leading.children[0];
is $ordered-leading.kind,'ordered-alternative','double pipe has its own compiled meaning';
is-deeply shape($ordered-leading),shape($ordered-plain),'leading double pipe preserves operands';
is OrderedChoice.new.mixed.children[0].children[0].kind,'alternative','single pipe binds more tightly than double pipe';
done-testing;
