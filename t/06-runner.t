use lib 'lib';
use Test;
use EEL;
use EEL::Runner;

my $action-count = 0;
event Flow {
    has $.id;
    has $.label;
    pattern TOP {
        <first=.event(:type<start>)>
        :my $id = $<first>.data<id>;
        <last=.event(:type<finish>, :$id)>
        { $!id = $id; $!label = $<first>.data<label>; $action-count++ }
    }
}
my $runner = EEL::Runner.new(:patterns[Flow]);
is $action-count, 0, 'constructing the runner does not run actions';
is $runner.process({type => 'start', id => 1, label => 'one'}).elems, 0, 'first event suspends at the next wait';
is $runner.pending, 1, 'one started match is stored';
is $runner.process({type => 'start', id => 2, label => 'two'}).elems, 0, 'another start makes an independent continuation';
is $runner.pending, 2, 'two matches coexist';
is $runner.process({type => 'noise'}).elems, 0, 'unexpected events are ignored by default';
is $runner.pending, 2, 'ignored event leaves waits intact';
my @two = $runner.process({type => 'finish', id => 2});
is @two.elems, 1, 'matching finish produces one derived event';
isa-ok @two[0], Flow, 'result has the declared event type';
is @two[0].id, 2, 'dependent argument uses the correct first capture';
is @two[0].label, 'two', 'captures belong to that continuation';
is @two[0]<last>.data<type>, 'finish', 'terminal capture exposes raw event as .data';
is @two[0].data<type>, 'finish', 'result data is the last consumed input';
is $runner.pending, 1, 'completion removes its wait';
my @one = $runner.process({type => 'finish', id => 1});
is @one[0].label, 'one', 'remaining continuation retains its captures and local';
is $runner.pending, 0, 'all finished matches have been removed';
is $runner.process({type => 'finish', id => 1}).elems, 0, 'completed continuation does not emit again';
is $action-count, 2, 'completion actions run exactly once per result';

my $same = EEL::Runner.new(:patterns[Flow]);
$same.process({type => 'start', id => 7, label => 'a'});
$same.process({type => 'start', id => 7, label => 'b'});
is $same.pending, 2, 'equal waiting queries do not overwrite';
my @both = $same.process({type => 'finish', id => 7});
is-deeply @both».label.List, ('a', 'b'), 'one finish completes all applicable independent matches in creation order';
is @both[0]<first>.data<label>, 'a', 'first result capture remains unchanged';
is @both[1]<first>.data<label>, 'b', 'second result capture remains unchanged';

# New continuations wait for another input occurrence, even with equal predicates.
event Double {
    pattern TOP { <first=.event(:type<x>)> <second=.event(:type<x>)> }
}
my $double = EEL::Runner.new(:patterns[Double]);
is $double.process({type => 'x', index => 1}).elems, 0, 'same input cannot fill two consecutive positions';
my @doubles = $double.process({type => 'x', index => 2});
is @doubles.elems, 1, 'second occurrence completes first start';
is @doubles[0]<first>.data<index>, 1, 'first capture references first occurrence';
is @doubles[0]<second>.data<index>, 2, 'second capture references second occurrence';
is $double.pending, 1, 'completion event can also start the next match';
is $double.process({type => 'x', index => 3})[0]<first>.data<index>, 2, 'overlap starts from the previous completion event';

my $calls = 0;
event Nested {
    has $.id;
    pattern TOP {
        <begin=.beginning>
        [ :my $id = $<begin><request>.data<id>; <.ending($id)> ]
        { $!id = $<begin><request>.data<id> }
    }
    pattern beginning { <request=.event(:type<start>)> { $calls++ } }
    pattern ending(Int $id) { <.event(:type<finish>, :$id)> }
}
my $nested = EEL::Runner.new(:patterns[Nested]);
$nested.process({type => 'start', id => 31});
is $calls, 1, 'subpattern action executes after its event';
is $nested.process({type => 'finish', id => 99}).elems, 0, 'subpattern receives its argument';
my @nested = $nested.process({type => 'finish', id => 31});
is @nested[0].id, 31, 'subpattern captures are nested under the call alias';
ok !(@nested[0].hash<ending>:exists), 'silent subpattern is not captured';
is @nested[0]<begin>.data<id>, 31, 'subpattern data is its last consumed event';

# Unexpected handling is lexical and a failing occurrence can start a new match.
event Strict {
    pattern TOP { :!ignore-unexpected <a=.event(:type<A>)> <b=.event(:type<B>)> }
}
my $strict = EEL::Runner.new(:patterns[Strict]);
$strict.process({type => 'A', index => 1});
$strict.process({type => 'A', index => 2});
is $strict.pending, 1, 'unexpected A invalidates the old match and starts another';
is $strict.process({type => 'B'})[0]<a>.data<index>, 2, 'same invalidating event can start the replacement';
event Scoped {
    pattern TOP {
        <.event(:type<A>)>
        [ :!ignore-unexpected <.event(:type<B>)> <.event(:type<C>)> ]
        <.event(:type<D>)>
    }
}
my $scoped = EEL::Runner.new(:patterns[Scoped]);
$scoped.process(%(:type($_))) for <A B C noise>;
is $scoped.pending, 1, 'group restores the previous unexpected-event policy';
is $scoped.process({type => 'D'}).elems, 1, 'sequence completes after leaving strict group';
my $invalidated = EEL::Runner.new(:patterns[Scoped]);
$invalidated.process(%(:type($_))) for <A noise B C D>;
is $invalidated.pending, 0, 'unexpected input inside strict group invalidates the match';

event PolicyCall {
    pattern TOP { <.event(:type<A>)> <.middle> <.event(:type<D>)> }
    pattern middle { :!ignore-unexpected <.event(:type<B>)> }
}
my $policy-call = EEL::Runner.new(:patterns[PolicyCall]);
$policy-call.process(%(:type($_))) for <A B noise>;
is $policy-call.process({type => 'D'}).elems, 1, 'subpattern policy is restored on return';

event Single { pattern TOP { <.event(:type<start>)> } }
my $multiple = EEL::Runner.new(:patterns[Flow, Single]);
is $multiple.process({type => 'start', id => 1}).elems, 1, 'multiple patterns consume the same input independently';
is $multiple.process({type => 'finish', id => 1}).elems, 1, 'other pattern keeps its partial match';

# Supply integration is isolated for each subscription.
my $source = Supplier.new;
my $output = EEL::Runner.new(:patterns[Flow]).supply($source.Supply);
my (@left, @right);
my $left = $output.tap(-> $event { @left.push($event) });
$source.emit({type => 'start', id => 5, label => 'before-right'});
my $right = $output.tap(-> $event { @right.push($event) });
$source.emit({type => 'finish', id => 5});
is @left.elems, 1, 'first tap sees the sequence it started';
is @right.elems, 0, 'later tap does not inherit another tap state';
$left.close;
$source.emit({type => 'start', id => 6, label => 'right-only'});
$source.emit({type => 'finish', id => 6});
is @left.elems, 1, 'closing a tap stops its processing';
is @right.elems, 1, 'other tap keeps processing after cancellation';
$source.done;

my @finite;
my $done = False;
EEL::Runner.new(:patterns[Single]).supply(({type => 'start'}, {type => 'noise'}).Supply)
    .tap(-> $event { @finite.push($event) }, done => { $done = True });
is @finite.elems, 1, 'on-demand input supplies are supported';
ok $done, 'output completes when input completes';

# Unsupported instructions fail during validation, before side effects.
my $unsupported-effects = 0;
event Unsupported {
    pattern TOP { { $unsupported-effects++ } <.event> & <.event> }
}
lives-ok { EEL::Runner.new(:patterns[Unsupported]) }, 'conjunction is validated without executing actions';
is $unsupported-effects, 0, 'validation does not execute pattern actions';
event Partitioned { pattern TOP { :partition{ .<id> } <.event> } }
lives-ok { EEL::Runner.new(:patterns[Partitioned]) }, 'partition routing is supported';
event Missing { pattern TOP { <.unknown> } }
throws-like { EEL::Runner.new(:patterns[Missing]) }, X::AdHoc,
    message => /'unknown'/, 'missing subpattern is rejected';
event Recursive { pattern TOP { <.again> }; pattern again { <.again> } }
throws-like { EEL::Runner.new(:patterns[Recursive]) }, X::AdHoc,
    message => /'Recursive'/, 'zero-input recursive calls are rejected';
event Empty { pattern TOP { } }
throws-like { EEL::Runner.new(:patterns[Empty]) }, X::AdHoc,
    message => /'at least one event'/, 'empty TOP is rejected';
throws-like { EEL::Runner.new(:patterns[]) }, X::AdHoc, 'empty pattern list is rejected';

my $errors = 0;
event Broken {
    pattern TOP { <.event(:type<start>)> { $errors++; die 'action failed' } }
}
my $broken = EEL::Runner.new(:patterns[Broken]);
throws-like { $broken.process({type => 'start'}) }, X::AdHoc,
    message => /'action failed'/, 'action error is propagated';
is $broken.pending, 0, 'failure releases stored continuations';
throws-like { $broken.process({type => 'start'}) }, X::AdHoc,
    message => /'has failed'/, 'failed runner cannot resume partially mutated state';
is $errors, 1, 'failed action is not replayed';
my $closed = EEL::Runner.new(:patterns[Flow]);
$closed.process({type => 'start', id => 3});
$closed.close;
is $closed.pending, 0, 'closing releases pending matches';
throws-like { $closed.process({type => 'finish', id => 3}) }, X::AdHoc,
    message => /'closed'/, 'closed runner cannot process input';
# Query selection is fixed before callbacks mutate any payload in the round.
event Mutator {
    pattern TOP { <.event(:type<start>)> <last=.event(:type<finish>)> { $<last>.data<type> = 'changed' } }
}
event Observer {
    pattern TOP { <.event(:type<start>)> <.event(:type<finish>)> }
}
my $snapshot-runner = EEL::Runner.new(:patterns[Mutator, Observer]);
$snapshot-runner.process({type => 'start'});
is $snapshot-runner.process({type => 'finish'}).elems, 2,
    'all candidate decisions precede callbacks in the same round';

# A repeated capture name accumulates independent terminal matches.
event RepeatedName {
    pattern TOP { <item=.event(:type<A>)> <item=.event(:type<B>)> }
}
my $names = EEL::Runner.new(:patterns[RepeatedName]);
$names.process({type => 'A'});
is-deeply $names.process({type => 'B'})[0]<item>.map(*.data<type>).List,
    ('A', 'B'), 'repeated capture names accumulate in source order';

# A subpattern can finish without consuming input; TOP must still consume input.
event EmptySub {
    pattern TOP { <marker=.marker> <.event(:type<A>)> }
    pattern marker { :my $x = 2; { $x } }
}
is EEL::Runner.new(:patterns[EmptySub]).process({type => 'A'}).elems, 1,
    'zero-input subpattern returns into its caller';

# Configuration errors are detected without executing callbacks.
event Required { pattern TOP(Int $n) { <.event(:$n)> } }
throws-like { EEL::Runner.new(:patterns[Required]) }, X::AdHoc,
    message => /'requires argument'/, 'entry parameters must have defaults';
event AlternateEntry { pattern selected(Int $n = 4) { <.event(:$n)> } }
is EEL::Runner.new(:patterns[AlternateEntry], :rule<selected>).process({n => 4}).elems,
    1, 'alternate entry rule and default parameters work';
for 42, Str -> $invalid {
    throws-like { EEL::Runner.new(:patterns[$invalid]) }, X::AdHoc,
        message => /'type objects'/, 'only event type objects are accepted';
}

# Stream failures terminate the subscription and unsubscribe the source.
my $failing-source = Supplier.new;
my (@stream-errors, @stream-results);
EEL::Runner.new(:patterns[Broken]).supply($failing-source.Supply).tap(
    -> $event { @stream-results.push($event) },
    quit => -> $error { @stream-errors.push($error.message) });
$failing-source.emit({type => 'start'});
$failing-source.emit({type => 'start'});
is @stream-errors.elems, 1, 'action failure quits output exactly once';
like @stream-errors[0], /'action failed'/, 'output carries the original error';
is @stream-results.elems, 0, 'failed event emits no partial result';
my $upstream-source = Supplier.new;
my $upstream-error;
EEL::Runner.new(:patterns[Flow]).supply($upstream-source.Supply).tap(
    quit => -> $error { $upstream-error = $error });
$upstream-source.emit({type => 'start', id => 1});
my $original-error = X::AdHoc.new(payload => 'upstream failed');
$upstream-source.quit($original-error);
ok $upstream-error === $original-error, 'upstream failure propagates unchanged';

# Closing in the tap callback prevents eager on-demand input from running actions.
my $before-cancel = $action-count;
EEL::Runner.new(:patterns[Flow]).supply(
    ({type => 'start', id => 2}, {type => 'finish', id => 2}).Supply).tap(
    tap => -> $handle { $handle.close });
is $action-count, $before-cancel, 'immediate cancellation prevents eager input processing';

# Recursive calls fail without clearing or unlocking an outer round accidentally.
my $reentrant;
my @recursive-errors;
event Reentrant {
    pattern TOP {
        <.event(:type<A>)>
        {
            try {
                $reentrant.process({type => 'noise'});
                CATCH { default { @recursive-errors.push(.message) } }
            }
        }
        <.event(:type<B>)>
    }
}
$reentrant = EEL::Runner.new(:patterns[Reentrant]);
$reentrant.process({type => 'A'});
like @recursive-errors[0], /'already running'/, 'recursive process is rejected';
is $reentrant.process({type => 'B'}).elems, 1, 'caught recursion error leaves outer continuation intact';

# Concurrent manual callers are serialized without losing any starts.
my $concurrent = EEL::Runner.new(:patterns[Flow]);
await (^8).map(-> $id { start { $concurrent.process({type => 'start', :$id}) } });
is $concurrent.pending, 8, 'concurrent calls retain independent waits';
my @parallel = await (^8).map(-> $id { start { $concurrent.process({type => 'finish', :$id}) } });
is $concurrent.pending, 0, 'concurrent finishes remove all waits';
is @parallel.map(*.elems).sum, 8, 'concurrent processing emits each completion once';
for ^2 {
    my $proc = run $*EXECUTABLE, '-Ilib', '-It/lib', '-e',
        'use RunnerFixture; use EEL::Runner; my $runner = EEL::Runner.new(:patterns[RunnerFixture::Flow]); $runner.process({type => "start", id => 17}); say $runner.process({type => "finish", id => 17})[0].id', :out, :err;
    my $out = $proc.out.slurp(:close);
    my $err = $proc.err.slurp(:close);
    is $proc.exitcode, 0, 'runner executes patterns from a precompiled module';
    is $out, "17\n", 'precompiled callbacks retain local and capture bindings';
    is $err, '', 'precompiled execution produces no errors';
}
done-testing;
