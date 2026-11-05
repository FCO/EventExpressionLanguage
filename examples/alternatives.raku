use lib 'lib';
use EEL;

# Forked paths can use the same initial capture and produce different outcomes.
event Decision {
    has $.id;
    has $.status;
    pattern TOP {
        :!ignore-unexpected
        <request=.event(:type<request>)>
        [
            <approved=.event(:type<approved>, :id($<request>.id))>
            |
            <declined=.event(:type<declined>, :id($<request>.id))>
        ]
        { $!id = $<request>.id; $!status = $<approved>.defined ?? 'approved' !! 'declined' }
    }
}
(
    {type => 'request', id => 'A'}, {type => 'approved', id => 'A'},
    {type => 'request', id => 'B'}, {type => 'declined', id => 'B'},
).Supply.match(Decision).tap: -> $event { say "{$event.id}: {$event.status}" };
# OUTPUT: A: approved
# OUTPUT: B: declined
