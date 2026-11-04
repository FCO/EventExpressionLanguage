use lib 'lib';
use EEL;

# Match a Raku class (including subclasses) and filter its public attributes.
class Temperature { has $.sensor; has $.value }
class CalibratedTemperature is Temperature { }
event Hot {
    has $.sensor;
    has $.value;
    pattern TOP {
        <reading=.event(:type(Temperature), :value({'>' => 40}))>
        { $!sensor = $<reading>.data.sensor; $!value = $<reading>.data.value }
    }
}
(
    Temperature.new(:sensor<kitchen>, :value(35)),
    CalibratedTemperature.new(:sensor<kitchen>, :value(45)),
    Temperature.new(:sensor<garage>, :value(48)),
).Supply.match(Hot).tap: -> $hot { say "{$hot.sensor}: {$hot.value}" };
# OUTPUT: kitchen: 45
# OUTPUT: garage: 48
