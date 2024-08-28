my class Step {
    has Numeric  $.min = 1;
    has Numeric  $.max = 1;
    has Callable @.steps;

    multi method add-step(&callable) {
        @!steps.push: &callable;
        self
    }

    multi method add-step(@callables, :$max = 1, :$min = 1) {
        my Step $step .= new: :$min, :$max;
        $step.add-step: $_ for @callables;
        self
    }
}

my class Or {
    has Callable @.options;

    multi method add-option(&opt) {
        @!options.push: &opt
    }

    multi method add-option(@opts) {
        @!options.push: $_ for @opts
    }

    method CALL-ME(\match, |c) {
        # FIXME: what happens if there is no rule as first step?
        for @!options {
            .(match, |c)
        }
    }
}

class Pattern is Method {
    has Str  $.source;
    has Step $.steps handles <add-step> .= new;

    method CALL-ME(\match, |c) {
        $!steps(match, |c)
    }
}
