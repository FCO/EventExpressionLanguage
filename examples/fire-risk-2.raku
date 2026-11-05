use lib 'lib';
use EEL;

# The positive assertion captures the area without consuming the reading.
# The same reading can therefore be the first dry/hot event below.
event FireRisk2 {
    has Str $.area;
    has Int $.temperature;
    has Int $.humidity;
    has Absence $.no-rain;

    pattern rain(*%attrs) { <.event: :type<rain>, |%attrs> }
    pattern TOP {
        <data=?event: :area(*.defined)>
        { $!area = $<data>.area }
        [
            :5min
            [
                & <dry=.event: :type<humidity>,    :value(* < 20), :$!area>
                & <hot=.event: :type<temperature>, :value(* > 40), :$!area>
            ]
            <no-rain=!rain: :$!area>
        ]
        {
            $!temperature = $<hot>.value;
            $!humidity = $<dry>.value;
            $!no-rain = $<no-rain>;
        }
    }
}

my @readings =
    # A reaches both thresholds. Rain in another area does not invalidate A.
    %(timestamp=>0,   type=>'temperature', area=>'A', value=>45),
    %(timestamp=>30,  type=>'humidity',    area=>'A', value=>15),
    %(timestamp=>60,  type=>'rain',        area=>'elsewhere'),
    # Input advances the watermark past A's inclusive deadline (300).
    %(timestamp=>301, type=>'heartbeat'),
    # B reaches both thresholds, but rain cancels its pending absence.
    %(timestamp=>400, type=>'humidity',    area=>'B', value=>12),
    %(timestamp=>410, type=>'temperature', area=>'B', value=>46),
    %(timestamp=>420, type=>'rain',        area=>'B'),
    # C demonstrates the explicitly selected EOF confirmation policy.
    %(timestamp=>700, type=>'temperature', area=>'C', value=>43),
    %(timestamp=>730, type=>'humidity',    area=>'C', value=>18);

@readings.Supply.match(FireRisk2).tap: -> $risk {
    say "{$risk.area}: temperature={$risk.temperature}, humidity={$risk.humidity}, no-rain={$risk.no-rain.reason}";
};
# OUTPUT: A: temperature=45, humidity=15, no-rain=window
# OUTPUT: C: temperature=43, humidity=18, no-rain=eof
# EOF confirms absence over the observed input; it does not mean five minutes
# were observed for C. B is intentionally absent from the output.
