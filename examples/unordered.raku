use lib 'lib';
use EEL;
event Both {
    pattern TOP {
        :!ignore-unexpected
        & [ <.event(:type<A>)> <.event(:type<B>)> ]
        & [ <.event(:type<C>)> <.event(:type<D>)> ]
    }
}
my $error;
(<C D A B>.map({ %(type=>$_) })).Supply.match(Both).tap(
    -> $event { say 'both complete' }, quit=>-> $e { $error=$e });
$error.throw if $error.defined;
# OUTPUT: both complete
