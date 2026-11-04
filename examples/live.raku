use lib 'lib';
use EEL;

# Subscribe before emitting on a live Supply. No sleeps or background tasks needed.
event SessionClosed {
    has $.id;
    pattern TOP {
        <connection=.event: :type<connected>>
        { $!id = $<connection>.id }
        <.event: :type<disconnected>, :$!id>
    }
}
my $source = Supplier.new;
my $tap = $source.Supply.match(SessionClosed, :reemit<heartbeat>).tap: -> $event {
    say $event ~~ SessionClosed ?? "closed: {$event.id}" !! 'heartbeat';
};
$source.emit({type => 'connected', id => 42});
$source.emit({type => 'heartbeat'});
$source.emit({type => 'disconnected', id => 42});
$source.done;
$tap.close;
# OUTPUT: heartbeat
# OUTPUT: closed: 42
