use lib 'lib';
use EEL;

event Session {
    has $.id;
    pattern TOP {
        <first=.event(:type<start>)>
        <last=.event(:type<finish>, :id($<first>.data<id>))>
        { $!id = $<first>.data<id> }
    }
}

my $input = (
    {type => 'start',  id => 1},
    {type => 'start',  id => 2},
    {type => 'noise'},
    {type => 'finish', id => 2},
    {type => 'finish', id => 1},
).Supply;

$input.match(Session).tap: -> $session {
    say "session {$session.id} completed";
};
