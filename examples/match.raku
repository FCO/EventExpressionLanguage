use lib 'lib';
use EEL;

event Session {
    has $.id;
    pattern TOP {
        <first=.event(:type<start>)>
        { $!id = $<first>.id }
        <last=.event(:type<finish>, :$!id)>
    }
}
event Flagged {
    has $.id;
    pattern TOP {
        <session=.event(:type(Session), :42id)>
        { $!id = $<session>.id }
    }
}

my $events = (
    { :type<start>,  :42id },
    { :type<start>,  :7id  },
    { :type<finish>, :7id  },
    { :type<finish>, :42id },
).Supply;

react whenever $events.match(Session).match(Flagged, :reemit(Session)) -> $event {
    say "{$event.^name}: {$event.id}";
}
