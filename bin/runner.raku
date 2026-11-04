#!/usr/bin/env raku
use lib 'lib';
use EEL;
event FireRisk {
    has $.area;
    has $.temperature;
    has $.humidity;
    pattern TOP {
        [ :5min
            <hot=.event(:type<temperature>, :value({'>' => 40}))>
            <dry=.event(:type<humidity>, :area($<hot>.data<area>), :value({'<' => 20}))>
            |
            <dry=.event(:type<humidity>, :value({'<' => 20}))>
            <hot=.event(:type<temperature>, :area($<dry>.data<area>), :value({'>' => 40}))>
        ]
        { $!area = $<hot>.data<area>; $!temperature = $<hot>.data<value>; $!humidity = $<dry>.data<value> }
    }
}
({type => 'temperature', value => 45, area => 'north'},
 {type => 'humidity', value => 10, area => 'north'}).Supply.match(FireRisk).tap: -> $risk { say "fire risk: {$risk.area}" };
