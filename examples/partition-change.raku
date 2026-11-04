use lib 'lib';
use EEL;
event Purchase {
    has $.customer;
    pattern TOP {
        :partition{ .<customer> }
        :!ignore-unexpected
        <order=.event(:type<order>)>
        [ :partition{ .<order> } <.event(:type<paid>)> ]
        <.event(:type<notified>)>
        { $!customer = $<order>.customer }
    }
}
my $error;
({type=>'order',customer=>1,order=>4},
 {type=>'paid',customer=>2,order=>9},
 {type=>'paid',customer=>2,order=>4},
 {type=>'notified',customer=>1}).Supply.match(Purchase).tap(
    -> $event { say "purchase: customer {$event.customer}" }, quit=>-> $e { $error=$e });
$error.throw if $error.defined;
# OUTPUT: purchase: customer 1
