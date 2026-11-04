use lib 'lib';
use Test;
use EEL;
use EEL::Runner;
sub recognize($type, @input) {
    my @out;
    my $failure;
    @input.Supply.match($type).tap(-> $value { @out.push($value) }, quit=>-> $error { $failure=$error });
    $failure.throw if $failure.defined;
    @out
}
event Branches {
    proto pattern branch {*}
    pattern branch:sym<b> { <start=.event(:type<A>)> <end=.event(:type<B>)> }
    pattern branch:sym<c> { <start=.event(:type<A>)> <end=.event(:type<C>)> }
    pattern TOP { :!ignore-unexpected <result=.branch> }
}
my @branches=recognize(Branches,[{type=>'A',id=>7},{type=>'C',id=>8}]);
is @branches.elems,1,'failure of one strict candidate does not invalidate sibling';
is @branches[0]<result><start>.id,7,'candidate retains initial capture after fork';
is @branches[0]<result><end>.id,8,'surviving candidate captures final input';
event Silent {
    proto pattern item {*}
    pattern item:sym<x> { <raw=.event(:type<X>)> }
    pattern TOP { <.item> }
}
my @silent=recognize(Silent,[{type=>'X'}]);
is @silent.elems,1,'silent proto still recognizes';
is @silent[0].hash.elems,0,'silent proto exposes no capture';
event Tree {
    proto pattern node {*}
    pattern node:sym<leaf> { <leaf=.event(:type<leaf>)> }
    pattern node:sym<group> { <open=.event(:type<open>)> <child=.node> <close=.event(:type<close>)> }
    pattern TOP { :!ignore-unexpected <tree=.node> }
}
my @trees=recognize(Tree,[{type=>'open'},{type=>'leaf',id=>42},{type=>'close'}]);
my @groups=@trees.grep({ .<tree>.hash<child>:exists });
is @groups.elems,1,'recursive family completes enclosing candidate';
is @groups[0]<tree><child><leaf>.id,42,'recursive proto captures remain nested';
event BadRecursion {
    proto pattern item {*}
    pattern item:sym<loop> { <item> }
    pattern TOP { <item> }
}
throws-like { EEL::Runner.new(:patterns[BadRecursion]) },X::AdHoc,
    message=>/'recurse without consuming'/,'recursion through proto is validated';
event Filtered {
    multi pattern item(Int $n where * > 0, :$source!, *%filters) {
        <raw=.event(:type($source), :value($n), |%filters)>
    }
    pattern TOP { <item: 3, :source<sensor>, :status(200)> }
}
my @filtered=recognize(Filtered,[{type=>'sensor',value=>3,status=>500},{type=>'sensor',value=>3,status=>200}]);
is @filtered.elems,1,'where constraint, required named parameter and slurpy filters compose';
is @filtered[0]<item><raw>.status,200,'slurpy named filter reaches event query';
my $error;
event MissingNamed {
    multi pattern item(Int $n, :$source!) { <.event(:type($source), :value($n))> }
    pattern TOP { <item: 3> }
}
({type=>'sensor',value=>3},).Supply.match(MissingNamed).tap(-> $v {},quit=>-> $e { $error=$e });
ok $error.defined,'missing required named argument reports dispatch error';
done-testing;
