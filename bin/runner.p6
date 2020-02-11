#!/usr/bin/env perl6

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

use lib "lib";
use QueryStorage;
my QueryStorage $storage .= new;

multi exec($_ (:$cmd where "query", |), %state = {}) {
    say "exec add: ", .<query>, %state;
    $storage.add: .<query>, %( :id(.<id>), :store(.<store> // []), :next(.<next>), :%state )
}

multi exec($_ (:$cmd where "dispatch", |), %state = {}) {
    say "dispatch: ", .<data>.(%state)
}

multi exec(|c) { die "unrecognised: { c.perl }" }

multi MAIN() {
    for @rules -> %cmd {
            exec %cmd
    }
    my Supplier $supplier .= new;
    my $s = start react {
        whenever $supplier.Supply -> %event {
            my @data = $storage.search: %event;
            say +@data if @data;
            for @data {
                my %state = .<state><> // %();
                %state{.<id>} = %event{|.<store>}:p.Hash if .<id>:exists and .<store>.elems;
                .<next><query> = .<next><query>.kv.map(-> $key, $_ {
                        $key => (
                                .key => .value ~~ Callable
                                        ?? .value.(%state)
                                        !! .value
                                )
                    }).Hash;

                exec .<next>, %state
            }
        }
    }

    sleep 1;

    $supplier.emit: %(:type<temperature>, :value(45), :area<abc>);

    sleep 1;

    $supplier.emit: %(:type<humidity>, :value(13), :area<abc>);
    sleep 2;
}

multi MAIN("rand") {
    for @rules -> %cmd {
        exec %cmd
    }
    my Supplier $supplier .= new;
    my $s = start react {
        whenever $supplier.Supply -> %event {
            my @data = $storage.search: %event;
            for @data {
                my %state = .<state><> // %();
                %state{.<id>} = %event{|.<store>}:p.Hash if .<id>:exists and .<store>.elems;
                .<next><query> = .<next><query>.kv.map(-> $key, $_ {
                    $key => (
                            .key => .value ~~ Callable
                                    ?? .value.(%state)
                                    !! .value
                            )
                }).Hash;

                exec .<next>, %state
            }
        }
    }

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
