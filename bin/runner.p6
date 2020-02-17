#!/usr/bin/env perl6
use lib "lib";
use Event::Runner;

my @rules =
    {
        cmd      => "query",
        query    => %( :type("==" => "temperature"), :value(">" => 40) ),
        id       => "#temp",
        store    => < value area >,
        next     => {
            cmd      => "query",
            query    => %( :type("==" => "humidity"), :value("<" => 20), :area("==" => -> %state { %state<#temp><area> }) ),
            id       => "#hum",
            store    => < value area >,
            next     => {
                cmd      => "dispatch",
                data     => -> %state --> Hash() { :type<fire-risk>, :area(%state<#temp><area>), :temperature(%state<#temp><value>), :humidity(%state<#hum><value>) },
            }
        }
    },
    {
        cmd      => "query",
        query    => %( :type("==" => "humidity"),    :value("<" => 20) ),
        id       => "#hum",
        store    => < value area >,
        next     => {
            cmd      => "query",
            query    => %( :type("==" => "temperature"), :value(">" => 40), :area("==" => -> %state { %state<#hum><area> }) ),
            id       => "#temp",
            store    => < value area >,
            next     => {
                cmd      => "dispatch",
                data     => -> %state --> Hash() { :type<fire-risk>, :area(%state<#temp><area>), :temperature(%state<#temp><value>), :humidity(%state<#hum><value>) },
            }
        }
    }
;

my Supplier $supplier .= new;
my Event::Runner $runner .= new: :supply($supplier.Supply), :@rules;

$runner.run;

multi MAIN() {

    sleep 1;

    $supplier.emit: %(:type<temperature>, :value(45), :area<abc>);

    sleep 1;

    $supplier.emit: %(:type<humidity>, :value(13), :area<abc>);
    sleep 2;
}

multi MAIN("rand") {
    sleep 1;

    loop {
        sleep 1;
        my $event = %(
                :type(<temperature humidity>.pick),
                :value((^100).pick),
                :area(<abc cde efg>.pick)
        );
        dd $event;
        $supplier.emit: $event
    }
}
