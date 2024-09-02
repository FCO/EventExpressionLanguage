use lib "lib";
use EEL;

my Supplier $supplier .= new;
start {
    sleep 2;
    $supplier.emit: %(:type<t1>)
}
event Bla {
    use Pattern;
    my $pattern = Pattern.bless: :name<TOP>, :source('<test=.event(:type<t1>)>');
    $pattern.add-rule-call: 'event', \(:type<t1>), :store-key<test>;
    ::?CLASS.^add_method: 'TOP', $pattern;
    say $pattern.list-steps;

    # method TOP {
    #     $.event: :type<t1>
    # }
}

react {
    whenever Bla.parse($supplier.Supply) {
        .say
    }
}
