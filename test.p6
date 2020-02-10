[
    [
        {
            cmd      => "query",
            query    => %( :type("==" => "temperature"), :value(">" => 40) ),
            id       => "#temp",
            store    => < value area >,
        }, {
            cmd      => "query",
            query    => %( :type("==" => "humidity"), :value("<" => 20), :area("==" => -> %state { %state<#temp><area> }) ),
            id       => "#hum",
            store    => < value area >,
        }, {
            cmd      => "dispatch",
            dispatch => "fire-risk",
            data     => -> %state --> Hash() { :temperature(%state<#temp>.value), :humidity(%state<#hum>.value) },
        }
    ], [
        {
            cmd      => "query",
            query    => %( :type("==" => "humidity"),    :value("<" => 20) ),
            id       => "#hum",
            store    => < value area >,
        }, {
            cmd      => "query",
            query    => %( :type("==" => "temperature"), :value(">" => 40), :area("==" => -> %state { %state<#hum><area> }) ),
            id       => "#temp",
            store    => < value area >,
        }, {
            cmd      => "dispatch",
            dispatch => "fire-risk",
            data     => -> %state --> Hash() { :temperature(%state<#temp>.value), :humidity(%state<#hum>.value) },
        }
    ]
]

# BEGIN
$storage.add:
    %( :type("==" => "temperature"), :value(">" => 40) ),
    %(:id<#temp>, :track<fire-risk>, :sub-track(0), :pos(0), :store< value area >, :state(%()))
;
$storage.add:
    %( :type("==" => "humidity"),    :value("<" => 20) ),
    %(:id<#hum>,  :track<fire-risk>, :sub-track(1), :pos(0), :store< value area >, :state(%()))
;

# ON temperature
$storage.add:
    %( :type("==" => "humidity"),    :value("<" => 20), :area(-> %state { %state<#temp><area> }) ),
    %(:id<#hum>,  :track<fire-risk>, :sub-track(0), :pos(1), :store< value area >, :state(%()))
;

# ON humidity
$storage.add:
    %( :type("==" => "temperature"), :value(">" => 40), :area(-> %state { %state<#hum><area> }) ),
    %(:id<#temp>, :track<fire-risk>, :sub-track(1), :pos(1), :store< value area >, :state(%()))
;
