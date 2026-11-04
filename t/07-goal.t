use lib 'lib';
use Test;
use EEL;
use EEL::Runner;

sub nodes($node) { gather { take $node; for $node.children { .take for nodes($_) } } }
sub of-kind($node, $kind) { nodes($node).grep(*.kind eq $kind).List }
sub feed($type, @types) {
    my $runner = EEL::Runner.new(:patterns[$type]);
    my @out;
    for @types.kv -> $i, $type { @out.append($runner.process({type => $type, index => $i})) }
    $runner.finish;
    @out.List
}

event Pair {
    pattern TOP {
        :!ignore-unexpected
        <open=.event(:type<open>)> ~ <close=.event(:type<close>)> <body=.event(:type<text>)>
        <tail=.event(:type<tail>)>
    }
}
my $tree = Pair.^find_method('TOP').definition;
my $goal = of-kind($tree, 'goal')[0];
is $goal.children[0].properties<capture>, 'close', 'goal keeps closing atom in source order';
is $goal.children[1].properties<capture>, 'body', 'goal keeps body atom in source order';
is $tree.children[0].children.tail.properties<capture>, 'tail', 'goal takes exactly the next two quantified atoms';
is feed(Pair, <open close text tail>).elems, 0, 'source operand order is not consumption order';
my @pair = feed(Pair, <open text close tail>);
is @pair.elems, 1, 'matches opener, body, closer, suffix';
is @pair[0]<body>.data<index>, 1, 'body consumes the middle event';
is @pair[0]<close>.data<index>, 2, 'closer is consumed after body';
is @pair[0]<tail>.data<index>, 3, 'following sequence remains outside the goal';

event Nested {
    pattern TOP {
        :!ignore-unexpected
        <open=.event(:type<open>)> ~ <close=.event(:type<close>)> [
            <nested=.TOP> | <text=.event(:type<text>)>
        ]*
    }
}
is feed(Nested, <open close>).elems, 1, 'nullable body allows an empty pair';
my @nested = feed(Nested, <open text open text close text close>);
is @nested.elems, 2, 'recursive TOP emits both independently started nested matches';
my $outer = @nested.first(*.<open>.data<index> == 0);
ok $outer.defined, 'outer pair completes';
is $outer<close>.data<index>, 6, 'outer goal is closed at its own level';
is $outer<nested>.elems, 1, 'recursive repeated capture is an Array even for one match';
is $outer<nested>[0]<open>.data<index>, 2, 'recursive capture retains nested opener';
is $outer<nested>[0]<close>.data<index>, 4, 'recursive capture retains nested closer';
is-deeply $outer<text>.map(*.data<index>).List, (1,5), 'outer body excludes nested contents';
is feed(Nested, <open open close>).first(*.<open>.data<index> == 0), Nil,
    'inner closure cannot also close its parent';

# Compare anchored, strict acceptance with native Raku regex semantics.
grammar Reference { regex TOP { '(' ~ ')' [ <TOP> | 'x' ]* } }
for '', '()', '(x)', '(xx)', '(())', '(()())', '(x(x)x)', '(', ')', '(x', 'x)',
    '(()', '())', '(x))', '(x)x', '(())()', '(x(y))' -> $word {
    my $native = False;
    try { $native = so Reference.parse($word) }
    my @types = $word.comb.map({ $_ eq '(' ?? 'open' !! $_ eq ')' ?? 'close' !! $_ eq 'x' ?? 'text' !! 'other' });
    my @results = feed(Nested, @types);
    my $accepted = so @results.first({ .<open>.data<index> == 0 && .<close>.data<index> == $word.chars - 1 });
    is $accepted, $native, "strict recursive acceptance agrees with Raku for '$word'";
}

# Tilde is a prefix metacharacter over two atoms, not a custom ternary infix.
event PrefixGoal { pattern TOP { :!ignore-unexpected ~ <.event(:type<close>)> <.event(:type<text>)> } }
is feed(PrefixGoal, <text close>).elems, 1, 'tilde does not require a syntactic left operand';
event QuantifiedGoal {
    pattern TOP { :!ignore-unexpected <.event(:type<open>)> ~ <close=.event(:type<close>)> ** 2 <body=.event(:type<text>)>? }
}
is feed(QuantifiedGoal, <open close close>).elems, 1, 'closing and body operands may both be quantified';
is feed(QuantifiedGoal, <open text close close>).elems, 1, 'optional quantified body can consume input';

# A wildcard body may consume a closer and later backtrack; no closer-first cut.
event WildBody {
    pattern TOP { :!ignore-unexpected <open=.event(:type<open>)> ~ <close=.event(:type<close>)> <items=.event>* }
}
my $wild = EEL::Runner.new(:patterns[WildBody]);
$wild.process({type => 'open'});
$wild.process({type => 'text'});
my @short = $wild.process({type => 'close', index => 1});
is @short.elems, 1, 'a greedy wildcard body leaves the closing atom an event';
is @short[0]<items>.elems, 1, 'first body excludes its closing event';
my @long = $wild.process({type => 'close', index => 2});
is @long.elems, 1, 'body can consume an earlier closer when a later closer arrives';
is @long[0]<items>.elems, 2, 'longer conclusion has its own accumulated body';
is @short[0]<items>.elems, 1, 'later path cannot mutate an emitted result';
$wild.finish;

# Defaults, locals, mutable containers and private attributes survive a fork.
my ($initializers, $actions, $defaults) = 0, 0, 0;
event BranchState {
    has $!score = 0;
    method score { $!score }
    pattern TOP(Int $seed = do { $defaults++; 10 }) {
        :!ignore-unexpected
        <first=.event(:type<A>)>
        :my $x = do { $initializers++; $seed };
        :my $state = {count => 0, values => []};
        { $actions++; $!score = 100 }
        [
            { $x++; $state<count>++; $state<values>.push(1); $!score += 1 }
            <.event(:type<B>)>
            |
            { $x += 2; $state<count> += 2; $state<values>.push(2); $!score += 2 }
            <.event(:type<B>)>
        ]
        { $!score += $x + $state<count> + $state<values>.sum }
    }
}
my $branch = EEL::Runner.new(:patterns[BranchState]);
$branch.process({type => 'A'});
is $initializers, 1, 'fork does not replay a local initializer';
is $actions, 1, 'fork does not replay an earlier action';
is $defaults, 2, 'signature default runs only for initial and replacement entry, not for forks';
my @branches = $branch.process({type => 'B'});
is-deeply @branches».score.List, (114,118), 'forks isolate scalars, nested containers and private attributes';
is $defaults, 2, 'resuming a branch does not re-evaluate defaults';

my @goals;
event Diagnostic {
    pattern TOP { :!ignore-unexpected <.event(:type<open>)> ~ <.event(:type<close>)> <items=.event(:type<text>)>* }
    method FAILGOAL($goal) { @goals.push($goal); False }
}
my $diagnostic = EEL::Runner.new(:patterns[Diagnostic]);
$diagnostic.process({type => 'open'});
$diagnostic.process({type => 'text'});
is @goals.elems, 0, 'a live body alternative prevents premature goal failure';
$diagnostic.process({type => 'wrong'});
is @goals.elems, 1, 'exhausting closing alternatives invokes FAILGOAL once';
like @goals[0], /'close'/, 'failure hook receives closing source';
$diagnostic.finish;
is @goals.elems, 1, 'failed goal is not reported again at EOF';
my $unfinished = EEL::Runner.new(:patterns[Diagnostic]);
$unfinished.process({type => 'open'});
$unfinished.finish;
is @goals.elems, 2, 'EOF invokes the failure hook on an unresolved closing goal';
my $cancelled = EEL::Runner.new(:patterns[Diagnostic]);
$cancelled.process({type => 'open'});
$cancelled.close;
is @goals.elems, 2, 'cancellation does not diagnose incomplete input';
my $success = EEL::Runner.new(:patterns[Diagnostic]);
$success.process({type => 'open'});
is $success.process({type => 'close'}).elems, 1, 'successful goal emits normally';
$success.finish;
is @goals.elems, 2, 'successful goal does not trigger failure';

event FatalGoal {
    pattern TOP { :!ignore-unexpected <.event(:type<open>)> ~ <.event(:type<close>)> [] }
    method FAILGOAL($goal) { die "missing goal: $goal" }
}
my $fatal = EEL::Runner.new(:patterns[FatalGoal]);
$fatal.process({type => 'open'});
throws-like { $fatal.finish }, X::AdHoc, message => /'missing goal'/,
    'failure hook may raise a diagnostic at EOF';
my @quits;
EEL::Runner.new(:patterns[FatalGoal]).supply(({type => 'open'},).Supply).tap(
    quit => -> $error { @quits.push($error.message) });
is @quits.elems, 1, 'Supply completion routes a goal error through quit';
like @quits[0], /'missing goal'/, 'stream preserves the hook diagnostic';

# Guard cycles that can recurse/iterate forever without consuming input.
event LeftRecursive { pattern TOP { <.TOP> | <.event> } }
throws-like { EEL::Runner.new(:patterns[LeftRecursive]) }, X::AdHoc,
    message => /'without consuming'/, 'left recursion is rejected';
event Mutual { pattern TOP { <.other> }; pattern other { <.TOP> | <.event> } }
throws-like { EEL::Runner.new(:patterns[Mutual]) }, X::AdHoc,
    message => /'without consuming'/, 'mutual zero-input recursion is rejected';
event NullableLoop { pattern TOP { <.event> [ {} ]* } }
throws-like { EEL::Runner.new(:patterns[NullableLoop]) }, X::AdHoc,
    message => /'Unbounded repetition'/, 'unbounded nullable repetition is rejected';

for 'pattern TOP { <a> ~ }', 'pattern TOP { <a> ~ <b> }', 'pattern TOP { <a> ~~ <b> <c> }' -> $body {
    my $proc = run $*EXECUTABLE, '-Ilib', '-c', '-e', 'use EEL; event Bad { ' ~ $body ~ ' }', :out, :err;
    my $out = $proc.out.slurp(:close);
    my $err = $proc.err.slurp(:close);
    isnt $proc.exitcode, 0, 'malformed goal syntax is rejected';
}
event Many {
    has $.count;
    pattern TOP { :!ignore-unexpected <.event(:type<A>)> <items=.event(:type<B>)>+ { $!count = $<items>.elems } }
}
my $many = EEL::Runner.new(:patterns[Many]);
$many.process({type => 'A'});
my @many;
@many.append($many.process({type => 'B'})) for ^3;
is-deeply @many».count.List, (1,2,3), 'repetition emits every valid conclusion';
is-deeply @many.map(*.<items>.elems).List, (1,2,3), 'earlier repetition captures remain immutable';

# Managed container aliases remain aliases inside each fork.
event Aliased {
    has $.value;
    pattern TOP {
        :!ignore-unexpected <.event(:type<A>)>
        :my %state = count => 0;
        :my $alias = %state;
        [
            { $alias<count>++ } <.event(:type<B>)>
            |
            { $alias<count> += 2 } <.event(:type<B>)>
        ]
        { $!value = %state<count> }
    }
}
my $alias = EEL::Runner.new(:patterns[Aliased]);
$alias.process({type => 'A'});
is-deeply $alias.process({type => 'B'})».value.List, (1,2), 'fork restores aliases of lexical hash containers';

my $signature-defaults = 0;
my @signature-descriptions;
event Signatures {
    has $.description;
    pattern TOP { :!ignore-unexpected <.event(:type<A>)> <child=.child('tag', :extra(7))> }
    pattern child(Str $tag, Int $number = do { $signature-defaults++; 4 }, :$label = 'L', *%options) {
        [ <.event(:type<B>)> | <.event(:type<B>)> ]
        { $!description = "$tag:$number:$label:%options<extra>"; @signature-descriptions.push($!description) }
    }
}
my $signature = EEL::Runner.new(:patterns[Signatures]);
$signature.process({type => 'A'});
is $signature-defaults, 1, 'subpattern default is not re-evaluated by its forks';
my @signature = $signature.process({type => 'B'});
is-deeply @signature-descriptions.List, ('tag:4:L:7', 'tag:4:L:7'),
    'fork preserves positional, named and slurpy subpattern parameters';

event Bounded {
    pattern TOP { :!ignore-unexpected <.event(:type<A>)> <b=.event(:type<B>)> ** 2..3 }
}
my $bounded = EEL::Runner.new(:patterns[Bounded]);
$bounded.process({type => 'A'});
is $bounded.process({type => 'B'}).elems, 0, 'bounded repetition enforces its minimum';
is $bounded.process({type => 'B'})[0]<b>.elems, 2, 'bounded repetition emits its minimum';
is $bounded.process({type => 'B'})[0]<b>.elems, 3, 'bounded repetition emits its maximum';
is $bounded.pending, 0, 'bounded repetition stops after its maximum';
event Zero { pattern TOP { <.event(:type<A>)> <unused=.event> ** 0 } }
is feed(Zero, ['A'])[0]<unused>.elems, 0, 'zero repetitions produce an empty capture array';

# Precompilation retains goal nodes and the state accessors needed for forks.
for ^2 {
    my $proc = run $*EXECUTABLE, '-Ilib', '-It/lib', '-e',
        'use GoalFixture; use EEL::Runner; my $r = EEL::Runner.new(:patterns[GoalFixture::Nested]); $r.process({type => "open"}); say $r.process({type => "close"}).elems; $r.finish', :out, :err;
    my $out = $proc.out.slurp(:close);
    my $err = $proc.err.slurp(:close);
    is $proc.exitcode, 0, 'precompiled recursive pattern executes';
    is $out, "1\n", 'precompiled goal reaches its closing atom';
    is $err, '', 'precompiled execution has no errors';
}
event DeferredGoal {
    pattern TOP {
        :!ignore-unexpected
        :my $target = 1;
        <.event(:type<open>)> ~ <close=.event(:type<close>, :id($target))> [
            <.event(:type<text>)> { $target = 2 }
        ]
    }
}
my $deferred = EEL::Runner.new(:patterns[DeferredGoal]);
$deferred.process({type => 'open'});
$deferred.process({type => 'text'});
is $deferred.process({type => 'close', id => 2}).elems, 1,
    'closing arguments are evaluated after the body, in execution order';
event DeadSelf { pattern TOP { <.TOP> ** 0 <.event> } }
is EEL::Runner.new(:patterns[DeadSelf]).process({type => 'x'}).elems, 1,
    'zero repetitions of a recursive call do not form an executable cycle';
event HostOperators {
    has $.value;
    pattern TOP {
        <.event>
        { my $text = 'a' ~ 'b'; $!value = $text ~~ /^ 'ab' $/ ?? $text !! 'bad' }
    }
}
is EEL::Runner.new(:patterns[HostOperators]).process({type => 'x'})[0].value, 'ab',
    'embedded Raku concatenation and smartmatch keep host semantics';
done-testing;
