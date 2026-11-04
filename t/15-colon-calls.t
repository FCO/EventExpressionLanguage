use lib 'lib';
use Test;
use EEL;
event Calls {
    pattern colon { <bla: :ble> }
    pattern parens { <bla(:ble)> }
    pattern complex { <named=.bla: 42, :value(* > 40), :text('>')> <.bla: :!ble> }
    pattern blocks { <.bla: :value{$_ > 40}, :items([1, 2, 3])> }
    pattern TOP { <request=.event: :type<request>, :value(* > 40)> }
}
my $colon=Calls.new.colon.children[0].children[0];
my $parens=Calls.new.parens.children[0].children[0];
is $colon.name,$parens.name,'same called rule';
is-deeply $colon.code.().hash,$parens.code.().hash,'same arguments';
my $complex=Calls.new.complex.children[0].children[0];
my $args=$complex.code.();
is $args.list[0],42,'positional argument';
ok $args.hash<value>(41),'callable argument containing greater-than';
is $args.hash<text>,'>','quoted delimiter';
is $complex.properties<capture>,'named','capture alias retained';
my $block-call=Calls.new.blocks.children[0].children[0];
ok $block-call.code.().hash<value>(41),'block predicate remains ordinary Raku';
is-deeply $block-call.code.().hash<items>,[1,2,3],'nested array argument';
my $silent=Calls.new.complex.children[0].children[1];
is $silent.properties<capture>,'','silent call stays silent';
is $silent.code.().hash<ble>,False,'negated named argument';
my @out;
({type=>'request',value=>41},).Supply.match(Calls).tap(-> $event { @out.push($event) });
is @out.elems,1,'colon call runs through matcher';
is @out[0]<request>.data<value>,41,'capture retains input';
done-testing;
