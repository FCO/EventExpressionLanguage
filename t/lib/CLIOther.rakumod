unit module CLIOther;
use EEL;
our event Login { pattern TOP { <.event(:type<other>)> } }
my event Exported is export { pattern TOP { <.event(:type<exported>)> } }
our package Group {
    our event Nested { pattern TOP { <.event(:type<nested>)> } }
}
our event Noisy {
    has $.value;
    pattern TOP { <.event(:type<noisy>)> { say 'action diagnostic'; $!value = 3 } }
}
our event Cyclic {
    has $.cycle;
    pattern TOP { <.event(:type<cycle>)> { my %cycle; %cycle<self> := %cycle; $!cycle = %cycle } }
}
