use lib "lib";
use EEL;

my Supplier $supplier .= new;
start {
    sleep 2;
    $supplier.emit: %(:type<t1>)
}
event Bla {
    # patterm TOP {
    #     <test=.event: :type<t1>>
    # }

    use Pattern;
    my $pattern = Pattern.bless: :name<TOP>, :source('<test=.event(:type<t1>)>');
    $pattern.add-rule-call: 'event', \(:type<t1>), :store-key<test>;
    ::?CLASS.^add_method: 'TOP', $pattern;
}

react {
    whenever Bla.parse($supplier.Supply) {
        .say
        # TOP: ｢｣ - (<test=.event(:type<t1>)>)
        #    test => event: ｢{type => t1}｣ - (event(...))
    }
}
