unit module ProtoFixture;
use EEL;
our event Parent {
    proto pattern piece {*}
    pattern piece:sym<a> { <.event(:type<A>)> }
    pattern TOP { <piece> }
}
our event Child is Parent {
    pattern piece:sym<a> { <.event(:type<replacement>)> }
    pattern piece:sym<b> { <.event(:type<B>)> }
}
