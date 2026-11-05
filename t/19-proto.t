use lib 'lib';
use Test;
use EEL;
event Family {
    proto pattern item {*}
    pattern item:sym<a> { <source=.event(:type<A>)> }
    multi pattern item:sym<b> { <.event(:type<A>)> }
    pattern TOP { <value=.item> }
}
my @results;
({type=>'A'},).Supply.match(Family).tap(-> $v { @results.push($v) },quit=>-> $e {die $e});
is @results.elems,2,'symbolic candidates produce independent matches';
is @results[0]<value><source>.data<type>,'A','candidate captures are exposed under proto call alias';
my @selected;
event Typed {
    has $.selected;
    multi pattern item(Int $n) { <.event(:value($n))> { $!selected='Int'; @selected.push('Int') } }
    multi pattern item(Numeric $n) { <.event(:value($n))> { $!selected='Numeric'; @selected.push('Numeric') } }
    pattern TOP { <x=.item(2)> { $!selected=$<x>.data<value> } }
}
my @typed;
({value=>2},).Supply.match(Typed).tap(-> $v { @typed.push($v) },quit=>-> $e {note $e.gist});
is @typed.elems,1,'implicit proto dispatches';
is-deeply @selected.Array,['Int'],'most specific signature is selected';
event Fork {
    multi pattern item(Int $n) { [ <.event(:value($n))> | <.event(:value($n))> ] }
    pattern TOP { <x=.item(2)> <.event(:type<end>)> }
}
my @fork;
({value=>2},{type=>'end'}).Supply.match(Fork).tap(-> $v { @fork.push($v) },quit=>-> $e {note $e.gist});
is @fork.elems,2,'candidate pinned across forks';
event Explicit {
    proto pattern choose(|) {*}
    multi pattern choose(Int $n, :$kind = 'A') { <.event(:type($kind), :value($n))> }
    pattern TOP { <choose: 4> }
}
my @explicit;
({type=>'A',value=>4},).Supply.match(Explicit).tap(-> $v { @explicit.push($v) });
is @explicit.elems,1,'explicit signature proto and named defaults';
event Extended is Family { pattern item:sym<c> { <.event(:type<C>)> } }
my @extended;
({type=>'C'},).Supply.match(Extended).tap(-> $v { @extended.push($v) });
is @extended.elems,1,'inherited family accepts new symbolic candidate';
event Entry {
    has $.selected;
    proto pattern TOP {*}
    pattern TOP:sym<a> { <.event(:type<A>)> }
    pattern TOP:sym<b> { <.event(:type<B>)> { $!selected = 'B' } }
}
my @entry;
({type=>'B'},).Supply.match(Entry).tap(-> $v { @entry.push($v) });
is @entry.elems,1,'proto TOP works as entry';
is @entry[0].selected,'B','proto entry preserves selected candidate attributes';
my $defaults=0;
event Defaults {
    multi pattern item(Int $n = do { $defaults++; 3 }) { [ <.event(:value($n))> | <.event(:value($n))> ] }
    pattern TOP { <item> <.event(:type<end>)> }
}
my @defaults;
({value=>3},{type=>'end'}).Supply.match(Defaults).tap(-> $v { @defaults.push($v) });
is @defaults.elems,2,'defaults survive candidate forks';
# A fresh starter may evaluate its own default; each materialization of a fork must not.
is $defaults,2,'default runs once per fresh starter and never during forks';
for ^2 {
    my $p=run $*EXECUTABLE,'-Ilib','-It/lib','-e',
        'use EEL; use ProtoFixture; my @out; ({type=>"A"},{type=>"replacement"},{type=>"B"}).Supply.match(ProtoFixture::Child).tap(-> $v { @out.push($v) }); say @out.elems', :out,:err;
    is $p.out.slurp(:close),"2\n",'precompiled inheritance overrides and extends family';
    is $p.err.slurp(:close),'','precompiled family has no errors';
    is $p.exitcode,0,'precompiled family executes';
}
event Restricted {
    multi pattern choose(Int $n where * > 0, :$kind!) { <.event(:type($kind), :value($n))> }
    pattern TOP { <choose: -1, :kind<A>> }
}
my $failure;
({type=>'A',value=>-1},).Supply.match(Restricted).tap(-> $v {}, quit=>-> $e { $failure=$e });
ok $failure.defined,'incompatible arguments fail dispatch rather than silently failing match';
my $invalid=run $*EXECUTABLE,'-Ilib','-e','use EEL; event Invalid { proto pattern f { <.event> } }',:out,:err;
$invalid.out.slurp(:close);
like $invalid.err.slurp(:close),/'proto pattern must have a {*} body'/,'unsupported proto body has explicit diagnostic';
isnt $invalid.exitcode,0,'unsupported proto body is rejected';
done-testing;
