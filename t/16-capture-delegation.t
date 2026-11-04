use lib 'lib';
use Test;
use EEL;
use Event;
class Request {
    has $.id;
    method describe($prefix, :$suffix = '') { "$prefix$!id$suffix" }
}
my %raw = id=>42, optional=>Nil, data=>'domain data', timestamp=>123;
my $capture=Event.new(:data(%raw));
is $capture.id,42,'hash field is available as method';
ok !$capture.optional.defined,'existing undefined hash field is returned';
ok $capture.data === %raw,'capture data method wins collision';
ok $capture.timestamp ~~ Instant,'capture metadata wins collision';
is $capture.data<timestamp>,123,'colliding field remains explicitly accessible';
throws-like { $capture.missing },X::Method::NotFound,'missing hash field throws';
throws-like { $capture.id(1) },X::Method::NotFound,'hash field does not silently discard arguments';
my $request=Request.new(:id(7));
my $object-capture=Event.new(:data($request));
is $object-capture.id,7,'object accessor is delegated';
is $object-capture.describe('request-', :suffix<!>),'request-7!','positional and named arguments forwarded';
ok $object-capture.data === $request,'delegation preserves object identity';
throws-like { $object-capture.missing },X::Method::NotFound,'object missing method throws';
throws-like { Event.new.missing },X::Method::NotFound,'empty capture fails without recursion';
event Session {
    has $.request-id;
    pattern TOP {
        <request=.event(:type<request>)>
        <.event(:type<response>, :id($<request>.id))>
        { $!request-id = $<request>.id }
    }
}
my @out;
({type=>'request',id=>9},{type=>'response',id=>9}).Supply.match(Session).tap(-> $v { @out.push($v) });
is @out.elems,1,'delegated field works in subsequent query';
is @out[0].request-id,9,'delegated field works in action';
is @out[0]<request>.id,9,'emitted capture retains delegation';
event ObjectSession {
    has $.request-id;
    pattern TOP {
        <request=.event(:type(Request))>
        { $!request-id = $<request>.id }
    }
}
my @objects;
($request,).Supply.match(ObjectSession).tap(-> $v { @objects.push($v) });
is @objects.elems,1,'typed object still matches';
is @objects[0].request-id,7,'object capture delegates within action';
ok @objects[0]<request>.data === $request,'runtime capture preserves original object';
event Own { has $.id = 'own' }
is Own.new(:data({id=>'payload'})).id,'own','declared event accessor wins over payload';
done-testing;
