use QueryStorage;
unit class Event::Runner;

has QueryStorage $.storage  .= new;
has Supply:D     $.input is required;
has              @.rules;
has Supply       $.output;

multi method exec($_ (:$cmd where "query", |), %state = {}) {
#    say "exec add: ", .<query>, %state;
    $!storage.add: .<query>.clone, %( :id(.<id>), :store(.<store> // []), :next(.<next>), :%state.clone )
}

multi method exec($_ (:$cmd where "dispatch", |), %state = {}) {
    emit self.init-event: .<data>.(%state).Hash
}

multi method exec(|c) { die "unrecognised: { c.perl }" }

proto method init-event(% --> Hash()) {*}
multi method init-event(%event (:$timestamp where *.defined, |)) { %event }
multi method init-event(%event) { %( |%event, :timestamp(now) )  }

method run() {
    for @!rules -> %cmd {
        self.exec: %cmd
    }
    $!output = supply {
        whenever $!input -> %pre-event {
            my %event = self.init-event: %pre-event;
            my @data = $!storage.search: %event;
            for @data {
                my %resp           = .clone;
                my %state          = %resp<state><> // %();
                with %resp<id> {
                    my @store = %resp<store>.grep: { .defined } if %resp<store>;
                    if @store {
                        %state{$_} = %(%event{@store}:p) if %event{@store}:exists
                    }
                }
                my %next           = %resp<next>.clone;
                %next<query>       = %next<query>.clone.kv.map(-> $key, $_ {
                    $key => (
                        .key => .value ~~ Callable
                                ?? .value.(%state)
                                !! .value
                        )
                }).Hash;
                self.exec: %next, %state
            }
        }
    }
}