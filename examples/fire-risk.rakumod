use lib "lib";
use EEL;

event fire-risk {
    has Rat $.temperature = $<temp><value>;
    has Rat $.humidity    = $<hum><value>;
    has Str $.area        = $<temp><area> // $<hum><area>;

    pattern TOP {
        [
            | <temp> <hum>
            | <hum> <temp>
        ] 5min
        <{ $<temp><area> eq $<hum><area> }>
    }

    pattern temp {
        <temperature=event(:type<temperature>)>
        <{ $<temperature><value> > 40 }>
        { $!area = $<temperature><area> }
    }

    pattern hum {
        <humidity=event(:type<humidity>)>
        <{ $<humidity><value> < 20 }>
        { $!area = $<humidity><area> }
    }
}
