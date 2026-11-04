use lib 'lib';
use EEL;

# Reemit selects inputs; derived events are always published.
event Alarm {
    has $.message;
    pattern TOP {
        <warning=.event(:type<warning>)>
        { $!message = $<warning>.data<message> }
    }
}
(
    {type => 'debug', message => 'polling'},
    {type => 'info', message => 'ready'},
    {type => 'warning', message => 'overheating'},
).Supply.match(Alarm, :reemit<info>).tap: -> $event {
    if $event ~~ Alarm { say "alarm: {$event.message}" }
    else { say "original: {$event<type>}" }
};
# OUTPUT: original: info
# OUTPUT: alarm: overheating
