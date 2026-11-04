use lib 'lib';
use EEL;
event Knock {
    has $.ip;
    pattern TOP {
        :partition{ .<ip> }
        :!ignore-unexpected
        <first=.event(:port(1))>
        <.event(:port(2))>
        { $!ip = $<first>.ip }
    }
}
my $error;
({ip=>'A',port=>1},{ip=>'B',port=>1},{ip=>'B',port=>9},{ip=>'A',port=>2}).Supply.match(Knock).tap(
    -> $event { say "knock: {$event.ip}" }, quit=>-> $e { $error=$e });
$error.throw if $error.defined;
# OUTPUT: knock: A
