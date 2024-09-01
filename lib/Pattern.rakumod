class HandledReturn {}
class HandledReturn::Next is HandledReturn {}
class HandledReturn::End is HandledReturn {}
class HandledReturn::AddToStorage {
    has $.storage is required;
    has %.query   is required;
    has $.match   is required;
}

my role Nextable {
    method elems                    {...}
    method choose-callable(UInt $i) {...}
    method run(\match ( :@pos, UInt :$index, | )) {
        return $.run: match.clone(:pos(|@pos, 0)) unless $index + 1 <= @pos;
        my $current = @pos[$index];
        dd @pos;
        dd $current;
        return HandledReturn::End unless $current + 1 <= $.elems;
        my &callable = self.choose-callable: $current;
        self.handle-return: match, callable match, |match.args.Capture
    }
    multi method handle-return(\match ( :@pos, UInt :$index, | ), HandledReturn::Next) {
        my $max     = $.elems - 1;
        my $current = @pos[$index];
        return HandledReturn::Next unless $current <= $max;
        self.run: match.clone: :pos(@pos.&{ |.head($current), .[$current] + 1, |.tail: * - $current - 1 })
    }
    multi method handle-return(\match, HandledReturn::End) {
        say "END: {match.gist}";
    }
    multi method handle-return(\match, HandledReturn::AddToStorage ( :$match ( :$index, :@pos, | ), :$storage, :%query, | )) {
        note "\$storage.add: %query<>, {$match.gist}";
        $storage.add: %query, $match.clone: :pos(|$.next-pos: match)
    }
    multi method handle-return(@returns) {
        $.handle-return: $_ for @returns
    }
    multi method handle-return(|) { }
    method next-pos(\match ( :$index, :@pos, | )) {
        my $current = @pos[$index];
        Array[UInt].new: do if $current + 1 >= $.elems {
            @pos.head($index - 1), @pos[$index - 1] + 1
        } else {
            |@pos.head($index), $current + 1, |@pos.tail: * - $index - 1
        }
    }
}

my class Step does Nextable is Method {
    method name {'step'}
    has Callable @.steps handles <AT-POS elems>;

    method choose-callable(UInt $i) {
        @!steps[$i]
    }

    multi method add-step(&callable) {
        @!steps.push: &callable;
        self
    }

    multi method add-step(@callables) {
        my Step $step .= new;
        $step.add-step: $_ for @callables;
        self
    }

    method CALL-ME(\match ( :@pos, UInt :$index, | ), |) {
        say 'here!!!';
        $.run: match
    }
}

my class Repeat is Method {
    method name {'repeat'}
    has Numeric  $.min = 1;
    has Numeric  $.max = 1;

    method elems { $!max }

    method CALL-ME(\match ( :@pos, UInt :$index, | ), |) {
        $.run: match
    }
}

my class Or is Method {
    method name {'or'}
    has Step @.options;

    multi method add-option($opt) {
        my $step = Step.bless;
        $step.add-step: $_ for |$opt;
        @!options.push: $step;
        self
    }

    multi method add-option(Step $opt) {
        @!options.push: $opt;
        self
    }

    method CALL-ME(\match, |) {
        # FIXME: what happens if there is no rule as first step?
        for @!options {
            .(match, |match.args.Capture) # last if match
        }
    }
}

class Pattern is Method {
    has Str  $.name;
    has Str  $.source;
    has Step $.steps handles <add-step> .= bless;

    method CALL-ME(\match, |c) {
        my $m = match.clone: :args(c), :rule($.name);
        say $m;
        $!steps($m)
    }
}
