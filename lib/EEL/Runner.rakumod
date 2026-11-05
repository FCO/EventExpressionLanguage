use nqp;
use Event;
use EEL::Definition;
use EEL::Query;
use EEL::MemoryStorage;
use EEL::Continuation;
use EEL::State;
use EEL::Input;
use EEL::Reemit;
use EEL::Condition;
use EEL::InputQueue;
use EEL::RetainedStore;
use EEL::Assertion;
use EEL::Absence;
unit class EEL::Runner;

class Window { has Int $.id; has Int $.duration; has $.start is rw }
class MarkChoice { has Int $.id; has Int $.rank }
class Unordered { has @.pending }
class AnyQuery is EEL::Query { has @.queries; method matches($view) { so @!queries.first({ .matches($view) }) } }
class EndCapture { has Int $.index; has Hash $.before; has @.positions; has @.array-names; has @.array-indices; has Bool $.ignore; has Int $.window-count = 0; has Hash $.partition is rw = {} }
class Restore { has Bool $.ignore is required; has Int $.window-count = 0; has Hash $.partition is rw = {} }
class Repeat {
    has EEL::Definition $.node is required;
    has Int $.count = 0;
}
class Goal {
    has Int $.id is required;
    has Event $.owner is required;
    has Str $.source is required;
    has Bool $.closing is rw = False;
}
class Closing { has Int $.id is required }
class EndGoal { has Int $.id is required }

has Mu @.patterns is required;
has Str $.rule = 'TOP';
has Real $.lateness = 0;
has Bool $.record-emissions = False;
has Int $!lateness-ns;
has FatRat $!maximum-time;
has FatRat $!watermark;
has EEL::InputQueue $!inbox .= new;
has @!emissions;
has Int $!input-order = 0;
has Int $!event-order = 0;
has Int $!cursor = 0;
has Bool $!uses-history = False;
has %!tape;
has @!tape-order;
has Int $!result-order = 0;
has Int $!next-window = 0;
has Int $!next-selection = 0;
has %!selection-rekeys;
has %!selected;
has FatRat $!arrival;
has EEL::MemoryStorage $!storage .= new;
has @!starters;
has @!starter-ids;
has EEL::MemoryStorage $!starter-storage .= new;
has Int $!starter-candidates = 0;
has Int $!forks = 0;
has Int $!rematerialized = 0;
has Int $!shared-definitions = 0;
has Int $!copied = 0;
has Bool $!reference-forks = False;
method EEL-reference-forks(Bool $enabled = True) { $!reference-forks=$enabled }
has Int $!retained-checked = 0;
method EEL-work { %(starters=>$!starter-candidates,forks=>$!forks,rematerialized=>$!rematerialized,retained=>$!retained-checked,shared=>$!shared-definitions,copied=>$!copied,history=>%!tape.elems) }

has Bool $!initialized = False;
has Bool $!closed = False;
has Bool $!failed = False;
has Bool $!processing = False;
has Lock $!lock .= new;
has Int $!next-goal = 0;
has Int $!next-choice = 0;
has %!committed;
has %!rekeys;
has %!partition-keys;
has %!partition-values;
has Bool $!linear-search = False; # differential-test oracle, not a Supply option
has Int $!candidate-total = 0;
has EEL::RetainedStore $!retained .= new;
has Bool $!reference-retained = False;
method EEL-reference-retained(Bool $enabled = True) { $!reference-retained=$enabled }
has SetHash $!satisfied .= new;
has %!goal-failures;
has EEL::Input::Snapshot $!input-view;

sub event-time(Instant:D $instant --> FatRat) { ($instant - Instant.from-posix(0)).FatRat * 1_000_000_000 }
sub nodes(EEL::Definition $node) {
    gather { take $node; for $node.children { .take for nodes($_) } }
}
sub nullable($node, %nullable --> Bool) {
    given $node.kind {
        when 'assertion' { True }
        when 'call' { $node.name ne 'event' && (%nullable{$node.name} // False) }
        when 'alternative' | 'ordered-alternative' { so $node.children.first({ nullable($_, %nullable) }) }
        when 'repeat' { $node.properties<min> == 0 || nullable($node.children[0], %nullable) }
        when 'window-start' | 'partition' | 'local' | 'code' | 'ignore-unexpected' { True }
        default { so $node.children.map({ nullable($_, %nullable) }).all }
    }
}
# Entry rules may be nullable, but must still have a consuming path.
sub productive($node, %rules --> Bool) {
    given $node.kind {
        when 'assertion' { False }
        when 'call' { $node.name eq 'event' || (%rules{$node.name} // False) }
        when 'repeat' { $node.properties<max> > 0 && productive($node.children[0], %rules) }
        default { so $node.children.first({ productive($_, %rules) }).defined }
    }
}
sub initial-calls($node, %nullable --> List) {
    given $node.kind {
        when 'call' { return $node.name eq 'event' ?? ().List !! ($node.name,).List }
        when 'alternative' | 'ordered-alternative' | 'unordered' | 'shuffle' { return $node.children.map({ initial-calls($_, %nullable) }).flat.List }
        when 'repeat' { return $node.properties<max> == 0 ?? ().List !! initial-calls($node.children[0], %nullable) }
    }
    my @calls;
    my @children = $node.kind eq 'goal' ?? $node.children.reverse !! $node.children;
    for @children -> $child {
        @calls.append(initial-calls($child, %nullable));
        last unless nullable($child, %nullable);
    }
    @calls.List
}

sub candidates($method) {
    return () unless $method;
    return ($method,) if $method.^can('definition');
    return () unless $method.^can('candidates');
    $method.candidates.grep({ .^can('definition') }).List
}
sub family-rules($type, $rule) {
    my $method = $type.^find_method($rule);
    return () unless $method && $method.^can('definition') && $method.definition.kind eq 'proto';
    my %seen;
    $type.^methods.grep({ candidates($_).first({ (.definition.properties<family> // '') eq $rule }).defined })
        .map(*.name).grep({ !%seen{$_}++ }).List
}
sub compiled-definition($type, $rule) {
    my @family = family-rules($type,$rule);
    my @candidates = candidates($type.^find_method($rule));
    die "Unknown compiled subpattern '$rule' in {$type.^name}" unless @candidates;
    if @candidates[0].definition.kind eq 'proto' && !@family {
        @candidates = $type.^find_method($rule).candidates.grep({ .^can('definition') && .definition.kind ne 'proto' });
        die "Proto pattern '$rule' has no candidates" unless @candidates;
    }
    if @family {
        die "Proto pattern '$rule' has no candidates" unless @family;
        return EEL::Definition.new(:kind<alternative>, :children(@family.map({ EEL::Definition.new(:kind<call>, :name($_)) })));
    }
    return @candidates[0].definition if @candidates.elems == 1;
    EEL::Definition.new(:kind<alternative>, :children(@candidates.map(*.definition)))
}
submethod TWEAK() {
    die 'lateness must be finite, nonnegative and representable in nanoseconds' unless 0 <= $!lateness < Inf && ($!lateness.FatRat * 1_000_000_000).denominator == 1;
    $!lateness-ns = ($!lateness.FatRat * 1_000_000_000).Int;
    die 'EEL::Runner needs at least one event type' unless @!patterns;
    for @!patterns -> $type {
        die 'EEL::Runner patterns must be Event type objects'
            unless !$type.DEFINITE && $type.^isa(Event);
        my $method = $type.^find_method($!rule);
        compiled-definition($type,$!rule);
        if $method.^can('definition') && $method.definition.kind ne 'proto' {
            for $method.signature.params -> $parameter {
                die "Entry pattern '$!rule' requires argument {$parameter.name}"
                    unless $parameter.invocant || $parameter.optional || $parameter.slurpy;
            }
        }
        my %rules;
        my @todo = $!rule;
        while @todo {
            my $rule = @todo.shift;
            next if %rules{$rule}:exists;
            %rules{$rule} = compiled-definition($type,$rule);
            for nodes(%rules{$rule}) -> $node {
                die "Runner does not support '{$node.kind}' yet at line {$node.line}, column {$node.column}"
                    unless $node.kind eq any(<pattern sequence ordered unordered group capture-group partition window-start shuffle assertion call local code ignore-unexpected alternative ordered-alternative repeat goal>);
                $!uses-history=True if $node.kind eq 'assertion';
                @todo.push($node.name) if $node.kind eq 'call' && $node.name ne 'event';
            }
        }
        my %nullable = %rules.keys.map({$_ => False});
        loop {
            my $changed = False;
            for %rules.kv -> $name, $definition {
                if !%nullable{$name} && nullable($definition, %nullable) {
                    %nullable{$name} = True;
                    $changed = True;
                }
            }
            last unless $changed;
        }
        my %graph = %rules.map({ .key => initial-calls(.value, %nullable) });
        sub check-cycle($name, @path) {
            die "Recursive subpattern '$name' can recurse without consuming an event"
                if $name eq any(@path);
            check-cycle($_, [|@path, $name]) for %graph{$name}.list;
        }
        check-cycle($_, []) for %rules.keys;
        my %productive = %rules.keys.map({ $_ => False });
        loop {
            my $changed = False;
            for %rules.kv -> $name,$definition {
                if !%productive{$name} && productive($definition,%productive) {
                    %productive{$name}=True;
                    $changed=True;
                }
            }
            last unless $changed;
        }
        die "Entry pattern '$!rule' must consume at least one event" unless %productive{$!rule};
        for %rules.values -> $definition {
            for nodes($definition).grep(*.kind eq 'repeat') -> $repeat {
                die 'Unbounded repetition must consume an event in its body'
                    if $repeat.properties<max> == Inf && nullable($repeat.children[0], %nullable);
            }
        }
    }
}

method !frame(Mu $type, Str $rule, Capture $args, Mu :$anchor, :$anchor-time, UInt :$anchor-index, Hash :$saved-partition = {}, Int :$saved-window-count = 0, Str :$capture = '', Bool :$saved-ignore = True) {
    my %captures;
    my $context = $type.new(:$rule, :args($args), :hash(%captures));
    $context.EEL-captures(%captures);
    if $anchor.defined { $context.EEL-accept($anchor, :index($anchor-index)); $context.timestamp=$anchor-time }
    my $method = $type.^find_method($rule);
    my $candidate;
    my $definition;
    my @family = family-rules($type,$rule);
    if @family {
        die "Arguments do not satisfy proto pattern '$rule'" unless $method.signature.ACCEPTS(\($context, |$args));
        $definition = EEL::Definition.new(:kind<pattern>, :name($rule), :properties({forkable-signature=>True, proto-family=>True}),
            :arguments-code({ $args }), :children[EEL::Definition.new(:kind<alternative>, :children(@family.map({
                EEL::Definition.new(:kind<call>, :name($_), :code({ $args }))
            })))]);
    } else {
        if $method.^can('definition') && $method.definition.kind ne 'proto' {
            $candidate = $method;
            $definition = $candidate.instantiate($context, |$args);
        } else {
            $definition = $method($context, |$args);
            $candidate = $method.candidates.first({ .^can('definition') && .definition === $definition.origin });
            die "Dispatcher for '$rule' selected a non-pattern candidate" unless $candidate.defined;
        }
    }
    $context.EEL-args($definition.arguments-code.());
    my @layout=nodes($definition);
    my $share-definition=!$context.args.list.elems && !$context.args.hash.elems && !@layout.first({
        .kind eq any(<code local partition assertion>) || (.kind eq 'call' && (.name ne 'event' || !.properties<context-free>))
    }).defined;
    EEL::Continuation::Frame.new(:@layout,:$share-definition,:$context, :$definition, :$candidate, :captures(%captures), :todo[$definition], :$capture, :$saved-ignore, :$saved-partition, :$saved-window-count)
}
method !start(Mu $type --> List) {
    my $frame = self!frame($type, $!rule, \());
    my $continuation = EEL::Continuation.new(:result($frame.context), :frames[$frame]);
    self!seek($continuation)
}

sub capture($frame, Str $name, Mu $match) {
    return unless $name.chars;
    if $frame.captures{$name}:exists {
        my $previous = $frame.captures{$name};
        $frame.captures{$name} = $previous ~~ Array ?? [|$previous, $match] !! [$previous, $match];
    } else {
        $frame.captures{$name} = $match;
    }
}
sub array-captures($frame, $body) {
    for nodes($body).grep(*.kind eq 'capture-group') -> $group {
        my $index = $group.properties<index>;
        my $key = '@pos:' ~ $index;
        unless $frame.arrays{$key}:exists {
            $frame.arrays{$key} = True;
            my @values = $frame.context.list;
            @values[$index] = @values[$index].defined ?? [@values[$index]] !! [];
            $frame.context.EEL-positions(@values);
        }
    }
    for nodes($body).grep(*.kind eq 'call') -> $call {
        my $name = $call.properties<capture> // '';
        next unless $name.chars;
        unless $frame.arrays{$name}:exists {
            $frame.arrays{$name} = True;
            $frame.captures{$name} = ($frame.captures{$name}:exists) ?? [$frame.captures{$name}] !! [];
        }
    }
}

# Rebinding a fresh factory creates new scalar containers. Read/write accessors
# restore local values; neither actions nor initializers are replayed.
method !fork(EEL::Continuation:D $old --> EEL::Continuation) {
    $!forks++;
    my $copy = EEL::State.new;
    my $result = $copy.copy($old.result);
    my @frames;
    my %allnodes;
    for $old.frames -> $frame {
        die 'Cannot fork an anonymous or destructured pattern signature'
            unless $frame.definition.properties<forkable-signature>;
        my $context = $copy.copy($frame.context);
        my $args = $copy.copy($frame.definition.arguments-code.());
        $context.EEL-args($args);
        my $shared=$frame.share-definition && !$!reference-forks;
        $shared ?? $!shared-definitions++ !! $!rematerialized++;
        my $definition = $shared ?? $frame.definition
            !! ($frame.candidate.defined
                ?? $frame.candidate.instantiate($context, |$args)
                !! self!frame($context.WHAT,$context.rule,$args).definition);
        my %captures := $context.EEL-hash;
        my @before = $frame.layout;
        my @after = $shared ?? $frame.layout !! nodes($definition);
        my %map;
        unless $shared {
            for @before Z @after -> ($before, $after) {
                %map{nqp::objectid($before).Str} = $after;
                %allnodes{nqp::objectid($before).Str} = $after;
                $after.write-state.($copy.copy($before.read-state.())) if $before.read-state.defined;
            }
        }
        my @todo = $frame.todo.map(-> $instruction {
            $instruction ~~ EEL::Definition ?? ($shared ?? $instruction !! %map{nqp::objectid($instruction).Str})
                !! $instruction ~~ Repeat ?? $instruction.clone(:node($shared ?? $instruction.node !! %map{nqp::objectid($instruction.node).Str}))
                !! $instruction ~~ EndCapture ?? $instruction.clone(:before($copy.copy($instruction.before)), :positions($copy.copy($instruction.positions.Array)))
                !! $instruction ~~ Unordered ?? $instruction.clone(:pending($instruction.pending.map({ $shared ?? $_ !! %map{nqp::objectid($_).Str} })))
                !! $instruction.clone
        });
        @frames.push(EEL::Continuation::Frame.new(:layout(@after),:share-definition($frame.share-definition),:$context, :$definition, :candidate($frame.candidate), :captures(%captures),
            :arrays($copy.copy($frame.arrays)), :initialized($frame.initialized.clone), :@todo, :capture($frame.capture), :saved-ignore($frame.saved-ignore), :saved-partition($frame.saved-partition), :saved-window-count($frame.saved-window-count)));
    }
    my %partition-remaps;
    sub remap(%partition) {
        return {} unless %partition;
        my $id = nqp::objectid(%partition).Str;
        return %partition-remaps{$id} if %partition-remaps{$id}:exists;
        my %p = %partition;
        %partition-remaps{$id} = %p;
        %p<node> = %allnodes{nqp::objectid(%p<node>).Str} // %p<node>;
        %p<key> = $copy.copy(%p<key>);
        %p
    }
    for @frames -> $frame {
        $frame.saved-partition = remap($frame.saved-partition);
        for $frame.todo -> $instruction {
            $instruction.partition = remap($instruction.partition) if $instruction ~~ Restore|EndCapture;
        }
    }
    my $fork = EEL::Continuation.new(:$result, :@frames, :branch-mode($old.branch-mode), :shuffle-base($copy.copy($old.shuffle-base)), :query($old.query),
        :selections($old.selections.map(*.Array).Array), :shuffle($old.shuffle.map({ self!fork($_) }).Array), :shuffle-order($old.shuffle-order.Array), :shuffle-locals($old.shuffle-locals.Array), :choices($old.choices.clone), :partition(remap($old.partition)), :done($old.done), :completed-at($old.completed-at), :result-order($old.result-order), :consumed($old.consumed), :ignore-unexpected($old.ignore-unexpected),
        :windows($old.windows.map(*.clone).Array),
        :goals($old.goals.map({ .clone(:owner($copy.copy(.owner))) }).Array));
    $!copied+=$copy.copied;
    sub gate($g) {
        $g.clone(:owner($copy.copy($g.owner)), :seeds($g.seeds.map({ self!fork($_) }).Array),
            :active($g.active.map({ self!fork($_) }).Array), :tried($g.tried.clone), :windows($g.windows.map(*.clone).Array))
    }
    $fork.positive=gate($old.positive) if $old.positive.defined;
    $fork.negatives=$old.negatives.map({ gate($_) }).Array;
    $fork.terminal=$old.terminal;
    $fork.seen-through=$old.seen-through; $fork.identity-bound=$old.identity-bound;
    $fork.used-events=$old.used-events.clone; $fork.blocked-events=$old.blocked-events.clone;
    $fork.first-time=$old.first-time; $fork.consume-base=$old.consume-base;
    $fork.deferred=$old.deferred.map({ %allnodes{nqp::objectid($_).Str} // $_ }).Array;
    my $old-id=nqp::objectid($old).Str;
    %!partition-keys{nqp::objectid($fork).Str} = %!partition-keys{$old-id} if %!partition-keys{$old-id}:exists;
    $fork
}

# Insert each choice before forking so that its instructions are remapped to
# the fresh factory too; inserting an old node afterwards would share closures.
method !choices($current, @choices --> List) {
    return ().List unless @choices;
    if @choices.elems == 1 {
        $current.frames.tail.todo.unshift(|@choices[0]);
        return ($current,).List;
    }
    my @branches;
    for @choices -> $instructions {
        $current.frames.tail.todo.unshift(|$instructions);
        @branches.push(self!fork($current));
        $current.frames.tail.todo.shift for ^$instructions.elems;
    }
    @branches.List
}

# Expand epsilon paths to an immutable round frontier. Every branch owns its
# callbacks and match contexts before any branch executes its next instruction.
sub consumes-node($node) {
    return False if $node.kind eq 'assertion';
    return True if $node.kind eq 'call';
    so $node.children.first({ consumes-node($_) }).defined
}
sub future-event($c) {
    so $c.frames.first(-> $frame {
        $frame.todo.first(-> $n {
            $n ~~ EEL::Definition ?? consumes-node($n)
                !! $n ~~ Repeat ?? $n.count < $n.node.properties<max>
                !! $n ~~ Unordered ?? so $n.pending
                !! False
        }).defined
    }).defined
}
method !seek(EEL::Continuation:D $continuation --> List) {
    my @work = $continuation;
    my @frontier;
    while @work {
        my $current = @work.shift;
        loop {
            last if $!closed;
            unless $current.frames {
                if $current.negatives {
                    $current.terminal=True; $current.query=EEL::Query.new;
                    @frontier.push($current); last;
                }
                $current.completed-at=$!event-order;
                $current.done = True;
                @frontier.push($current);
                last;
            }
            my $frame = $current.frames.tail;
            unless $frame.todo {
                if $current.negatives && !future-event($current) {
                    $current.terminal=True; $current.query=EEL::Query.new;
                    @frontier.push($current); last;
                }
                if $current.branch-mode && $current.frames.elems == 1 {
                    if $current.negatives {
                        $current.terminal=True; $current.query=EEL::Query.new;
                        @frontier.push($current); last;
                    }
                    $current.completed-at=$!event-order;
                    $current.done=True; @frontier.push($current); last;
                }
                $current.frames.pop;
                if $current.frames {
                    if $current.frames.tail.definition.properties<proto-family> {
                        $current.frames.tail.context.EEL-adopt($frame.context);
                    }
                    capture($current.frames.tail, $frame.capture, $frame.context.EEL-capture);
                    $current.ignore-unexpected = $frame.saved-ignore;
                    $current.partition = $frame.saved-partition;
                    $current.windows.splice($frame.saved-window-count) if $current.windows.elems > $frame.saved-window-count;
                }
                next;
            }
            my $node = $frame.todo.shift;
            if $node ~~ MarkChoice { $current.choices{$node.id} = $node.rank; next }
            if $node ~~ Unordered {
                next unless $node.pending;
                my @options = $node.pending.kv.map(-> $i, $child {
                    [$child, Unordered.new(:pending((^$node.pending.elems).grep(* != $i).map({ $node.pending[$_] })))]
                });
                @work.unshift(|self!choices($current,@options));
                last;
            }
            if $node ~~ EndCapture {
                sub delta($value, $before, Bool $array = False) {
                    return $value unless $value ~~ Array && $before.defined;
                    my $count = $before ~~ Array ?? $before.elems !! 1;
                    my @new = $value.skip($count);
                    @new.elems == 1 && !$array ?? @new[0] !! @new.Array
                }
                my %captured;
                for $frame.captures.kv -> $name,$value {
                    next if ($node.before{$name}:exists) && $value === $node.before{$name};
                    %captured{$name} = delta($value,$node.before{$name}, so $name eq any($node.array-names));
                }
                my @positions;
                for $frame.context.list.kv -> $index,$value {
                    next if $index == $node.index || $value === $node.positions[$index];
                    @positions[$index] = delta($value,$node.positions[$index], so $index eq any($node.array-indices));
                }
                my $view = Event.new(:index($frame.context.EEL-index), :data($frame.context.data), :timestamp($frame.context.timestamp),
                    :made($frame.context.made), :hash(%captured), :list(@positions));
                $frame.context.EEL-position($node.index,$view);
                $current.ignore-unexpected = $node.ignore;
                $current.partition = $node.partition; $current.windows.splice($node.window-count) if $current.windows.elems > $node.window-count;
                next;
            }
            if $node ~~ Restore { $current.ignore-unexpected = $node.ignore; $current.partition = $node.partition; $current.windows.splice($node.window-count) if $current.windows.elems > $node.window-count; next }
            if $node ~~ Closing {
                $current.goals.first(*.id == $node.id).closing = True;
                next;
            }
            if $node ~~ EndGoal {
                $!satisfied{$node.id} = True;
                $current.goals.pop;
                next;
            }
            if $node ~~ Repeat {
                my $repeat = $node.node;
                my $again = $node.count < $repeat.properties<max>;
                my $stop = $node.count >= $repeat.properties<min>;
                my @choices;
                if $again {
                    @choices.push([$repeat.children[0], Repeat.new(:node($repeat), :count($node.count + 1))]);
                }
                @choices.push([]) if $stop;
                @work.unshift(|self!choices($current, @choices));
                last;
            }
            given $node.kind {
                when 'pattern' | 'sequence' | 'ordered' { $frame.todo.unshift(|$node.children) }
                when 'assertion' {
                    my $gate=self!new-assertion($current,$node);
                    my $immediate=self!monitor-result($gate);
                    if $node.properties<positive> {
                        if $immediate.defined {
                            self!positive-capture($gate,$immediate);
                            next;
                        }
                        $current.positive=$gate;
                        $current.query=EEL::Query.new;
                        @frontier.push($current); last;
                    } else {
                        last if $immediate.defined;
                        $current.negatives.push($gate);
                    }
                }
                when 'window-start' {
                    $current.windows.push(Window.new(:id(++$!next-window), :duration($node.properties<nanoseconds>)));
                }
                when 'capture-group' {
                    my @repeated = nodes($node).grep(*.kind eq 'repeat').map({ |nodes(.children[0]) });
                    my @names = @repeated.grep(*.kind eq 'call').map({ .properties<capture> // '' }).unique;
                    my @indices = @repeated.grep(*.kind eq 'capture-group').map({ .properties<index> }).unique;
                    $frame.todo.unshift(|$node.children, EndCapture.new(:index($node.properties<index>), :before($frame.captures.Hash.clone), :positions($frame.context.list.Array), :array-names(@names), :array-indices(@indices), :ignore($current.ignore-unexpected), :partition($current.partition), :window-count($current.windows.elems)));
                }
                when 'group' { $frame.todo.unshift(|$node.children, Restore.new(:ignore($current.ignore-unexpected), :partition($current.partition), :window-count($current.windows.elems))) }
                when 'partition' {
                    my %p = node=>$node, bound=>False;
                    if $frame.context.data.defined {
                        %p<key> = freeze-key($node.code.($frame.context.data));
                        %p<bound> = True;
                    }
                    $current.partition = %p;
                }
                when 'ignore-unexpected'  { $current.ignore-unexpected = $node.properties<enabled> }
                when 'local' | 'code' {
                    if $node.kind eq 'code' && $current.negatives && !future-event($current) { $current.deferred.push($node); next }
                    $node.code.() if $node.code.defined;
                    $frame.initialized{nqp::objectid($node.origin // $node).Str}=True if $node.kind eq 'local';
                }
                when 'ordered-alternative' {
                    my $id = ++$!next-choice;
                    @work.unshift(|self!choices($current,$node.children.kv.map(-> $rank,$child {
                        [MarkChoice.new(:$id,:$rank),$child]
                    }).Array));
                    last;
                }
                when 'shuffle' {
                    my %inside=nodes($node).map({ nqp::objectid(.origin // $_).Str => True }).Hash;
                    $current.shuffle-locals=$frame.initialized.keys.grep({ !%inside{$_} }).Array;
                    $current.shuffle-base=EEL::State.new.copy($frame.context);
                    my @paths=$current,;
                    for $node.children -> $operand {
                        my @next;
                        for @paths -> $path {
                            my $owner=$path.frames.tail;
                            my $copy-node=nodes($owner.definition).first({ .origin === $operand.origin });
                            my @original=$owner.todo;
                            $owner.todo.splice(0,$owner.todo.elems,$copy-node);
                            my $seed=$path.clone(:result($owner.context), :frames[$owner], :branch-mode(True), :positive(Nil), :negatives[], :deferred[], :shuffle[], :shuffle-order[], :shuffle-locals[], :used-events({}), :first-time(Nil), :consume-base(($path.consumed max 1)), :consumed(($path.consumed max 1)));
                            my $branch=self!fork($seed);
                            $owner.todo.splice(0,$owner.todo.elems,|@original);
                            for self!seek($branch) -> $variant {
                                my $next=self!fork($path);
                                $next.shuffle.push($variant);
                                self!inherit-gates($next,$variant);
                                self!transfer-locals($variant.frames[0],$next.frames.tail,$next.shuffle-locals);
                                $next.frames.tail.context.EEL-merge-fields(EEL::State.new.copy($variant.result));
                                $next.shuffle-order.push($next.shuffle.elems-1) if $variant.done;
                                @next.push($next);
                            }
                        }
                        @paths=@next;
                    }
                    for @paths -> $path {
                        if $path.shuffle.first({ pending-lookahead($_) }).defined { .deferred-boundary=True for $path.negatives }
                        if $path.shuffle.map(*.done).all { @work.unshift(|self!join-shuffle($path)) }
                        else { $path.query=AnyQuery.new(:queries($path.shuffle.grep(!*.done).map(*.query).Array)); @frontier.push($path) }
                    }
                    last;
                }
                when 'unordered' { $frame.todo.unshift(Unordered.new(:pending($node.children))) }
                when 'alternative' {
                    @work.unshift(|self!choices($current, $node.children.map({[$_]}).Array));
                    last;
                }
                when 'repeat' {
                    my $policy = $node.properties<selection> // 'all';
                    $current.selections.push([++$!next-selection,$policy,nqp::objectid($node.origin // $node).Str]);
                    array-captures($frame, $node.children[0]);
                    $frame.todo.unshift(Repeat.new(:$node));
                }
                when 'goal' {
                    my $goal = Goal.new(:id(++$!next-goal), :owner($frame.context), :source($node.children[0].source));
                    $current.goals.push($goal);
                    $frame.todo.unshift($node.children[1], Closing.new(:id($goal.id)),
                        $node.children[0], EndGoal.new(:id($goal.id)));
                }
                when 'call' {
                    my $args = $node.code.defined ?? $node.code.() !! \();
                    if $node.name eq 'event' {
                        die '.event accepts only named query arguments' if $args.list.elems;
                        $current.query = EEL::Query.new(:conditions($args.hash));
                        $frame.todo.unshift($node);
                        @frontier.push($current);
                        last;
                    }
                    $current.frames.push(self!frame($frame.context.WHAT, $node.name, $args,
                        :anchor($frame.context.data), :anchor-time($frame.context.timestamp), :anchor-index($frame.context.EEL-index), :capture($node.properties<capture> // ''), :saved-ignore($current.ignore-unexpected), :saved-partition($current.partition), :saved-window-count($current.windows.elems)));
                }
            }
        }
    }
    @frontier.List
}

# Assertion recognizers use isolated, forkable frames of the same compiled grammar.
sub assertion-skips($seed) { $seed.positive.defined ?? $seed.positive.ignore !! $seed.ignore-unexpected }
method !new-assertion($c,$node) {
    my $owner=$c.frames.tail;
    my @todo=$owner.todo;
    $owner.todo.splice(0,$owner.todo.elems,$node.children[0]);
    my $seed=$c.clone(:result($owner.context), :frames[$owner], :branch-mode(True),
        :positive(Nil), :negatives[], :deferred[], :terminal(False), :shuffle[], :shuffle-order[],
        :choices({}), :selections[], :goals[], :consumed(0), :identity-bound(True), :used-events({}), :blocked-events({}), :first-time(Nil), :consume-base(0), :done(False), :completed-at(0));
    my $branch=self!fork($seed);
    $owner.todo.splice(0,$owner.todo.elems,|@todo);
    my @seeds=self!seek($branch);
    EEL::Assertion.new(:positive(so $node.properties<positive>), :ignore(so @seeds.first({ assertion-skips($_) }).defined), :pattern($node.name),
        :capture($node.properties<capture> // ''), :owner($owner.context), :from-index($!cursor), :seen-index($!cursor),
        :started-at($owner.context.data.defined ?? $owner.context.timestamp !! $!input-view.fields<timestamp>),
        :windows($c.windows.map(*.clone).Array), :seeds(@seeds), :active(@seeds.grep(*.done).Array))
}
method !monitor-result($gate, Bool :$finish=False) {
    my @done=$gate.active.grep(*.done);
    my @live=$finish ?? () !! $gate.active.grep(!*.done);
    unless $finish {
        for $gate.seeds.kv -> $index,$seed {
            @live.push($seed) if !$seed.done && (assertion-skips($seed) || !($gate.tried{$index}:exists));
        }
    }
    @done.first(-> $candidate {
        !@done.first({ $_ !=== $candidate && selection-better($_,$candidate) }).defined
        && !@live.first(-> $other {
            my $shared=shared-selection($candidate,$other);
            $shared.defined && $shared[1] eq 'last' && !lower-choice($other,$candidate)
        }).defined
        && !(|@live,|@done).first(-> $other {
            $candidate.choices.keys.first(-> $id {
                ($other.choices{$id}:exists) && $other.choices{$id} < $candidate.choices{$id}
            }).defined
        }).defined
    })
}
method !positive-capture($gate,$match) {
    my $value=$match.result.hash<__eel-asserted>;
    $value=$value.tail if $value ~~ Array;
    $gate.owner.EEL-add-capture($gate.capture,$value) if $gate.capture.chars;
}
method !absence($gate,Str $reason,Instant $time,Mu $witness=Nil) {
    $gate.owner.EEL-add-capture($gate.capture,EEL::Absence.new(:pattern($gate.pattern),
        :started-at($gate.started-at // $time), :confirmed-at($time), :$reason, :$witness)) if $gate.capture.chars;
}
method !feed-monitor($gate,$event) {
    unless $!uses-history { return self!feed-one($gate,$event) }
    my ($order,$cursor,$view,$arrival)=($!event-order,$!cursor,$!input-view,$!arrival);
    LEAVE { ($!event-order,$!cursor,$!input-view,$!arrival)=($order,$cursor,$view,$arrival) }
    my @ends=$gate.windows.grep(*.start.defined).map({ .start+.duration });
    for $gate.seen-index+1 .. $order -> $index {
        next unless %!tape{$index}:exists;
        my $record=%!tape{$index};
        my $time=event-time($record.view.fields<timestamp>);
        last if @ends && $time > @ends.min;
        $gate.seen-index=$index;
        $!event-order=$index; $!cursor=$index; $!input-view=$record.view; $!arrival=$time;
        my $matched=self!feed-one($gate,$record.event);
        return $matched if $matched.defined;
    }
    self!monitor-result($gate)
}
method !feed-one($gate,$event) {
    my @next;
    for $gate.active -> $active {
        if $active.done { @next.push($active); next }
        if self!expired($active,$!arrival) {
            @next.append(self!tick($active,$!arrival)); next;
        }
        if self!applicable($active,$event,$!input-view) { @next.append(self!advance($active,$event)) }
        elsif !self!strict-unexpected($active,$event) { @next.push($active) }
    }
    for $gate.seeds.kv -> $index,$seed {
        next if $seed.done;
        if $gate.positive && !assertion-skips($seed) {
            next if $gate.tried{$index}:exists;
            next unless self!in-partition($seed,$event);
            $gate.tried{$index}=True;
        }
        next unless $seed.positive.defined
            ?? self!in-partition($seed,$event)
            !! self!starter-applicable($seed,$event,$!input-view);
        next if self!expired($seed,$!arrival);
        $gate.started=True;
        my $fresh=self!fork($seed);
        sub reset($path) {
            if $path.positive.defined {
                $path.positive.from-index=$!event-order-1; $path.positive.seen-index=$!event-order-1; $path.positive.tried={};
                $path.positive.started-at=$!input-view.fields<timestamp>;
                reset($_) for $path.positive.seeds;
            }
            for $path.negatives -> $g {
                $g.from-index=$!event-order-1; $g.seen-index=$!event-order-1; $g.tried={}; $g.started-at=$!input-view.fields<timestamp>;
                reset($_) for $g.seeds;
            }
        }
        reset($fresh);
        @next.append(self!advance($fresh,$event));
    }
    $gate.active=@next.Array;
    self!monitor-result($gate)
}
method !replay($c,Int $from --> List) {
    my ($saved-order,$saved-cursor,$saved-view,$saved-time)=($!event-order,$!cursor,$!input-view,$!arrival);
    LEAVE { ($!event-order,$!cursor,$!input-view,$!arrival)=($saved-order,$saved-cursor,$saved-view,$saved-time) }
    $!cursor=$from;
    my @paths=self!seek($c);
    for $from+1 .. $saved-order -> $index {
        next unless %!tape{$index}:exists;
        my $record=%!tape{$index};
        $!event-order=$index; $!cursor=$index; $!input-view=$record.view;
        $!arrival=event-time($record.view.fields<timestamp>);
        my @next;
        for @paths -> $path {
            if $path.done { @next.push($path); next }
            if ($path.blocked-events{$index}:exists) && !$path.positive.defined && !$path.negatives { @next.push($path); next }
            next if self!expired($path,$!arrival);
            if self!applicable($path,$record.event,$!input-view) { @next.append(self!advance($path,$record.event)) }
            elsif !self!strict-unexpected($path,$record.event) { @next.push($path) }
        }
        @paths=@next;
    }
    .seen-through=max(.seen-through,$saved-order) for @paths;
    @paths.List
}
method !assertion-step($c,$event --> List) {
    if $c.positive.defined {
        my $gate=$c.positive;
        my $matched=self!feed-monitor($gate,$event);
        if $matched.defined {
            self!positive-capture($gate,$matched);
            $c.positive=Nil;
            return self!replay($c,$gate.from-index);
        }
        return ().List if !$gate.ignore && self!in-partition($c,$event) && !$gate.active.grep(!*.done);
        return ($c,).List;
    }
    if $c.shuffle && $c.negatives.first(*.deferred-boundary).defined {
        return self!consume($c,$event) if self!main-applicable($c,$event,$!input-view);
        return ().List if self!strict-unexpected($c,$event);
        return ($c,).List;
    }
    for $c.negatives -> $gate {
        return ().List if self!feed-monitor($gate,$event).defined;
    }
    return ($c,).List if $c.terminal;
    return ($c,).List if $!uses-history && ($c.blocked-events{$!event-order}:exists);
    if self!main-applicable($c,$event,$!input-view) {
        # At the boundary, an already completed lower-priority recognition also
        # forbids the occurrence: no future input remains inside this absence.
        return ().List if $c.negatives.first({ self!monitor-result($_,:finish).defined }).defined;
        self!absence($_,'next-step',$!input-view.fields<timestamp>,$event) for $c.negatives;
        $c.negatives=[];
        return self!consume($c,$event);
    }
    return ().List if self!strict-unexpected($c,$event);
    ($c,).List
}
method !settle($c,Str $reason,Instant $time --> List) {
    return ($c,).List if $c.done;
    if $reason eq 'window' {
        my $end=deadline($c);
        return ($c,).List if !$end.defined || $end > event-time($time);
    }
    if $c.positive.defined {
        my $gate=$c.positive;
        self!feed-monitor($gate,%!tape{$!event-order}.event) if %!tape{$!event-order}:exists;
        my @paths;
        for $gate.active -> $path {
            @paths.append($path.done ?? ($path,) !! self!settle($path,$reason,$time));
        }
        $gate.active=@paths.Array;
        my $match=self!monitor-result($gate,:finish);
        return ().List unless $match.defined;
        self!positive-capture($gate,$match); $c.positive=Nil;
        my @out;
        for self!replay($c,$gate.from-index) -> $next { @out.append(self!settle($next,$reason,$time)) }
        return @out.List;
    }
    if $c.terminal && $c.negatives {
        for $c.negatives -> $gate {
            self!feed-monitor($gate,%!tape{$!event-order}.event) if %!tape{$!event-order}:exists;
            my @paths;
            for $gate.active -> $path { @paths.append($path.done ?? ($path,) !! self!settle($path,$reason,$time)) }
            $gate.active=@paths.Array;
            return ().List if self!monitor-result($gate,:finish).defined;
        }
        self!absence($_,$reason,$time) for $c.negatives;
        $c.negatives=[]; $c.terminal=False;
        .code.() for $c.deferred;
        $c.deferred=[];
        return self!seek($c);
    }
    if $c.shuffle {
        my @paths=$c,;
        for ^$c.shuffle.elems -> $index {
            my @next;
            for @paths -> $path {
                if $path.shuffle[$index].done { @next.push($path); next }
                self!block-siblings($path,$path.shuffle[$index]);
                for self!settle($path.shuffle[$index],$reason,$time) -> $branch {
                    my $fork=self!fork($path); $fork.shuffle[$index]=$branch;
                    $fork.shuffle-order.push($index) if $branch.done;
                    @next.push($fork);
                }
            }
            @paths=@next;
        }
        my @out;
        for @paths -> $path {
            if $path.shuffle.map(*.done).all { @out.append(self!join-shuffle($path)) }
            elsif $reason eq 'window' && !self!expired($path,event-time($time)) { @out.push($path) }
        }
        return @out.List;
    }
    ().List
}
sub wake-deadline($c) {
    my @ends;
    my $own=deadline($c); @ends.push($own) if $own.defined;
    my @gates=$c.negatives; @gates.push($c.positive) if $c.positive.defined;
    for @gates -> $g {
        for $g.active.grep(!*.done) { my $end=wake-deadline($_); @ends.push($end) if $end.defined }
    }
    for $c.shuffle.grep(!*.done) { my $end=wake-deadline($_); @ends.push($end) if $end.defined }
    @ends ?? @ends.min !! Nil
}
method !tick($c,Real $now --> List) {
    return ($c,).List if $c.done;
    my @gates=$c.negatives; @gates.push($c.positive) if $c.positive.defined;
    for @gates -> $gate {
        next if $gate.deferred-boundary;
        self!feed-monitor($gate,%!tape{$!event-order}.event) if %!tape{$!event-order}:exists;
        my @paths;
        for $gate.active -> $path { @paths.append(self!tick($path,$now)) }
        $gate.active=@paths.Array;
    }
    if $c.positive.defined {
        my $g=$c.positive;
        my $matched=self!monitor-result($g);
        if $matched.defined {
            self!positive-capture($g,$matched); $c.positive=Nil;
            return self!replay($c,$g.from-index);
        }
    }
    for $c.negatives -> $g { return ().List if self!monitor-result($g).defined }
    if $c.shuffle {
        my @paths=$c,;
        for ^$c.shuffle.elems -> $index {
            my @next;
            for @paths -> $path {
                if $path.shuffle[$index].done { @next.push($path); next }
                self!block-siblings($path,$path.shuffle[$index]);
                for self!tick($path.shuffle[$index],$now) -> $branch {
                    my $fork=self!fork($path); $fork.shuffle[$index]=$branch;
                    $fork.shuffle-order.push($index) if $branch.done;
                    @next.push($fork);
                }
            }
            @paths=@next;
        }
        my @out;
        for @paths -> $path {
            if $path.shuffle.map(*.done).all { @out.append(self!join-shuffle($path)) }
            elsif self!expired($path,$now) {
                my $end=deadline($path);
                @out.append(self!settle($path,'window',Instant.from-posix(0)+($end // $now)/1_000_000_000));
            } else { @out.push($path) }
        }
        return @out.List;
    }
    if self!expired($c,$now) {
        my $end=deadline($c);
        return self!settle($c,'window',Instant.from-posix(0)+($end // $now)/1_000_000_000);
    }
    ($c,).List
}
sub history-positions($c) {
    gather {
        my @gates=$c.negatives; @gates.push($c.positive) if $c.positive.defined;
        for @gates -> $gate {
            take ($gate.positive || $gate.deferred-boundary) ?? $gate.from-index !! $gate.seen-index;
            for |$gate.active,|$gate.seeds { .take for history-positions($_) }
        }
        for $c.shuffle { .take for history-positions($_) }
    }
}
method !trim-history {
    return unless $!uses-history;
    my @starts=($!storage.history-start,$!starter-storage.history-start).grep(*.defined);
    my $earliest=@starts ?? @starts.min !! $!event-order;
    while @!tape-order && @!tape-order[0] <= $earliest { %!tape{@!tape-order.shift}:delete }
}

class UndefinedPartition { }
sub freeze-key($value, %seen = {}) {
    return UndefinedPartition unless $value.defined;
    if $value ~~ Positional|Associative {
        my $id = nqp::objectid(nqp::decont($value)).Str;
        die 'Cyclic partition key' if %seen{$id};
        my %next = |%seen, $id=>True;
        return $value.map({ .key => freeze-key(.value,%next) }).Map if $value ~~ Associative;
        return $value.list.map({ freeze-key($_,%next) }).List;
    }
    $value
}
sub partition-key($value) {
    if $value ~~ List {
        my @parts=$value.map({ partition-key($_) });
        return Nil if @parts.grep({ !.defined }).elems;
        return 'L' ~ @parts.map({ .chars ~ ':' ~ $_ }).join;
    }
    if $value ~~ Map {
        my @parts;
        for $value.keys.sort -> $key {
            my $part=partition-key($value{$key});
            return Nil unless $part.defined;
            @parts.push($key.chars~':'~$key~$part.chars~':'~$part);
        }
        return 'M' ~ @parts.join;
    }
    return 'undefined' if $value === UndefinedPartition;
    scalar-key($value)
}
method !partition-group(%p) {
    my $node=%p<node>;
    (%p<node>.properties<share-extractor> ?? 'shared:'~nqp::objectid($node.origin // $node) !! 'private:'~nqp::objectid($node)).Str
}
method !partition-value(%p,$event) {
    my $group=self!partition-group(%p);
    return %!partition-values{$group} if %!partition-values{$group}:exists;
    %!partition-values{$group}=freeze-key(%p<node>.code.($event))
}
method !partition-description(%p) {
    {group=>self!partition-group(%p),key=>(%p<bound> ?? partition-key(%p<key>) !! Nil),
        extract=>-> $event { partition-key(self!partition-value(%p,$event)) }}
}
sub deadline($c) {
    my @ends=$c.windows.grep(*.start.defined).map({ .start+.duration });
    for $c.negatives.grep(!*.deferred-boundary) -> $g { @ends.append($g.windows.grep(*.start.defined).map({ .start+.duration })) }
    for $c.shuffle.grep(!*.done) -> $branch { my $end=deadline($branch); @ends.push($end) if $end.defined }
    @ends ?? @ends.min !! Nil
}
method !waits($c --> List) {
    if $c.positive.defined || $c.negatives {
        my %wait=query=>EEL::Query.new,strict=>False,low=>-Inf,high=>(deadline($c) // Inf);
        %wait<partition>=self!partition-description($c.partition) if $c.partition;
        my @out; @out.push(%wait);
        my @gates=$c.negatives; @gates.push($c.positive) if $c.positive.defined;
        for @gates -> $gate {
            for |$gate.active.grep(!*.done),|$gate.seeds.grep(!*.done) { @out.append(self!waits($_)) }
        }
        return @out.List;
    }
    return $c.shuffle.grep(!*.done).map({ |self!waits($_) }).List if $c.shuffle;
    my @starts=$c.windows.grep(*.start.defined).map(*.start);
    my %wait=query=>$c.query, strict=>!$c.ignore-unexpected,
        low=>(@starts ?? @starts.max !! -Inf), high=>(deadline($c) // Inf);
    %wait<partition>=self!partition-description($c.partition) if $c.partition;
    (%wait.item,).List
}
method !register($c) {
    my @waits=self!waits($c);
    my %groups=choice=>$c.choices.keys.Array, selection=>$c.selections.map(*.[0]).Array, goal=>$c.goals.map(*.id).Array, history=>history-positions($c).unique.Array;
    $!storage.register($c.query,$c,:@waits,:%groups,:deadline(wake-deadline($c)))
}
# Internal hooks for repeatable differential tests and benchmarks.
method EEL-linear-search(Bool $enabled = True) { $!linear-search=$enabled }
method EEL-candidates { $!candidate-total }
method !in-partition($continuation,$event) {
    my %p = $continuation.partition;
    my $matches=True;
    if %p {
        my $key=self!partition-value(%p,$event);
        %!partition-keys{nqp::objectid($continuation).Str}=$key;
        $matches=so $key eqv %p<key> if %p<bound>;
    }
    return so $continuation.shuffle.grep(!*.done).first({ self!in-partition($_,$event) }).defined if $continuation.shuffle;
    $matches
}
method !applicable($c,$event,$view) {
    return True if $c.positive.defined || $c.negatives;
    self!main-applicable($c,$event,$view)
}
method !starter-applicable($c,$event,$view) {
    return self!in-partition($c,$event) if $c.done;
    return so $c.positive.seeds.first({ self!starter-applicable($_,$event,$view) }).defined if $c.positive.defined;
    if $c.negatives {
        return True if $c.negatives.first({ .seeds.first({ self!starter-applicable($_,$event,$view) }).defined }).defined;
    }
    return so $c.shuffle.grep(!*.done).first({ self!starter-applicable($_,$event,$view) }).defined if $c.shuffle;
    self!main-applicable($c,$event,$view)
}
method !fresh-position($c,Int $from,Instant $time) {
    my @gates=$c.negatives; @gates.push($c.positive) if $c.positive.defined;
    for @gates -> $g {
        $g.from-index=$from; $g.seen-index=$from; $g.started-at=$time unless $c.consumed;
        self!fresh-position($_,$from,$time) for $g.seeds;
    }
    self!fresh-position($_,$from,$time) for $c.shuffle;
}
method !main-applicable($c,$event,$view) {
    return so $c.shuffle.grep(!*.done).first({ self!applicable($_,$event,$view) }).defined if $c.shuffle;
    self!in-partition($c,$event) && $c.query.matches($view)
}
method !strict-unexpected($c,$event) {
    return so $c.shuffle.grep(!*.done).first({ self!strict-unexpected($_,$event) }).defined if $c.shuffle;
    self!in-partition($c,$event) && !$c.ignore-unexpected
}
method !inherit-gates($parent,$branch) {
    $parent.choices{$_}=$branch.choices{$_} for $branch.choices.keys;
    for $branch.selections -> $entry {
        $parent.selections.push($entry.Array) unless $parent.selections.first({ .[0] == $entry[0] }).defined;
    }
}
method !remap-gates($c) {
    $c.choices=$c.choices.map({ (%!rekeys{.key} // .key) => .value }).Hash;
    $c.selections=$c.selections.map({ [(%!selection-rekeys{.[0]} // .[0]),|.skip(1)] }).Array;
    self!remap-gates($_) for $c.shuffle;
}
method !bind-partition($c,$origin,$key) {
    sub bind(%p) {
        if %p && !%p<bound> && %p<node>.origin === $origin { %p<key>=$key; %p<bound>=True }
    }
    bind($c.partition);
    for $c.frames -> $frame {
        bind($frame.saved-partition);
        for $frame.todo -> $i { bind($i.partition) if $i ~~ Restore|EndCapture }
    }
    self!bind-partition($_,$origin,$key) for $c.shuffle;
}
method !sync-windows($c,@windows) {
    for $c.windows -> $window {
        my $parent=@windows.first({ .id == $window.id });
        $window.start=$parent.start if $parent.defined && $parent.start.defined;
    }
    self!sync-windows($_,@windows) for $c.shuffle;
}
method !transfer-locals($from,$to,@keys) {
    return unless @keys;
    my %source=nodes($from.definition).grep(*.read-state.defined).map({ nqp::objectid(.origin // $_).Str => $_ }).Hash;
    my %target=nodes($to.definition).grep(*.write-state.defined).map({ nqp::objectid(.origin // $_).Str => $_ }).Hash;
    my $copy=EEL::State.new;
    for @keys -> $key {
        %target{$key}.write-state.($copy.copy(%source{$key}.read-state.())) if (%source{$key}:exists) && (%target{$key}:exists);
    }
}
sub pending-lookahead($c) {
    $c.positive.defined || so $c.shuffle.first({ pending-lookahead($_) }).defined
}
method !block-siblings($parent,$branch) {
    return unless $!uses-history;
    $branch.blocked-events=(|$parent.blocked-events,|$parent.used-events.grep({ !($branch.used-events{.key}:exists) })).Hash;
}
method !advance-shuffle($current,$event) {
    self!remap-gates($_) for $current.shuffle;
    my @indices=(^$current.shuffle.elems).grep({ !$current.shuffle[$_].done && self!applicable($current.shuffle[$_],$event,$!input-view) });
    my @out;
    for @indices -> $i {
        my $path=self!fork($current);
        my $branch=$path.shuffle[$i];
        self!transfer-locals($path.frames.tail,$branch.frames[0],$path.shuffle-locals);
        $branch.frames[0].context.EEL-merge-fields(EEL::State.new.copy($path.frames.tail.context));
        $branch.choices = (|$path.choices, |$branch.choices).Hash;
        if $path.partition && !$path.partition<bound> && $branch.partition && $branch.partition<node>.origin === $path.partition<node>.origin {
            my $key=%!partition-keys{nqp::objectid($branch).Str};
            self!bind-partition($path,$path.partition<node>.origin,$key);
        }
        self!block-siblings($path,$branch);
        my $before=$branch.consumed;
        my @variants=self!advance($branch,$event);
        for @variants -> $variant {
            my $next=self!fork($path);
            $next.shuffle[$i]=$variant;
            self!transfer-locals($variant.frames[0],$next.frames.tail,$next.shuffle-locals);
            $next.frames.tail.context.EEL-merge-fields(EEL::State.new.copy($variant.result));
            my $delta=$variant.consumed-$before;
            $next.consumed+=$delta;
            if $delta > 0 {
                if $!uses-history {
                    $next.used-events{$_}=True for $variant.used-events.keys;
                    $next.first-time=$variant.first-time if $variant.first-time.defined && (!$next.first-time.defined || $variant.first-time < $next.first-time);
                    if $variant.result.EEL-index > $next.frames.tail.context.EEL-index {
                        for $next.frames { .context.EEL-accept($variant.result.data,:index($variant.result.EEL-index)); .context.timestamp=$variant.result.timestamp }
                    }
                } else {
                    for $next.frames { .context.EEL-accept($event,:index($!event-order)); .context.timestamp=$!input-view.fields<timestamp> }
                }
                my $start=$variant.first-time // $!arrival;
                for $next.windows { .start=$start if !.start.defined || $start < .start }
                self!sync-windows($_,$next.windows) for $next.shuffle;
            }
            self!inherit-gates($next,$variant);
            $next.shuffle-order.push($i) if $variant.done;
            if $!uses-history { @out.append(self!tick($next,$!arrival)) }
            elsif $next.shuffle.map(*.done).all { @out.append(self!join-shuffle($next)) }
            else { $next.query=AnyQuery.new(:queries($next.shuffle.grep(!*.done).map(*.query).Array)); @out.push($next) }
        }
    }
    @out.List
}
method !join-shuffle($current) {
    my $frame=$current.frames.tail;
    my $baseline=$current.shuffle-base;
    for $current.shuffle-order -> $index {
        my $branch=$current.shuffle[$index];
        my $context=$branch.result;
        for $context.hash.kv -> $name,$value {
            my @new;
            if $baseline.hash{$name}:exists {
                next unless $value ~~ Array;
                my $old=$baseline.hash{$name};
                @new=$value.skip($old ~~ Array ?? $old.elems !! 1);
            } else { @new=$value ~~ Array ?? $value.list !! ($value,) }
            capture($frame,$name,$_) for @new;
            $frame.captures{$name}=[$frame.captures{$name}] if $value ~~ Array && $frame.captures{$name} !~~ Array;
        }
        for $context.list.kv -> $i,$value {
            next unless $value.defined;
            my $old=$baseline.list[$i];
            my @new=$old.defined ?? ($value ~~ Array ?? $value.skip($old ~~ Array ?? $old.elems !! 1) !! ()) !! ($value ~~ Array ?? $value.list !! ($value,));
            $frame.context.EEL-position($i,$_) for @new;
        }
        $frame.arrays{$_}=True for $branch.frames[0].arrays.keys;
    }
    for $frame.captures.kv -> $name,$values {
        if $values ~~ Array && $values.elems && $values.all ~~ Event {
            $frame.captures{$name} = $values.sort({ $^a.EEL-index <=> $^b.EEL-index }).Array;
        }
    }
    $frame.context.EEL-captures($frame.captures);
    if $!uses-history {
        my %used; my $latest=$frame.context;
        for $current.shuffle -> $branch {
            return ().List if $branch.used-events.keys.first({ %used{$_}:exists }).defined;
            %used{$_}=True for $branch.used-events.keys;
            $latest=$branch.result if $branch.result.EEL-index > $latest.EEL-index;
        }
        $current.used-events{$_}=True for %used.keys;
        $current.consumed=$current.consume-base+$current.used-events.elems;
        for $current.frames { .context.EEL-accept($latest.data,:index($latest.EEL-index)); .context.timestamp=$latest.timestamp }
    }
    if $current.negatives.first(*.deferred-boundary).defined {
        my @remaining;
        for $current.negatives -> $gate {
            my @indices=$current.used-events.keys.map(*.Int).grep(* > $gate.from-index);
            unless @indices { $gate.deferred-boundary=False; @remaining.push($gate); next }
            my $index=@indices.min;
            my $record=%!tape{$index};
            my $time=event-time($record.view.fields<timestamp>);
            return ().List if $gate.windows.first({ .start.defined && $time-.start >= .duration }).defined;
            my ($order,$cursor,$view,$arrival)=($!event-order,$!cursor,$!input-view,$!arrival);
            my $prohibited;
            {
                LEAVE { ($!event-order,$!cursor,$!input-view,$!arrival)=($order,$cursor,$view,$arrival) }
                $!event-order=$index; $!cursor=$index; $!input-view=$record.view; $!arrival=$time;
                my $probe=$gate.clone(:active[], :seen-index($gate.from-index), :tried({}), :started(False),
                    :seeds($gate.seeds.map({ self!fork($_) }).Array));
                $prohibited=self!feed-monitor($probe,$record.event);
                $prohibited=self!monitor-result($probe,:finish) unless $prohibited.defined;
            }
            return ().List if $prohibited.defined;
            self!absence($gate,'next-step',$record.view.fields<timestamp>,$record.event);
        }
        $current.negatives=@remaining.Array;
    }
    $current.shuffle=[]; $current.shuffle-order=[]; $current.shuffle-locals=[]; $current.shuffle-base=Nil;
    self!seek($current)
}
method !bind-start($continuation) {
    return if $continuation.identity-bound;
    $continuation.identity-bound=True;
    if !$continuation.consumed && $continuation.selections {
        $continuation.selections = $continuation.selections.map(-> $entry {
            %!selection-rekeys{$entry[0]} //= ++$!next-selection;
            [%!selection-rekeys{$entry[0]},|$entry.skip(1)]
        }).Array;
    }
    if !$continuation.consumed && $continuation.choices {
        my %choices;
        for $continuation.choices.kv -> $id,$rank {
            %!rekeys{$id} //= ++$!next-choice;
            %choices{%!rekeys{$id}} = $rank;
        }
        $continuation.choices = %choices;
    }
}
method !advance(EEL::Continuation:D $continuation, $event --> List) {
    self!bind-start($continuation);
    if $continuation.done {
        if $continuation.partition && !$continuation.partition<bound> {
            $continuation.partition<key> = %!partition-keys{nqp::objectid($continuation).Str};
            $continuation.partition<bound> = True;
        }
        return ($continuation,).List;
    }
    return self!assertion-step($continuation,$event) if $continuation.positive.defined || $continuation.negatives;
    self!consume($continuation,$event)
}
method !consume(EEL::Continuation:D $continuation, $event --> List) {
    return ($continuation,).List if $!uses-history && ($continuation.blocked-events{$!event-order}:exists);
    return self!advance-shuffle($continuation,$event) if $continuation.shuffle;
    if $continuation.partition && !$continuation.partition<bound> {
        $continuation.partition<key> = %!partition-keys{nqp::objectid($continuation).Str};
        $continuation.partition<bound> = True;
    }
    .start = $!arrival for $continuation.windows.grep({ !.start.defined });
    my $frame = $continuation.frames.tail;
    my $call = $frame.todo.shift;
    capture($frame, $call.properties<capture> // '', Event.new(:rule<event>, :index($!event-order), :data($event), :timestamp($!input-view.fields<timestamp>), :event-id($!input-view.fields<event-id>)));
    for $continuation.frames { .context.EEL-accept($event, :index($!event-order)); .context.timestamp = $!input-view.fields<timestamp> }
    $continuation.consumed++;
    if $!uses-history {
        $continuation.used-events{$!event-order}=True;
        $continuation.first-time=$!arrival if !$continuation.first-time.defined || $!arrival < $continuation.first-time;
    }
    self!seek($continuation)
}

# Internal adapter hook; this is the pre-action view for the last input round.
method EEL-input-view() { $!input-view }

method !expired($c,Real $now) {
    return True if $c.negatives.grep(!*.deferred-boundary).first({ .windows.first({ .start.defined && $now-.start >= .duration }).defined }).defined;
    return True if $c.windows.first({ .start.defined && $now - .start >= .duration }).defined;
    so $c.shuffle.grep(!*.done).first({ self!expired($_,$now) }).defined
}
method !expire(Real $now) {
    my %removed;
    for $!storage.expired($now) -> $entry {
        %removed{.id}=True for $entry.continuation.goals;
        $!storage.remove($entry.id);
        for self!tick($entry.continuation,$now) -> $next {
            $next.done ?? self!queue($next) !! self!register($next);
        }
    }
    for %removed.keys.grep({ !$!storage.has-members('goal',$_) }) -> $id {
        %!goal-failures{$id}:delete;
        $!satisfied{$id}:delete;
    }
}
method pending(--> Int) { $!lock.protect({ self!expire($!watermark) if $!watermark.defined; $!storage.elems + $!retained.elems + $!inbox.elems }) }
method close(Bool :$keep-emissions = False) {
    $!lock.lock;
    LEAVE $!lock.unlock;
    $!closed = True;
    $!input-view = EEL::Input::Snapshot;
    $!storage.clear;
    @!starters = (); $!starter-storage.clear; @!starter-ids=();
    $!satisfied = SetHash.new;
    %!goal-failures = ();
    @!emissions=() unless $keep-emissions;
    %!tape=(); @!tape-order=();
    $!inbox.clear; $!retained.clear; %!selected=(); %!committed = (); %!rekeys = ();
}
method EEL-emissions { my @records=@!emissions; @!emissions=(); @records.List }
method process($event --> List) {
    $!lock.lock;
    LEAVE $!lock.unlock;
    die 'EEL::Runner is closed' if $!closed;
    die 'EEL::Runner has failed' if $!failed;
    die 'EEL::Runner.process is already running' if $!processing;
    $!processing = True;
    do {
    LEAVE $!processing=False;
    CATCH { default { %!tape=(); @!tape-order=(); @!emissions=(); $!failed=True; $!storage.clear; $!inbox.clear; $!retained.clear; @!starters=(); $!starter-storage.clear; @!starter-ids=(); .rethrow } }
    @!emissions=();
    my $input = $event ~~ PreparedInput ?? $event !! PreparedInput.new(:event($event), :view(snapshot($event)));
    my $time=event-time($input.view.fields<timestamp>);
    if $!watermark.defined && $time < $!watermark {
        note "Late event {$input.view.fields<event-id>}: timestamp {$input.view.fields<timestamp>} precedes watermark {Instant.from-posix(0) + $!watermark / 1_000_000_000}";
        return ().List;
    }
    $!maximum-time = $time if !$!maximum-time.defined || $time > $!maximum-time;
    $!watermark = $!maximum-time - $!lateness-ns;
    $!inbox.push([$time,++$!input-order,$input]);
    self!drain
    }
}
method !drain(Bool :$all = False --> List) {
    my @out;
    while $!inbox && ($all || $!inbox.peek[0] <= $!watermark) {
        my $input = $!inbox.shift[2];
        my @matches=self!round($input.event,:prepared($input.view));
        @out.append(@matches);
        @!emissions.push({input=>$input,matches=>@matches.Array}) if $!record-emissions;
    }
    unless $all {
        self!expire($!watermark);
        my @ready=self!release;
        if @ready { @out.append(@ready); @!emissions.push({matches=>@ready.Array}) if $!record-emissions }
    }
    self!trim-history;
    @out.List
}
method !notify(@failed) {
    %!goal-failures{.id} = $_ for @failed;
    for %!goal-failures.keys.sort(*.Int).reverse -> $id {
        next unless %!goal-failures{$id}:exists;
        if $!satisfied{$id} { %!goal-failures{$id}:delete; next }
        next if $!storage.has-members('goal',$id);
        my $goal = %!goal-failures{$id}:delete;
        $goal.owner.FAILGOAL($goal.source);
    }
    $!satisfied{$_}:delete for $!satisfied.keys.grep({ !$!storage.has-members('goal',$_) });
}
method !refresh-starters(Int $index) {
    $!starter-storage.remove($_) for (@!starter-ids[$index] // []).list;
    @!starters[$index]=self!start(@!patterns[$index]).Array;
    my @ids;
    for @!starters[$index].kv -> $position,$c {
        $c.query=EEL::Query.new if $c.done;
        @ids.push($!starter-storage.register($c.query,{:$index,:$position,:$c},:waits(self!waits($c)),:groups({history=>[]})));
    }
    @!starter-ids[$index]=@ids.Array;
}
method !round($event, :$prepared --> List) {
    LEAVE { %!partition-keys = (); %!partition-values=() }
    CATCH { default { %!tape=(); @!tape-order=(); $!retained.clear; %!committed=(); %!rekeys=(); $!failed = True; $!storage.clear; @!starters = (); $!starter-storage.clear; @!starter-ids=(); $!satisfied = SetHash.new; %!goal-failures = (); $!input-view = EEL::Input::Snapshot; .rethrow } }
    %!rekeys = (); %!selection-rekeys=();
    %!partition-keys = ();
    $!arrival = event-time($prepared.fields<timestamp>);
    $!event-order++;
    $!cursor=$!event-order-1;
    if $!uses-history { %!tape{$!event-order}=PreparedInput.new(:$event,:view($prepared)); @!tape-order.push($!event-order) }
    self!expire($!arrival);
    $!input-view = $prepared // snapshot($event);
    my $view = $!input-view;
    unless $!initialized {
        self!refresh-starters($_) for ^@!patterns.elems;
        $!initialized = True;
    }
    $!cursor=$!event-order;
    my @failed;
    my @snapshot = $!linear-search ?? $!storage.snapshot !! $!storage.candidates($view,:raw($event),:time($!arrival),:strict);
    $!candidate-total+=@snapshot.elems;
    my @starter-snapshot=$!linear-search ?? $!starter-storage.snapshot
        !! $!starter-storage.candidates($view,:raw($event),:time($!arrival));
    $!starter-candidates+=@starter-snapshot.elems;
    my %starts;
    for @starter-snapshot -> $entry {
        my %start=$entry.continuation;
        (%starts{%start<index>} //= []).push(%start) if self!starter-applicable(%start<c>,$event,$view);
    }
    my @applicable = @snapshot.kv.map(-> $i,$entry { self!applicable($entry.continuation,$event,$view) });
    for @snapshot.kv -> $index, $entry {
        last if $!closed;
        my $continuation = $entry.continuation;
        next if $continuation.seen-through >= $!event-order;
        if @applicable[$index] {
            $!storage.remove($entry.id);
            for self!advance($continuation, $event) -> $next {
                $next.done ?? self!queue($next) !! self!register($next);
            }
        } elsif self!strict-unexpected($continuation,$event) {
            $!storage.remove($entry.id);
            @failed.append($continuation.goals.grep(*.closing));
        }
    }
    for %starts.keys.sort(*.Int) -> $key {
        last if $!closed;
        my $index=$key.Int;
        for %starts{$key}.sort(*.<position>) -> %start {
            self!fresh-position(%start<c>,$!event-order-1,$!input-view.fields<timestamp>);
            for self!advance(%start<c>, $event) -> $next {
                $next.done ?? self!queue($next) !! self!register($next);
            }
        }
        self!refresh-starters($index) unless $!closed;
    }
    if $!closed { $!storage.clear; @!starters = (); $!starter-storage.clear; @!starter-ids=(); return ().List }
    self!notify(@failed);
    my @ready=$!closed ?? () !! self!release;
    self!trim-history;
    @ready.List
}

method !queue($continuation) {
    $continuation.completed-at = $!event-order;
    $continuation.result-order = ++$!result-order;
    $!retained.add($continuation);
}
sub lower-choice($other,$candidate) {
    so $candidate.choices.keys.first(-> $id {
        ($other.choices{$id}:exists) && $other.choices{$id} > $candidate.choices{$id}
    }).defined
}
sub shared-selection($candidate,$other) {
    $candidate.selections.first(-> $entry { $other.selections.first({ .[0] == $entry[0] }).defined })
}
sub selection-better($other,$candidate) {
    return False if lower-choice($other,$candidate);
    my $shared=shared-selection($candidate,$other);
    return False unless $shared.defined;
    if $other.completed-at == $candidate.completed-at { return $other.result-order < $candidate.result-order }
    $shared[1] eq 'first' ?? $other.completed-at < $candidate.completed-at !! $other.completed-at > $candidate.completed-at
}
method !discarded($continuation) {
    so $continuation.choices.kv.map(-> $id,$rank {
        (%!committed{$id}:exists) && %!committed{$id} != $rank
    }).any
}
# Stable repeat origin, rather than its per-start selection id, groups
# overlapping starts. Partition keys keep independent streams independent.
method !selection-groups($c --> List) {
    my $partition=$c.partition && $c.partition<bound>
        ?? (partition-key($c.partition<key>) // '') !! '';
    $c.selections.grep({ .[1] ne 'last' }).map({
        nqp::objectid($c.result.WHAT).Str ~ '|' ~ .[2] ~ '|' ~ $partition.chars ~ ':' ~ $partition
    }).List
}
method !selection-outranks($other,$candidate --> Bool) {
    my @groups=self!selection-groups($candidate);
    my @other=self!selection-groups($other);
    for @groups.kv -> $i,$group {
        next unless $group eq any(@other);
        my $policy=$candidate.selections.grep({ .[1] ne 'last' })[$i][1];
        return $other.result-order < $candidate.result-order if $other.consumed == $candidate.consumed;
        return $policy eq 'first' ?? $other.consumed < $candidate.consumed
            !! $other.consumed > $candidate.consumed;
    }
    False
}
method !release(--> List) {
    my %changes=$!storage.changes;
    $!retained.affect(%changes);
    $!retained.mark-all if $!reference-retained;
    my @out;
    my %published;
    loop {
        my @ready=$!retained.ready;
        last unless @ready;
        for @ready.kv -> $position,$candidate {
            next unless $!retained.has($candidate.result-order);
            $!retained-checked++;
            if self!discarded($candidate) { $!retained.remove($candidate.result-order); next }
            my @peers=$!retained.related($candidate)
                .grep({ !self!discarded($_) }).List;
            my %related;
            for $candidate.choices.keys -> $id { %related{$_}=True for $!storage.members('choice',$id) }
            for $candidate.selections -> $entry { %related{$_}=True for $!storage.members('selection',$entry[0]) }
            my @live=$!storage.entries(%related.keys).map(*.continuation);
            next if (|@live,|@peers).first(-> $other {
                $candidate.choices.keys.first(-> $id {
                    ($other.choices{$id}:exists) && $other.choices{$id} < $candidate.choices{$id}
                }).defined
            }).defined;
            my @groups=self!selection-groups($candidate);
            if @groups.first({ %published{$_}:exists }).defined
                || (@groups && $!retained.snapshot.first(-> $other {
                    $other !=== $candidate && !self!discarded($other)
                        && self!selection-outranks($other,$candidate)
                }).defined) {
                $!retained.remove($candidate.result-order);
                next;
            }
            %published{$_}=True for @groups;
            my $winner=$candidate;
            $!retained.remove($winner.result-order);
            my %prune;
            for $winner.choices.kv -> $id,$rank {
                %!committed{$id}=$rank;
                %prune{$_}=True for $!storage.members('choice',$id);
            }
            for $!storage.entries(%prune.keys) -> $entry { $!storage.remove($entry.id) if self!discarded($entry.continuation) }
            # Forks preserve the candidate's identity; publishing a new snapshot
            # must not turn growth of that candidate into a different event ID.
            @out.push($winner.result);
            # Publishing may unblock an earlier result. Requeue the rest so
            # the next pass again chooses the earliest eligible source path.
            my %changed=|$!storage.changes,|$!retained.changes;
            %changes{$_}=True for %changed.keys;
            $!retained.affect(%changed);
            $!retained.schedule(@ready.skip($position+1).List);
            last;
        }
    }
    %changes{$_}=True for $!retained.changes.keys;
    for %changes.keys -> $group {
        if $group.starts-with('choice:') {
            my $id=$group.substr(7);
            %!committed{$id}:delete unless $!storage.has-members('choice',$id) || $!retained.has-group($group);
        } elsif $group.starts-with('selection:') {
            my $id=$group.substr(10);
            %!selected{$id}:delete unless $!storage.has-members('selection',$id) || $!retained.has-group($group);
        }
    }
    @out.List
}

# End of input is distinct from cancellation: unresolved closing goals get the
# same failure hook as an exhausted strict path. Completed paths are not replayed.
method finish(--> List) {
    $!lock.lock;
    LEAVE $!lock.unlock;
    die 'EEL::Runner has failed' if $!failed;
    return ().List if $!closed;
    die 'EEL::Runner.process is already running' if $!processing;
    $!processing = True;
    do {
    LEAVE $!processing=False;
    CATCH { default {
        %!tape=(); @!tape-order=();
        $!failed=True; @!emissions=(); $!inbox.clear; $!retained.clear; @!starters=(); $!starter-storage.clear; @!starter-ids=(); $!storage.clear;
        %!goal-failures=(); $!satisfied=SetHash.new; $!input-view=EEL::Input::Snapshot;
        .rethrow
    } }
    @!emissions=();
    my @out=self!drain(:all);
    @out.append(self!end-round);
    @out.List
    }
}
method !end-round(--> List) {
    LEAVE $!processing = False;
    CATCH { default { $!failed = True; self.close; .rethrow } }
    self!expire($!watermark) if $!watermark.defined;
    my @pending=$!storage.snapshot;
    my @goals = @pending.map({ .continuation.goals.grep(*.closing) }).flat;
    $!storage.clear;
    my $time=$!arrival.defined ?? Instant.from-posix(0)+$!arrival/1_000_000_000 !! Instant.from-posix(0);
    for @pending -> $entry {
        for self!settle($entry.continuation,'eof',$time) -> $next { self!queue($next) if $next.done }
    }
    $!retained.mark-all;
    self!notify(@goals);
    my @out = self!release;
    self.close(:keep-emissions);
    @out.List
}

# A Tappable owns lifecycle state per subscription, including for live inputs.
# Keep cancellation explicit rather than storing engine state in supply phasers.
class MatcherSupply does Tappable {
    has Supply $.source is required;
    has @.patterns;
    has Str $.rule;
    has Real $.lateness;
    has EEL::Reemit $.reemit is required;
    method live { $!source.live }
    method sane { True }
    method serial { True }

    method tap(&emit, &done, &quit, &tap) {
        my $runner = EEL::Runner.new(:@!patterns, :$!rule, :$!lateness, :record-emissions);
        my $lock = Lock::Async.new;
        my $closed = False;
        my $upstream;
        my $output;
        sub cleanup() {
            unless $closed {
                $closed = True;
                $upstream.close if $upstream.defined;
                $runner.close;
            }
        }
        $!source.sanitize.tap(
            tap => -> $handle {
                $upstream = $handle;
                $output = Tap.new({ cleanup() });
                tap($output);
            },
            -> $event {
                $lock.protect-or-queue-on-recursion: {
                    CATCH { default { cleanup(); quit($_) } }
                    unless $closed {
                        $runner.process($event);
                        for $runner.EEL-emissions -> $record {
                            last if $closed;
                            if $record<input>:exists {
                                my $input=$record<input>;
                                emit($input.event) if $!reemit.accepts($input.event,$input.view) && !$closed;
                            }
                            for $record<matches>.list -> $match { last if $closed; emit($match) }
                        }
                    }
                }
            },
            done => {
                $lock.protect-or-queue-on-recursion: {
                    CATCH { default { cleanup(); quit($_) } }
                    unless $closed {
                        my @final = $runner.finish;
                        my $count=0;
                        for $runner.EEL-emissions -> $record {
                            last if $closed;
                            if $record<input>:exists {
                                my $input=$record<input>;
                                emit($input.event) if $!reemit.accepts($input.event,$input.view) && !$closed;
                            }
                            $count += $record<matches>.elems;
                            for $record<matches>.list -> $match { last if $closed; emit($match) }
                        }
                        for @final.skip($count) { last if $closed; emit($_) }
                        unless $closed { cleanup(); done() }
                    }
                }
            },
            quit => -> $exception {
                $lock.protect-or-queue-on-recursion: {
                    unless $closed { cleanup(); quit($exception) }
                }
            });
        $output
    }
}

# Low-level Supply adapter; Supply.match delegates here.
method supply(Supply:D $input, :$reemit = False --> Supply) {
    my $policy = EEL::Reemit.new(:selection($reemit));
    Supply.new(MatcherSupply.new(:source($input), :@!patterns, :$!rule, :reemit($policy), :$!lateness))
}
