use lib 'lib';
use EEL;
event Login {
    has Str $.session-id;
    has UInt $.tries;
    has DateTime $.start;
    has DateTime $.end;
    pattern TOP {
        :!ignore-unexpected
        <get=.login-form>
        :my $form-id = $<get><request>.data<form-id>;
        <failures=.login-failure($form-id)>*
        <success=.login-success($form-id)>
        {
            $!session-id = $<success><request>.data<session-id>;
            $!tries = $<failures>.elems + 1;
            $!start = $<get><request>.data<timestamp>;
            $!end = $<success><request>.data<timestamp>;
        }
    }
    pattern login-form {
        <request=.event(:type<request>, :path</login>, :method<GET>, :status(200))>
    }
    pattern login-failure(Str $form-id) {
        <request=.event(:type<request>, :path</login>, :method<POST>, :$form-id, :status({'<' => 200}))>
        |
        <request=.event(:type<request>, :path</login>, :method<POST>, :$form-id, :status({'>=' => 300}))>
    }
    pattern login-success(Str $form-id) {
        <request=.event(:type<request>, :path</login>, :method<POST>, :$form-id, :status({'>=' => 200, '<' => 300}))>
    }
}
(
    {type => 'request', path => '/login', method => 'GET', status => 200, form-id => 'form-1', timestamp => DateTime.new('2026-01-01T00:00:00Z')},
    {type => 'request', path => '/login', method => 'POST', status => 401, form-id => 'form-1', timestamp => DateTime.new('2026-01-01T00:00:01Z')},
    {type => 'request', path => '/login', method => 'POST', status => 200, form-id => 'form-1', session-id => 'session', timestamp => DateTime.new('2026-01-01T00:00:02Z')},
).Supply.match(Login).tap: -> $login { say "login {$login.session-id}: {$login.tries} tries" };
