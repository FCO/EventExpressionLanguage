use lib "lib";
use EEL;

my Supplier $supplier .= new;

event Bla {
    # patterm TOP {
    #     <test1=.event(:type<t1>)>
    #     <test2=.event(:type<t2>)>
    # }

    use Pattern;
    my $pattern = Pattern.bless: :name<TOP>, :source('<test1=.event(:type<t1>)>␤<test2=.event(:type<t2>)>');
    $pattern.add-rule-call: 'event', \(:type<t1>), :store-key<test1>;
    $pattern.add-rule-call: 'event', \(:type<t2>), :store-key<test2>;
    ::?CLASS.^add_method: 'TOP', $pattern;
}

# Enter events
start {
    sleep 2;
    $supplier.emit: %(:type<t1>);
    sleep 2;
    $supplier.emit: %(:type<t2>);
}

react {
    whenever Bla.parse($supplier.Supply) {
        .say
        # TOP: ｢｣   # <test1=.event(:type<t1>)>␤<test2=.event(:type<t2>)>
        #     test1 => event: ｢{type => t1}｣   # event(...)
        #     test2 => event: ｢{type => t2}｣   # event(...)
    }
}
