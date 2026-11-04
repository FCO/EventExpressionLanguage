use lib 'lib';
use EEL;

event Bracketed {
    has $.from;
    has $.to;
    pattern TOP {
        :!ignore-unexpected
        <open=.event(:type<open>)> ~ <close=.event(:type<close>)> [
            <children=.TOP> | <text>
        ]*
        { $!from = $<open>.data<index>; $!to = $<close>.data<index> }
    }
    pattern text {
        <.event(:type<text>)>
    }
}

my $input = (
    {type => 'open',  index => 0},
    {type => 'text',  index => 1},
    {type => 'open',  index => 2},
    {type => 'text',  index => 3},
    {type => 'close', index => 4},
    {type => 'close', index => 5},
).Supply;

$input.match(Bracketed).tap: -> $block {
    say "closed block {$block.from}..{$block.to}, children: {$block<children>.elems}";
};
