use lib 'lib';
use Test;
use EEL;
use EEL::Runner;

event Packet {
    pattern TOP { <header> <item> ** { $<header>.count } }
    pattern header { <h=.event(:type<header>)> { make $<h>.count } }
    pattern item { <i=.event(:type<item>)> { make $<i>.value } }
    pattern infinite { <header> <item> ** { 1..Inf } <.event(:type<end>)> }
    pattern trailing { <header> <item> ** { $<header>.count } %% <.event(:type<sep>)> <.event(:type<end>)> }
    pattern shortest { <header> <item> ** { 1..$<header>.count }? <.event(:type<end>)> }
    pattern ranged { <header> <item> ** { 1..$<header>.count }! <.event(:type<end>)> }
    pattern separated { <header> <item> ** { $<header>.count } % <.event(:type<sep>)> }
    pattern once { :my $n = 0; <header> <item> ** { ++$n; $<header>.count } { make $n } }
    pattern invalid { <header> <item> ** { $<header>.value } }
    pattern nullable { <header> [] ** { $<header>.value } }
    pattern silent { <.item> { make 99 } }
    pattern closing { <header> <item> ** { $<header>.count } $$ }
    pattern nullable-call { <header> <empty> ** { $<header>.value } }
    pattern empty { [] }
    pattern parameterized(Int $n) { <item> ** { $n } }
    pattern parameters { <header> <parameterized($<header>.count)> }
    pattern forked { <header> <item> ** { $<header>.count } [ <.event(:type<x>)> | <.event(:type<y>)> ] }
}
class Build {
    method header($/) { make $<h>.count * 10 }
    method item($/) { make $<i>.value * 2 }
    method TOP($/) { make $<item>.map(*.made).Array }
}
sub header($count, $value = 0) { {type=>'header', :$count, :$value}.item }
sub item($value) { {type=>'item', :$value}.item }
sub feed($rule, @input, :$actions) {
    my $r = EEL::Runner.new(:patterns[Packet], :$rule, :$actions);
    my @out;
    @out.append($r.process($_)) for @input;
    @out.append($r.finish);
    @out
}
my @packet = feed('TOP', [header(2), item(3), item(5)], :actions(Build.new));
is @packet.elems, 1, 'dynamic exact count completes';
is-deeply @packet[0].made, [6,10], 'external Actions override inline make and combine subpattern values';
is-deeply @packet[0].ast, [6,10], 'ast aliases made';
is @packet[0]<header>.made, 20, 'subpattern action runs before parent';
is feed('TOP', [header(2), item(3)]).elems, 0, 'minimum enforced';
is feed('TOP', [header(0)]).elems, 1, 'zero count completes without item';
is feed('TOP', [header(1),item(7)])[0]<item>[0].made, 7, 'inline make without external actions';
is feed('once', [header(3),item(1),item(2),item(3)])[0].made, 1, 'bounds evaluated once across repeat growth and forks';
is feed('separated', [header(2),item(1),{type=>'sep'},item(2)]).elems, 1, 'dynamic count works with separators';
is feed('ranged', [header(2),item(1),item(2),{type=>'end'}]).elems, 2, 'dynamic inclusive range with exhaustive selection';
is feed('infinite', [header(2),item(1),item(2),{type=>'end'}]).elems, 1, 'unbounded dynamic range accepts a consuming body';
is feed('trailing', [header(2),item(1),{type=>'sep'},item(2),{type=>'sep'},{type=>'end'}]).elems, 1, 'dynamic count accepts trailing separator';
is feed('shortest', [header(2),item(1),item(2),{type=>'end'}])[0]<item>.elems, 1, 'dynamic range honors shortest selection';
is feed('forked', [header(2),item(1),item(2),{type=>'y'}]).elems, 1, 'evaluated bounds survive alternative forks';
for -1, 1.5, '2', (3..1), (1..^3) -> $invalid {
    throws-like { feed('invalid', [header(1,$invalid)]) }, Exception, 'invalid dynamic bound rejected';
}
throws-like { feed('nullable', [header(1,0..Inf)]) }, Exception, 'unbounded nullable dynamic repeat rejected';
is feed('nullable', [header(1,2)]).elems, 1, 'finite nullable dynamic repeat allowed';
my @made;
(header(2),item(3),item(5)).Supply.match(Packet, :actions(Build.new)).made.tap(-> $value { @made.push($value) });
is-deeply @made, [[6,10],], 'Supply.made projects published results';
my @ast;
(header(1),item(4)).Supply.match(Packet, :actions(Build.new)).ast.tap(-> $value { @ast.push($value) });
is-deeply @ast, [[8],], 'Supply.ast aliases made';
class Broken { method TOP($/) { die 'action failed' } }
throws-like { feed('TOP', [header(0)], :actions(Broken.new)) }, Exception, message => /'action failed'/, 'action exceptions propagate';
class RegexActions { method TOP($/) { make 42 } }
grammar Ordinary { token TOP { a } }
is Ordinary.parse('a', :actions(RegexActions.new)).made, 42, 'make works in ordinary grammar Actions';
is ('a' ~~ / a { make 17 } /).made, 17, 'make works inside ordinary regex';
is feed('parameters', [header(2),item(1),item(2)]).elems, 1, 'dynamic bound reads subpattern parameter';
throws-like { feed('nullable-call', [header(1,0..Inf)]) }, Exception, 'nullable subpattern cannot repeat infinitely';
is feed('nullable-call', [header(1,2)]).elems, 1, 'finite repetition of nullable subpattern';
class CountActions {
    has $.calls is rw = 0;
    method item($/) { ++$!calls; make $<i>.value }
    method closing($/) { make $<item>.map(*.made).Array }
}
my $counter = CountActions.new;
is feed('silent', [item(5)], :actions($counter))[0].made, 99, 'missing parent Action preserves inline make';
is $counter.calls, 1, 'silent calls invoke external Actions';
is-deeply feed('closing', [header(1),item(5)], :actions($counter))[0].made, [5], 'EOF completion invokes Action';
my $lazy-counter = CountActions.new;
my $stream = (header(1),item(3)).Supply.match(Packet, :actions($lazy-counter));
is $lazy-counter.calls, 0, 'Actions are deferred to subscription';
$stream.tap;
$stream.tap;
is $lazy-counter.calls, 2, 'each subscription runs Actions';
my $source = Supplier.new;
my $error;
my $tap = $source.Supply.match(Packet, :actions(Broken.new)).tap(-> $result { }, quit => -> $exception { $error = $exception });
$source.emit(header(0));
like $error.message, /'action failed'/, 'Supply routes Action exceptions to quit';
$tap.close;
event Family {
    proto pattern TOP {*}
    pattern TOP:sym<a> { <a=.event(:type<a>)> }
    pattern TOP:sym<b> { <b=.event(:type<b>)> }
}
class FamilyActions { method TOP($/) { make 'family' } }
my @family = EEL::Runner.new(:patterns[Family], :actions(FamilyActions.new)).process({type=>'a'});
is @family[0].made, 'family', 'proto entry invokes family Action';
event Updates { pattern TOP { :10s ^ <i=.event(:type<item>)>+ } }
class UpdateActions { method TOP($/) { make $<i>.elems } }
my $updater = EEL::Runner.new(:patterns[Updates], :actions(UpdateActions.new));
my $first = $updater.process({type=>'item',timestamp=>0})[0];
my $second = $updater.process({type=>'item',timestamp=>1})[0];
is $first.made, 1, 'first semantic snapshot remains unchanged';
is $second.made, 2, 'Actions compute semantic values for incremental updates';
is $first.event-id, $second.event-id, 'semantic updates retain recognition identity';
done-testing;
