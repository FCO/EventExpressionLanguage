unit module RunnerFixture;
use EEL;

our event Flow {
    has $.id;
    pattern TOP {
        <first=.event(:type<start>)>
        :my $id = $<first>.data<id>;
        <.finish($id)>
        { $!id = $id }
    }
    pattern finish(Int $id) { <.event(:type<finish>, :$id)> }
}
