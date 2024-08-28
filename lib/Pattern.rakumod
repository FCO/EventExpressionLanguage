my class Step is Callable {
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

class Pattern is Step is Method {
    has Str $.source;

}
