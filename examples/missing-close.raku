use lib 'lib';
use EEL;

# A diagnostic raised by FAILGOAL is delivered to quit, including at EOF.
event DelimitedBlock {
    pattern TOP { :!ignore-unexpected <.event(:type<open>)> ~ <.event(:type<close>)> [] }
    method FAILGOAL($goal) { die 'missing closing event' }
}
({type => 'open'},).Supply.match(DelimitedBlock).tap(
    -> $block { say 'complete block' },
    quit => -> $exception { say $exception.message },
);
# OUTPUT: missing closing event
