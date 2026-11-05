use lib 'lib';
use EEL;

event FireRisk {
    has Str  $.area;
    has Int  $.temperature;
    has UInt $.humidity;

    pattern temp(*%attrs) { <.event: :type<temperature>, |%attrs> }
    pattern hum(*%attrs)  { <.event: :type<humidity>,    |%attrs> }

    pattern TOP {
        [ :5min
            <hot=.temp: :value( * > 40 )> { $!area = $<hot>.area }
            <dry=.hum: :$!area, :value( * < 20 )>
            |
            <dry=.hum: :value( * < 20 )>  { $!area = $<dry>.area }
            <hot=.temp: :$!area, :value( * > 40 )>
        ]
        {
            $!temperature = $<hot>.value;
            $!humidity    = $<dry>.value;
        }
    }
}

class Area {
    has Str $.area;
    has Int $.temperature = 25;
    has Int $.humidity    = 25;

    method emit {
        emit %( :type<temperature>, :$!area, :value($!temperature) );
        emit %( :type<humidity>,    :$!area, :value($!humidity)    );
    }

    method next {
        my $dt = (-6 .. 5).pick;
        my $dh = (-5 .. 6).pick;

        $!temperature += $dt;
        $!humidity    += $dh if $!humidity + $dh >= 0;
    }
}

my @areas = (<A E I O U> X~ ^3).map: -> $area {
    Area.new: :$area
}

my $events = supply {
    whenever Supply.interval: .3 {
        for @areas {
            .next;
            .emit;
        }
    }
}

 react whenever $events.match: FireRisk {
     say "area       : { .area }";
     say "temperature: { .temperature }";
     say "humidity   : { .humidity }";
     say "-" x 30;
 }
