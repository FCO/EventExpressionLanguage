use lib 'lib';
use Test;
use EEL;

sub nodes($node) { gather { take $node; for $node.children { .take for nodes($_) } } }
sub of-kind($node, $kind) { nodes($node).grep(*.kind eq $kind).List }

my $executions = 0;
my $offset = 10;
event SlangExample {
    has $.answer is rw;
    pattern TOP(Int $value = 2) {
        :my $local = $value + $offset;
        :partition{ .<a>, .<b> }
        :ignore-unexpected
        <first=.event(:type<start>, :value($local), :previous($<previous>))>
        [ :5min  :!ignore-unexpected <.finish> ]
        { $executions++; $!answer = $local; $<previous> }
    }
    pattern operators {
        <a>? <b>* <c>+ <d> ** 2 <e> ** 1..3 <f> ** 2..*
        && ( <g> & <h> ) | <.fallback>
    }
    pattern scoped {
        :my $x = 1;
        [ :my $x = 2; <inside> { $x } ]
        { $x }
    }
    pattern string-key { :partition{ "{ .<a> } { .<b> }" } <.event> }
    pattern captures { ( <a> ( <b> { $<previous> } ) ) ( <c> ) { $0 } }
    pattern empty { }
    pattern units { [ :2s <a> ] [ :3min <b> ] [ :4h <c> ] [ :5days <d> ] }
    method ordinary { { answer => 42 } }
}

my $method = SlangExample.^find_method('TOP');
is $method.definition.kind, 'pattern', 'method exposes compiled definition';
is $method.definition.name, 'TOP', 'definition preserves pattern name';
is $method.definition.children[0].kind, 'sequence', 'body is a sequence';
is $method.definition.line, 12, 'definition records source line';
is $executions, 0, 'compilation does not execute action blocks';
my $event = SlangExample.new(:hash({previous => 'captured'}));
my $definition = $method.instantiate($event, 3);
is $executions, 0, 'materializing a definition does not execute its actions';
my $local = of-kind($definition, 'local')[0];
$local.code.();
my $args = of-kind($definition, 'call')[0].code.();
isa-ok $args, Capture, 'call arguments are delayed as a Capture';
is $args<value>, 13, 'arguments retain parameters, outer lexicals and locals';
is $args<previous>, 'captured', 'arguments can reference captures';
is of-kind($definition, 'call')[0].properties<capture>, 'first', 'alias capture recorded';
is of-kind($definition, 'call')[1].properties<capture>, '', 'silent call is not captured';
my $partition = of-kind($definition, 'partition')[0].code;
is-deeply $partition({a => 'a b', b => 'c'}), ('a b', 'c'), 'partition preserves list result';
my $string-partition = of-kind($event.string-key, 'partition')[0].code;
is $string-partition({a => 'a b', b => 'c'}), 'a b c', 'partition preserves interpolated string';
is of-kind($definition, 'code')[0].code.(), 'captured', 'action can access captures';
is $event.answer, 13, 'action can update an event attribute';
is $executions, 1, 'action runs only when invoked';
is-deeply of-kind($definition, 'ignore-unexpected')».properties.map(*.<enabled>).List, (True, False), 'both unexpected-event adverbs recorded';
is of-kind($definition, 'window-start')[0].properties<seconds>, 300, 'window converted to seconds';
is of-kind($definition, 'window-start')[0].properties<clock>, 'event', 'event clock recorded';
nok of-kind($definition, 'window-start')[0].properties<inclusive>, 'window limit is exclusive';

my $operators = $event.operators;
is $operators.children[0].kind, 'alternative', 'alternation has lowest precedence';
is of-kind($operators, 'unordered').elems, 1, 'unordered conjunction compiled';
is of-kind($operators, 'ordered').elems, 1, 'explicit ordered conjunction compiled';
is of-kind($operators, 'capture-group').elems, 1, 'parentheses create positional capture';
is of-kind($operators, 'capture-group')[0].properties<index>, 0, 'positional captures are numbered from zero';
is-deeply of-kind($operators, 'repeat').map({ [.properties<min>, .properties<max>] }).Array,
    [[0,1], [0,Inf], [1,Inf], [2,2], [1,3], [2,Inf]], 'all quantifiers compiled';
my $captures = SlangExample.new(:hash({previous => 'nested'}), :list[42]).captures;
is-deeply of-kind($captures, 'capture-group').map({ .properties<index> }).List, (0, 1, 2), 'nested positional captures follow source order';
is of-kind($captures, 'code')[0].code.(), 'nested', 'nested actions retain match context';
is of-kind($captures, 'code')[1].code.(), 42, 'actions can access positional captures';
my $scoped = $event.scoped;
.code.() for of-kind($scoped, 'local');
is-deeply of-kind($scoped, 'code').map({ .code.() }).List, (2, 1), 'group locals shadow without leaking';
is of-kind($event.empty, 'call').elems, 0, 'empty patterns compile';
is-deeply of-kind($event.units, 'window-start').map({.properties<seconds>}).List,
    (2,180,14400,432000), 'all duration units compile';
is $event.ordinary<answer>, 42, 'ordinary method and hash syntax unchanged';
throws-like { SlangExample.parse(supply { }) }, X::AdHoc,
    message => /'legacy'/, 'legacy runner rejects new definitions explicitly';

sub compile-source(Str $source) {
    my $proc = run $*EXECUTABLE, '-Ilib', '-c', '-e', $source, :out, :err;
    my $out = $proc.out.slurp(:close);
    my $err = $proc.err.slurp(:close);
    ($proc.exitcode, $out ~ $err)
}
for (
    'pattern TOP { <a> ** 3..1 }' => 'inverted repetition',
    'pattern TOP { <a> ** -1 }' => 'negative repetition',
    'pattern TOP { <a> ** }' => 'missing repetition bound',
    'pattern TOP { <a> | }' => 'missing alternative',
    'pattern TOP { [ <a> }' => 'unclosed group',
    'pattern TOP { :unknown <a> }' => 'unknown adverb',
    'pattern TOP { <.alias=.target> }' => 'silent alias',
    'pattern TOP { <a> 3fortnights }' => 'unknown duration unit',
    'pattern TOP { <a> }; pattern TOP { <b> }' => 'duplicate declaration'
) -> $case {
    my ($status, $message) = compile-source('use EEL; event Invalid { ' ~ $case.key ~ ' }');
    isnt $status, 0, "rejects {$case.value}";
    like $message, / 'line' | 'at -e:' /, 'diagnostic includes source location';
}
my ($status, $message) = compile-source('{ use EEL; event Inside { pattern TOP { <a> } } }; class Outside { pattern TOP { <a> } }');
isnt $status, 0, 'slang does not leak outside importing scope';
like $message, /'pattern'/, 'outside pattern is rejected';
($status, $message) = compile-source('use EEL; event Outer { pattern TOP { { my %nested = a => { b => 1 }; "{ %nested<a><b> }" } <.event> } }');
is $status, 0, 'nested Raku blocks, hashes and interpolation compile';
my ($event-status, $event-message) = compile-source('{ use EEL; event Inside { } }; event Outside { }');
isnt $event-status, 0, 'event declarator is lexical too';
like $event-message, /'event'/, 'outside event declaration is rejected';
($status, $message) = compile-source('use EEL; use EEL; event Twice { pattern TOP { <a> } }');
is $status, 0, 'repeated imports work';
my $another = $method.instantiate(SlangExample.new, 9);
of-kind($another, 'local')[0].code.();
is of-kind($another, 'call')[0].code.()<value>, 19, 'second materialization has independent local state';
is of-kind($definition, 'call')[0].code.()<value>, 13, 'first materialization retains its own local state';
for ^2 {
    my $proc = run $*EXECUTABLE, '-Ilib', '-It/lib', '-e',
        'use SlangFixture; say SlangFixture::Reusable.^find_method("TOP").definition.kind; say SlangFixture::Reusable.new.TOP.kind', :out, :err;
    my $out = $proc.out.slurp(:close);
    my $err = $proc.err.slurp(:close);
    is $proc.exitcode, 0, 'module with slang loads from precompilation';
    is $out, "pattern\npattern\n", 'precompiled method retains metadata and factory';
    is $err, '', 'precompiled module loads without errors';
}
done-testing;
