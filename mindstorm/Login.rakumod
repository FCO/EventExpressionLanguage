########################
# Emits a Login event after getting the login page, 0, 1 or more login tries and a succefull login
########################

event Request is generic-log-entry(&line-to-hash) {
  has Str      $.method;
  has UInt     $.status;
  has Str      $.path;
  has UUID()   $.form-id;
  has DateTime $.timestamp;
  has Str()    %.headers
}

event Login {
  has UUID()   $.session-id;
  has UInt     $.tries;
  has DateTime $.start;
  has DateTime $.end;

  pattern TOP {
    <get=.login-form>
    :my $form-id = $<login-form>.form-id;
    <failures=.login-action-fail($form-id)>*
    <success=.login-action-success($form-id)>
    { $!session-id = $<success>.headers<session-id> }
    { $!tries = $<failures>.elems + 1               }
    { $!start = $<get>.timestamp                    }
    { $!end   = $<success>.timestamp                }
  }

  pattern login-page {
    <req=.Request> <{ $<req>.path eq "/login" }>
  }

  pattern login-form {
    <page=.login-page>
    <{ $<page>.method eq "GET" && $<page>.status == 200 }>
  }

  pattern login-action(UUID() $form-id) {
    <page=.login-page>
    <{ $<page>.method eq "POST" && $<page>.form-id eq $form-id }>
  }

  pattern login-action-fail(UUID() $form-id) {
    <action=.login-action($form-id)>
    <{ $<action>.status div 100 != 2 }>
  }

  pattern login-action-success(UUID() $form-id) {
    <action=.login-action($form-id)>
    <{ $<action>.status div 100 == 2 }>
  }
}

