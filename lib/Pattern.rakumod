class HandledReturn {}
class HandledReturn::Next is HandledReturn {
    has $.match is required
}
class HandledReturn::End is HandledReturn {}
class HandledReturn::AddToStorage {
    has $.storage is required;
    has %.query   is required;
}
class HandledReturn::CallRule is HandledReturn {
    has         $.rule-to-call is required;
    has Capture $.args;
}

sub run(\match) {
    my $rule    = match.rule;
    my &pattern = match.^find_method: $rule;

    &pattern.steps.run: match;
}

my role Nextable is Method {
    method elems                    {...}
    method choose-callable(UInt $i) {...}
    method run(Any:D \match) {
        my @pos   = match.pos;
        my $index = match.index;
        # quietly say "run: {match.rule}: @pos[]; $index => @pos[$index]";
        return run match.clone(:pos(|@pos, 0)) unless $index + 1 <= @pos;
        my $current = @pos[$index];
        return HandledReturn::End unless $current + 1 <= $.elems;
        my &callable = $.choose-callable: $current;
        $.handle-return: match, callable match, |match.args.Capture;
    }
    proto method handle-return(\match, |) {
        my $response = {*};
        do if $response ~~ Positional && $response.elems > 1 && $response[1] ~~ HandledReturn {
            $.handle-return: |$response
        } else {
            $response
        }
    }
    multi method handle-return(\match, HandledReturn::Next:D $next ( :$match )) {
        $match, $next.WHAT
    }
    multi method handle-return(\match, HandledReturn::Next:U) {
        my @pos        = match.pos;
        my $index      = match.index;
        my $current    = @pos[$index];
        my $next-match = $.next-pos-match(match);
        do with $next-match {
            run $_
        } orwith match.parent -> $match is copy {
            $match .= clone: :parent(match);
            $match, HandledReturn::Next.new: :$match;
        } else {
            match, HandledReturn::End
        }
    }
    multi method handle-return(\match, HandledReturn::End) {
        emit match
    }
    multi method handle-return(\match, HandledReturn::AddToStorage ( :$storage! is raw, :%query!, | )) {
        $storage.add: %query, $.next-pos-match: match;
    }
    multi method handle-return(\match, HandledReturn::CallRule ( :rule-to-call($rule), :$args, | )) {
        match.new(:parent(match), :$rule, :$args)."$rule"(|$args.Capture)
    }
    multi method handle-return(@returns) {
        $.handle-return: $_ for @returns
    }
    multi method handle-return(|) { }
    method next-pos-match(\match) {
        my $new-pos = $.next-pos: match;
        return Nil unless $new-pos;
        match.clone: :pos(|$new-pos)
    }
    method next-pos(\match) {
        my @pos     = match.pos;
        my $index   = match.index;
        my $current = @pos[$index];
        Array[UInt].new: do if $current + 1 >= $.elems {
            return Nil if $index == 0;
            @pos.head($index - 1), @pos[$index - 1] + 1
        } else {
            |@pos.head($index), $current + 1, |@pos.tail: * - $index - 1
        }
    }
}

my class Step does Nextable {
    method name {'step'}
    has Callable @.steps handles <AT-POS elems>;

    method list-steps {
        |@!steps
    }

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

    method add-rule-call(Str $rule-to-call, Capture $args, Bool :$store-positional = False, Str :$store-key) {
        $.add-step: sub call-rule($match) {
            HandledReturn::CallRule.new: :$rule-to-call, :$args
        }
        $.add-step: sub return-from-rule ($match is copy) {
            my $parent = $match.parent;
            my @list = $match.list;
            my %hash = $match.hash;
            if $store-positional {
                @list.push: $parent;
            }
            with $store-key {
                %hash{.Str} = $parent;
            }

            $match .= clone: :parent(Nil), :@list, :%hash;
            HandledReturn::Next.new: :$match
        }
    }

    method CALL-ME(\match, |) {
        my @pos   = match.pos;
        my $index = match.index;
        run match
    }
}

my class Repeat does Nextable {
    method name {'repeat'}
    has Numeric  $.min = 1;
    has Numeric  $.max = 1;
    has Step     $.steps handles <add-step>.= new;

    method elems { $!max }
    method choose-callable($) { $!steps }

    method CALL-ME(\match, |) {
        my @pos   = match.pos;
        my $index = match.index;
        run match
    }
}

# my class Or does Nextable {
#     method name {'or'}
#     has Step @.options;
# 
#     multi method add-option($opt) {
#         my $step = Step.bless;
#         $step.add-step: $_ for |$opt;
#         @!options.push: $step;
#         self
#     }
# 
#     multi method add-option(Step $opt) {
#         @!options.push: $opt;
#         self
#     }
# 
#     method CALL-ME(\match, |) {
#         # FIXME: what happens if there is no rule as first step?
#         for @!options {
#             .(match, |match.args.Capture) # last if match
#         }
#     }
# }

class Pattern is Method {
    has Str  $.name;
    has Str  $.source;
    has Step $.steps handles <add-step add-rule-call list-steps> .= bless;

    method CALL-ME(\match, |c) {
        my $m = match.clone: :args(c), :rule($.name);
        $!steps($m)
    }
}
