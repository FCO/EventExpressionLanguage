unit module LogEvents;
use EEL;
our event Login is export {
    has $.id;
    pattern TOP {
        <start=.event(:type<start>)>
        <.event(:type<finish>, :id($<start>.id))>
        { $!id = $<start>.id }
    }
}

our event Heartbeat is export { pattern TOP { <.event(:type<ping>)> } }
