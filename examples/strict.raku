use lib 'lib';
use EEL;

# Strict invalidates a partial match on noise. Tolerant permits that noise.
event Tolerant {
    has $.id;
    pattern TOP {
        :ignore-unexpected
        <start=.event(:type<start>)> <.event(:type<finish>)>
        { $!id = $<start>.data<id> }
    }
}
event Strict {
    has $.id;
    pattern TOP {
        :!ignore-unexpected
        <start=.event(:type<start>)> <.event(:type<finish>)>
        { $!id = $<start>.data<id> }
    }
}
(
    {type => 'start', id => 1}, {type => 'noise'}, {type => 'finish'},
    {type => 'start', id => 2}, {type => 'finish'},
).Supply.match(Tolerant, Strict).tap: -> $event { say "{$event.^name}: {$event.id}" };
# OUTPUT: Tolerant: 1
# OUTPUT: Tolerant: 2
# OUTPUT: Strict: 2
