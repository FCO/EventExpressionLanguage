use lib 'lib';
use EEL;

event LoginResult {
    has $.status;
    proto pattern result {*}
    pattern result:sym<success> { <response=.event(:type<response>, :status(200 <= * < 300))> }
    multi pattern result:sym<failure> { <response=.event(:type<response>, :status(* >= 400))> }
    pattern TOP {
        <result>
        { $!status = $<result><response>.status }
    }
}
({type=>'response',status=>200},{type=>'response',status=>401}).Supply.match(LoginResult).tap:
    -> $event { say "login result: {$event.status}" };

# OUTPUT: login result: 200
# OUTPUT: login result: 401
