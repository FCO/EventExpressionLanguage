use EEL::Input;
unit class EEL::Reemit;

has Bool $!all = False;
has @!selectors;

submethod BUILD(:$selection = False) {
    if $selection ~~ Bool:D {
        $!all = $selection;
        return;
    }
    my @selectors = $selection ~~ Positional:D ?? $selection.list !! ($selection,);
    for @selectors -> $selector {
        die ':reemit expects Bool, an event name/type, or a list of names/types'
            unless $selector ~~ Str:D || !$selector.DEFINITE;
    }
    @!selectors = @selectors;
}
method accepts($input, $view = snapshot($input) --> Bool) {
    $!all || @!selectors.first({ selected-kind($input, $_, $view) }, :k).defined
}
