use lib "lib";
use EEL;

my Supplier $supplier .= new;
start {
    sleep 2;
    $supplier.emit: %(:type<t1>)
}
event Bla {
    method TOP {
        $.event: :type("==" => "t1")
    }
}

react {
    whenever Bla.parse($supplier.Supply) -> $event {
        say '-' x 30, "> $event.gist()"
    }
}
