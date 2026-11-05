use lib 'lib';
use EEL;
event Pair {
    has $.id;
    pattern TOP {
        (<request=.event(:type<start>)>)
        (<response=.event(:type<finish>)>)
        { $!id = $0<request>.id }
    }
}
my $error;
({type=>'start',id=>42},{type=>'finish',id=>42}).Supply.match(Pair).tap(
    -> $event { say "pair {$event.id}: {$event[0]<request>.id} -> {$event[1]<response>.id}" },
    quit=>-> $e { $error=$e });
$error.throw if $error.defined;
# OUTPUT: pair 42: 42 -> 42
