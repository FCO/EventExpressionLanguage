unit module MatchFixture;
use EEL;
our event Ping { pattern TOP { <.event(:type<ping>)> } }
sub output(Supply $input) is export { $input.match(Ping) }
