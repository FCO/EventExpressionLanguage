use lib 'lib';
use EEL;
event Interleave {
    pattern TOP {
        :5s :!ignore-unexpected
        &&& [ <a=.event(:type<A>)> <b=.event(:type<B>)> ]
        &&& [ <c=.event(:type<C>)> <d=.event(:type<D>)> ]
    }
}
my $error;
(<A C B D>.kv.map(-> $time,$type { %(:$type,timestamp=>$time) })).Supply.match(Interleave).tap(
    -> $event { say "interleaved: {$event<a>.data<type>} {$event<c>.data<type>} {$event<b>.data<type>} {$event<d>.data<type>}" },
    quit=>-> $e { $error=$e });
$error.throw if $error.defined;
# OUTPUT: interleaved: A C B D
