use lib 'lib';
use EEL;

# Independent matches can wait for payments in a different order.
event PaidOrder {
    has $.id;
    pattern TOP {
        <order=.event: :type<order>>
        { $!id = $<order>.id }
        <payment=.event: :type<payment>, :$!id>
    }
}

my Supply $events .= from-list:
    { :type<order>  , :id<A>       },
    { :type<order>  , :id<B>       },
    { :type<payment>, :id<unknown> },
    { :type<payment>, :id<B>       },
    { :type<payment>, :id<A>       },
;

$events.match(PaidOrder).tap: -> $order { say "paid: {$order.id}" };
# OUTPUT: paid: B
# OUTPUT: paid: A
