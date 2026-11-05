use lib 'lib';
use EEL;
event Samples {
    pattern all { :5s :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+ }
    pattern first { :5s :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+? }
    pattern last { :5s :!ignore-unexpected <.event(:type<S>)> <items=.event(:type<A>)>+! }
}
# The timestamp, not how quickly these lines are processed, advances the window.
my @input={type=>'S',timestamp=>0},{type=>'A',timestamp=>1},{type=>'A',timestamp=>2},{type=>'X',timestamp=>6};
for <all first last> -> $rule {
    my @counts; my $error;
    @input.Supply.match(Samples,:$rule).tap(-> $event { @counts.push($event<items>.elems) },quit=>-> $e { $error=$e });
    $error.throw if $error.defined;
    say "$rule: {@counts.join(', ')}";
}
# OUTPUT: all: 1, 2
# OUTPUT: first: 1, 2
# OUTPUT: last: 1, 2
