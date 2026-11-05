use lib 'lib';
use EEL;

# A subclasse amplia a família sem reescrever TOP.
event Notice {
    has $.level;
    proto pattern entry {*}
    pattern entry:sym<info> { <raw=.event(:type<log>, :level<info>)> }
    pattern entry:sym<error> { <raw=.event(:type<log>, :level<error>)> }
    pattern TOP {
        <entry>
        { $!level = $<entry><raw>.level }
    }
}
event DebugNotice is Notice {
    pattern entry:sym<debug> { <raw=.event(:type<log>, :level<debug>)> }
}
my $error;
({type=>'log',level=>'info'},{type=>'log',level=>'debug'},{type=>'log',level=>'error'}).Supply.match(DebugNotice).tap(
    -> $event { say "notice: {$event.level}" },
    quit => -> $failure { $error=$failure },
);
$error.throw if $error.defined;
# OUTPUT: notice: info
# OUTPUT: notice: debug
# OUTPUT: notice: error
