use lib 'lib';
use EEL;

# Three equivalent ways to filter the value field. Blocks receive the field,
# not the whole event, as their argument/topic.
event ByMap { pattern TOP { <.event(:value({'>' => 40}))> } }
event ByWhatever { pattern TOP { <.event(:value(* > 40))> } }
event ByBlock { pattern TOP { <.event(:value{$_ > 40})> } }

({value => 35}, {value => 45}, {other => 99}).Supply
    .match(ByMap, ByWhatever, ByBlock)
    .tap: -> $event { say $event.^name };
# OUTPUT: ByMap
# OUTPUT: ByWhatever
# OUTPUT: ByBlock
