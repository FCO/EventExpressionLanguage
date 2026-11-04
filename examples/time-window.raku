use lib 'lib';
use EEL;

# Decimal duration in event time; logs may be replayed immediately.
event Transfer {
    has $.id;
    pattern TOP {
        [ :1.5h
            <start=.event(:type<started>)>
            <.event(:type<finished>, :id($<start>.data<id>))>
        ]
        { $!id = $<start>.data<id> }
    }
}
({type => 'started', id => 7, timestamp => 0}, {type => 'finished', id => 7, timestamp => 3600})
    .Supply.match(Transfer).tap: -> $transfer { say "transfer {$transfer.id}: within 1.5h" };
# OUTPUT: transfer 7: within 1.5h
