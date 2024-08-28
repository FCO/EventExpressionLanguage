########################
# Emits a Login event after getting the login page, 0, 1 or more login tries and a succefull login
########################

event Login {
  has UUID()   $.session-id;
  has UInt     $.tries;
  has DateTime $.start;
  has DateTime $.end;

  pattern TOP {
    <get=.login-form>
    :my $form-id = $<login-form>.data<form-id>;
    <failures=.login-action-fail($form-id)>*
    <success=.login-action-success($form-id)>

    { $!session-id = $<success><headers><session-id> }
    { $!tries = $<failures>.elems + 1                }
    { $!start = $<get><timestamp>                    }
    { $!end   = $<success><timestamp>                }
  }

  pattern login-page(*%pars) {
    <req=.event(:path</login>, |%pars)>
  }

  pattern login-form {
    <page=.login-page(:method<GET>, :200status)>
  }

  pattern login-action(UUID() $form-id, *%pars) {
    <page=.login-page(:method<POST>, "data.form-id" => $form-id, |%pars)>
  }

  pattern login-action-fail(UUID() $form-id) { 
    <action=.login-action($form-id, :status['<' => 200, '>=' => 300])>
  }

  pattern login-action-success(UUID() $form-id) {
    <action=.login-action($form-id, :status{'>=' => 200, '<' => 300})>
  }
}

