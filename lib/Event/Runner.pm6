use QueryStorage;
unit class Event::Runner;

has QueryStorage $.storage  .= new;
has Supply:D     $.input is required;
has              @.rules;
has Supply       $.output;

multi method exec($_ (:$cmd where "query", |), %state = {}) {
#    say "exec add: ", .<query>, %state;
    $!storage.add: .<query>, %( :id(.<id>), :store(.<store> // []), :next(.<next>), :%state )
}

multi method exec($_ (:$cmd where "dispatch", |), %state = {}) {
    emit self.init-event: .<data>.(%state).Hash
}

multi method exec(|c) { die "unrecognised: { c.perl }" }

proto method init-event(% --> Hash()) {*}
multi method init-event(%event (:$timestamp where *.defined, |)) { %event }
multi method init-event(%event) { %( |%event, :timestamp(now) )  }

method run() {
#    dd @!rules;
    for @!rules -> %cmd {
        self.exec: %cmd
    }
    $!output = supply {
        whenever $!input -> %pre-event {
            my %event = self.init-event: %pre-event;
            my @data = $!storage.search: %event;
#            say +@data if @data;
            for @data {
                my %state      = .<state><> // %();
                %state{.<id>}  = %event{|.<store>}:p.Hash if .<id>:exists and .<store>.elems;
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