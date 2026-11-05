unit module CLIInferred;
use EEL;

our event CLIInferred is export {
    pattern TOP { <.event(:type<inferred>)> }
}

our event Additional is export(:extra) {
    pattern TOP { <.event(:type<additional>)> }
}

our event Hidden {
    pattern TOP { <.event(:type<hidden>)> }
}
