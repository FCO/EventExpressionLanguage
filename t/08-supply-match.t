use lib 'lib';
use Test;
use EEL;
use Event;

my $actions = 0;
event Session {
    has $.id;
    pattern TOP {
        <first=.event(:type<start>)>
        <last=.event(:type<finish>, :id($<first>.data<id>))>
        { $!id = $<first>.data<id>; $actions++ }
    }
}
event Flagged {
    has $.id;
    pattern TOP { <session=.event(:type(Session), :id(42))> { $!id = $<session>.data.id } }
}
event Single { pattern TOP { <.event(:type<start>)> } }

my @input = {type => 'start', id => 42}, {type => 'noise'}, {type => 'finish', id => 42};
sub collect(Supply $output --> List) {
    my @out;
    $output.tap(-> $event { @out.push($event) });
    @out.List
}
my @default = collect(@input.Supply.match(Session));
is @default.elems, 1, 'match emits derived events by default';
isa-ok @default[0], Session, 'result is an instance of the event type';
is @default[0].id, 42, 'runner evaluates captures and actions';
is collect(@input.Supply.match(Session, :!reemit)).elems, 1, 'explicit False disables original events';
is collect(@input.Supply.match(Session, :reemit([]))).elems, 1, 'empty selector list disables original events';
my @all = collect(@input.Supply.match(Session, :reemit));
is @all.elems, 4, 'Bool True emits every input and each result';
ok @all[0] === @input[0], 'first original preserves identity';
ok @all[1] === @input[1], 'unmatched input is reemitted too';
ok @all[2] === @input[2], 'completion input is emitted before its derived result';
isa-ok @all[3], Session, 'derived result follows its completion input';
my @selected = collect(@input.Supply.match(Session, :reemit<noise finish>));
is @selected.elems, 3, 'name list selects only matching originals';
is-deeply @selected.grep(Associative)».<type>.List, ('noise','finish'), 'name selection uses type field';
is @selected[2].id, 42, 'filtering originals does not filter recognition input';
is collect(@input.Supply.match(Session, :reemit(['finish','finish']))).elems, 2,
    'duplicate selectors never duplicate an original';

my @multi = collect(@input.Supply.match(Session, Single));
is-deeply @multi.map(*.^name).List, ('Single','Session'), 'multiple patterns share one input subscription';
my @no-feedback = collect(@input.Supply.match(Session, Flagged));
is @no-feedback.elems, 1, 'derived output is not fed to another pattern in the same call';
isa-ok @no-feedback[0], Session, 'only the directly matched type is emitted';
my @pipeline = collect(@input.Supply.match(Session).match(Flagged));
is @pipeline.elems, 1, 'chained match recognizes derived event objects';
isa-ok @pipeline[0], Flagged, 'second stage creates its declared type';
is @pipeline[0].id, 42, 'second stage can query object attributes';
isa-ok @pipeline[0]<session>.data, Session, 'primitive capture keeps the original derived instance';
my @preserved = collect(@input.Supply.match(Session).match(Flagged, :reemit(Session)));
is-deeply @preserved.map(*.^name).List, ('Session','Flagged'), 'single type selector reemits a pipeline input';
ok @preserved[1]<session>.data === @preserved[0], 'reemitted and captured instance identities agree';
is collect(@input.Supply.match(Session).match(Flagged, :reemit<Session>)).elems, 2,
    'type names can select derived instances';
is collect(@input.Supply.match(Session).match(Flagged, :reemit(Session, Flagged))).elems, 2,
    'list of type objects is supported';

class Reading { has $.value }
class Warm is Reading { }
event Hot {
    has $.value;
    pattern TOP { <reading=.event(:type(Reading), :value({'>=' => 40}))> { my $reading = $<reading>.data; $!value = $reading ~~ Associative ?? $reading<value> !! $reading.value } }
}
my $warm = Warm.new(:value(45));
my @typed = collect(($warm,).Supply.match(Hot, :reemit(Reading)));
is @typed.elems, 2, 'type selectors support ordinary objects and inheritance';
ok @typed[0] === $warm, 'ordinary object is not replaced by its matching view';
is @typed[1].value, 45, 'public object attributes can satisfy query predicates';
my %tagged = type => 'Reading', value => 45;
my @tagged = collect((%tagged,).Supply.match(Hot, :reemit(Reading)));
is @tagged.elems, 2, 'type selectors match exact type names on tagged hashes';
ok @tagged[0] === %tagged, 'tagged hash identity is preserved';
isa-ok @tagged[1], Hot, 'type-object condition recognizes a tagged raw event';
my @typed-name = collect(($warm,).Supply.match(Hot, :reemit<Warm>));
is @typed-name.elems, 2, 'object class name can be selected as a string';
class Tagged { has $.type; has $.value }
event TaggedMatch { pattern TOP { <.event(:type<sensor>, :value(3))> } }
my $tagged-object = Tagged.new(:type<sensor>, :value(3));
is collect(($tagged-object,).Supply.match(TaggedMatch, :reemit<sensor>)).elems, 2,
    'explicit type accessor provides a string event tag';
event ByClass { pattern TOP { <.event(:type(Tagged))> } }
is collect(($tagged-object,).Supply.match(ByClass)).elems, 1,
    'class conditions retain object identity even with a custom type tag';
event Number { pattern TOP { <.event(:type(Int))> } }
is collect((5,).Supply.match(Number, :reemit(Int))).elems, 2, 'defined scalar events can be selected by type';

# Configuration is eager; input, defaults and actions remain lazy until a tap.
my $subscriptions = 0;
my $source = Supply.on-demand(-> $producer {
    $subscriptions++;
    $producer.emit($_) for @input;
    $producer.done;
});
my $before = $actions;
my $output = $source.match(Session, :reemit);
is $subscriptions, 0, 'match does not subscribe while constructing the output';
is $actions, $before, 'match does not run pattern actions while constructing output';
is collect($output).elems, 4, 'first tap processes its input';
is $subscriptions, 1, 'reemit uses one input subscription';
is collect($output).elems, 4, 'second tap creates fresh matching state';
is $subscriptions, 2, 'on-demand source is subscribed once per output tap';
is $actions, $before + 2, 'each tap runs its own match';

my $live = Supplier.new;
my $shared-output = $live.Supply.match(Session, :reemit(Session));
my (@left, @right);
my $left = $shared-output.tap(-> $event { @left.push($event) });
$live.emit({type => 'start', id => 1});
my $right = $shared-output.tap(-> $event { @right.push($event) });
$live.emit({type => 'finish', id => 1});
is @left.elems, 1, 'live first subscriber completes its match';
is @right.elems, 0, 'late subscriber does not inherit previous state';
$left.close;
$live.emit({type => 'start', id => 2});
$live.emit({type => 'finish', id => 2});
is @left.elems, 1, 'cancelled subscriber stops';
is @right.elems, 1, 'other subscriber continues after cancellation';
$live.done;

my $completed = False;
@input.Supply.match(Session).tap(done => { $completed = True });
ok $completed, 'input completion completes the output';
my $bad-source = Supplier.new;
my $original = X::AdHoc.new(payload => 'input failed');
my $seen-error;
$bad-source.Supply.match(Session, :reemit).tap(quit => -> $exception { $seen-error = $exception });
$bad-source.quit($original);
ok $seen-error === $original, 'input error identity propagates';
event Broken { pattern TOP { <.event> { die 'pattern failed' } } }
my (@partial, @errors);
({type => 'x'},).Supply.match(Broken, :reemit).tap(
    -> $event { @partial.push($event) }, quit => -> $error { @errors.push($error.message) });
is @partial.elems, 0, 'failing input emits neither an original nor a partial derived result';
like @errors[0], /'pattern failed'/, 'action error quits the matching Supply';

# Reemission callbacks cannot change matching decisions for the current input.
event Identified {
    has $.id;
    pattern TOP { <input=.event(:type<start>)> { $!id = $<input>.data<id> } }
}
my %mutable = type => 'start', id => 42;
my $identified;
(%mutable,).Supply.match(Identified, :reemit).tap(-> $event {
    if $event ~~ Associative { $event<id> = 99 } else { $identified = $event }
});
is $identified.id, 42, 'recognition runs before reemitted-input callbacks';
is %mutable<id>, 99, 'reemission still passes the original object';

# Reentrant input is queued after all output for the current event.
my $reentrant = Supplier.new;
my @order;
$reentrant.Supply.match(Single, :reemit).tap(-> $event {
    if $event ~~ Associative {
        @order.push('raw-' ~ $event<id>);
        $reentrant.emit({type => 'start', id => 2}) if $event<id> == 1;
    } else { @order.push('derived-' ~ $event.data<id>) }
});
$reentrant.emit({type => 'start', id => 1});
is-deeply @order.List, ('raw-1','derived-1','raw-2','derived-2'), 'original and derived outputs form one ordered batch';
$reentrant.done;

my $cancellation-actions = $actions;
@input.Supply.match(Session, :reemit).tap(tap => -> $handle { $handle.close });
is $actions, $cancellation-actions, 'immediate cancellation skips matching actions';
event OtherEntry { pattern selected { <.event(:type<noise>)> } }
is collect(@input.Supply.match(OtherEntry, :rule<selected>)).elems, 1, 'rule option is forwarded';
throws-like { @input.Supply.match() }, X::AdHoc, message => /'at least one'/, 'at least one pattern is required';
throws-like { @input.Supply.match('Session') }, X::AdHoc, message => /'type objects'/, 'patterns are types, not names';
throws-like { @input.Supply.match(Session.new) }, X::AdHoc, message => /'type objects'/, 'pattern instances are rejected';
throws-like { @input.Supply.match(Session, :unknown) }, X::AdHoc, message => /'Unknown Supply.match'/, 'unknown options are rejected';
for 42, [42], Session.new -> $selection {
    throws-like { @input.Supply.match(Session, :reemit($selection)) }, X::AdHoc,
        message => /':reemit expects'/, 'invalid reemit selection is rejected before tapping';
}
is 'abc'.match(/b/).Str, 'b', 'ordinary string matching is unaffected';

# The method follows augment semantics; the slang remains separately lexical.
my $global = run $*EXECUTABLE, '-Ilib', '-e',
    'my $kind; { use EEL; event Local { pattern TOP { <.event> } }; $kind = Local }; say Supply.^find_method("match").package.^name; say ({a => 1},).Supply.match($kind).^name', :out, :err;
my $global-out = $global.out.slurp(:close);
my $global-err = $global.err.slurp(:close);
is $global.exitcode, 0, 'Supply method survives the lexical importing scope';
is $global-out, "Supply\nSupply\n", 'augment installs the method on Supply itself';
is $global-err, '', 'no MONKEY-TYPING pragma is needed at the call site';

for ^2 {
    my $proc = run $*EXECUTABLE, '-Ilib', '-It/lib', '-e',
        'use MatchFixture; output(({type => "ping"},).Supply).tap(-> $event { say $event.^name })', :out, :err;
    my $out = $proc.out.slurp(:close);
    my $err = $proc.err.slurp(:close);
    is $proc.exitcode, 0, 'matching works through a precompiled consumer module';
    is $out, "MatchFixture::Ping\n", 'precompiled client retains the Supply extension';
    is $err, '', 'precompiled matching produces no error';
}
my @multi-all = collect(@input.Supply.match(Session, Single, :reemit));
is @multi-all.grep(Associative).elems, 3, 'multiple patterns still reemit each original only once';
is @multi-all.grep(Event).elems, 2, 'all derived types are emitted independently of original filtering';

# Reemit reuses the matching snapshot and cannot trigger more accessor reads.
my $reads = 0;
class Measured {
    has $.type = 'measurement';
    has $.value;
    method value { $reads++; $!value }
}
event MeasuredMatch { pattern TOP { <.event(:type<measurement>, :value(7))> } }
my $measured = Measured.new(:value(7));
is collect(($measured,).Supply.match(MeasuredMatch)).elems, 1, 'object input matches without reemit';
is $reads, 1, 'accessor view is evaluated once for that input';
is collect(($measured,).Supply.match(MeasuredMatch, :reemit<measurement>)).elems, 2,
    'string selection reuses object input view';
is $reads, 2, 'reemission does not add accessor side effects';

event Rename {
    pattern TOP { <input=.event(:type<before>)> { $<input>.data<type> = 'after' } }
}
my %renamed = type => 'before';
my @renamed = collect((%renamed,).Supply.match(Rename, :reemit<before>));
is @renamed.elems, 2, 'reemission selects using the input type before matching actions';
ok @renamed[0] === %renamed, 'renamed original keeps its identity';
is @renamed[0]<type>, 'after', 'mutations to the raw payload remain visible to its owner';

event MissingGoal {
    pattern TOP { :!ignore-unexpected <.event(:type<open>)> ~ <.event(:type<close>)> [] }
    method FAILGOAL($goal) { die 'missing close' }
}
my @goal-errors;
({type => 'open'},).Supply.match(MissingGoal).tap(quit => -> $error { @goal-errors.push($error.message) });
like @goal-errors[0], /'missing close'/, 'match signals end of input to delimiter goals';
my $goal-source = Supplier.new;
my $goal-tap = $goal-source.Supply.match(MissingGoal).tap;
$goal-source.emit({type => 'open'});
lives-ok { $goal-tap.close }, 'cancelling match does not signal a missing goal';
$goal-source.done;

my @invalid-input;
(Nil,).Supply.match(Single).tap(quit => -> $error { @invalid-input.push($error.message) });
is @invalid-input.elems, 1, 'undefined input fails the output Supply';
like @invalid-input[0], /'defined values'/, 'undefined input has an explicit diagnostic';
done-testing;
