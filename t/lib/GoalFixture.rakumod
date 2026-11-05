unit module GoalFixture;
use EEL;
our event Nested {
    pattern TOP {
        :!ignore-unexpected
        <open=.event(:type<open>)> ~ <close=.event(:type<close>)> [ <.TOP> | <.event(:type<text>)> ]*
    }
}
