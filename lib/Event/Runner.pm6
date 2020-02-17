use QueryStorage;
unit class Event::Runner;

has QueryStorage $.storage .= new;
has Supply       $.supply;
has              @.rules;

multi method exec($_ (:$cmd where "query", |), %state = {}) {
    say "exec add: ", .<query>, %state;
    $!storage.add: .<query>, %( :id(.<id>), :store(.<store> // []), :next(.<next>), :%state )
}

multi method exec($_ (:$cmd where "dispatch", |), %state = {}) {
    say "dispatch: ", self.init-event: .<data>.(%state)
}

multi method exec(|c) { die "unrecognised: { c.perl }" }

multi method init-event(%event (:$timestamp where *.defined, |)) { %event }
multi method init-event(%event) {
    { |%event, :timestamp(now) }
}

method run() {
    for @!rules -> %cmd {
        self.exec: %cmd
    }
    my Supplier $supplier .= new;
    my $s = start react {
        whenever $!supply -> %pre-event {
            my %event = self.init-event: %pre-event;
            my @data = $!storage.search: %event;
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

                self.exec: .<next>, %state
            }
        }
    }
}