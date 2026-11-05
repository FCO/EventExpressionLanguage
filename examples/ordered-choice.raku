use lib 'lib';
use EEL;
event Priority {
    pattern TOP {
        :!ignore-unexpected
        || [ <start=.event(:type<A>)> <.event(:type<B>)> ]
        || <start=.event(:type<A>)>
    }
}
my $source=Supplier.new;
my @out;
my $error;
my $tap=$source.Supply.match(Priority).tap(-> $event { @out.push($event) }, quit=>-> $e {$error=$e});
$source.emit({type=>'A',id=>42});
say "before EOF: {@out.elems}";
$source.done;
$error.throw if $error.defined;
say "after EOF: {@out.elems}, id {@out[0]<start>.id}";
$tap.close;
# OUTPUT: before EOF: 0
# OUTPUT: after EOF: 1, id 42
