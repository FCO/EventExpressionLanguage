use lib 'lib';
use EEL;
event Transfer {
    has $.id;
    pattern TOP {
        :5s
        <start=.event(:type<start>)>
        <.event(:type<finish>, :id($<start>.id))>
        { $!id=$<start>.id }
    }
}
# Arrival order is finish, start, tick. Lateness allows the engine to reorder it.
my $error;
({type=>'finish',id=>42,timestamp=>2},{type=>'start',id=>42,timestamp=>0},{type=>'tick',timestamp=>4}).Supply.match(Transfer,:lateness(2)).tap(
    -> $transfer { say "historical transfer: {$transfer.id}" },quit=>-> $e { $error=$e });
$error.throw if $error.defined;
# OUTPUT: historical transfer: 42
