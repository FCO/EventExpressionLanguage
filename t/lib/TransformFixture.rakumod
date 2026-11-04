unit module TransformFixture;
use EEL;
my sub hidden(Str $line, :$origin!, :$line-number!) is export {
    %(type=>'inferred',timestamp=>$line-number)
}
our sub invalid(Str $line, *%) { [{type=>'inferred',timestamp=>1},42] }
our sub endless(Str $line, *%) { (1..Inf).List }
our class Measured {
    has $.id = 7;
    has $.type = 'measured';
    has $.timestamp = 1;
    has Int $!reads = 0;
    method id { die 'getter evaluated twice' if ++$!reads > 1; $!id }
}
our $last;
our sub measured(Str $line, *%) { $last = Measured.new }
our event Seen {
    pattern TOP { <capture=.event(:type<measured>, :id(7))> { die 'input identity changed' unless $<capture>.data === $last } }
}
