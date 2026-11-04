unit module SlangFixture;
use EEL;

our event Reusable {
    pattern TOP(Int $n = 42) {
        :my $value = $n;
        :partition{ .<a>, .<b> }
        <item=.event(:$value)>
    }
}
