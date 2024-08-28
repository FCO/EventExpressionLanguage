use lib 'lib';
use EEL;
event knocked-the-secret {
  has $.ip;

  pattern TOP {
    <first=.event(:type<request>, :1port)> { $!ip = $<first><ip> }
    <.event(:type<request>, :2port, :$!ip)>
    <.event(:type<request>, :3port, :$!ip)>
    [
      <.event(:type<request>, :1port, :$!ip)>
      <.event(:type<request>, :2port, :$!ip)>
      <.event(:type<request>, :3port, :$!ip)>
    ] ** 2
  }
}

my $storge;

role Event {
  has Event $.parent;
  has UInt  $.pos    = 0;
  has Str   $.rule;
  has       $.event;

  method min {...}
  method max {...}

  method match(Supply $supply, Str :$rule = "TOP") {
    my $parent = self.run: $rule;
    supply {
      whenever $supply -> $event {
        $parent.step: $event
      }
    }
  }
  method to-map(--> Map()) {
    self.^attributes.map(-> $a {
      $a.name.substr(2) => .<> with $a.get_value(self)
    })
  }

  method clone(*%p) {
    $.new: |$.to-map, |%p
  }

  method step($event) {
    my @nexts = $storge.query: $event;
    for @nexts -> $match {
      $match.run-next: $event
    }
  }

  method return {
    return emit self unless $!parent; # Should it emit $!made if it exist?
    # TODO: Call action? Rule name on $!rule. `$action."$!rule"(self)`?
    $!parent.run-next: :parent(self)
  }
  
  multi method store-submatch(Str $rule) {
    $.run-next(:hash(%(|$.hash, $rule => $!parent)))
  }
  
  multi method store-submatch {
    $.run-next(:list((|$.list, $!parent)))
  }

  method event(*%pars) {
    my multi run(0) {
      my %query is Map = %pars.kv.map: -> $key, $value {
        do if $value !~~ Associative {
          $key => %("==" => $value)
        } else {
          $key => $value
        }
      }
      $storge.add-query: :%query, :match(self)
    }
    my multi run($) {
      $.return
    }

    run $.pos
  }

  method run(Str $rule, UInt $pos = 0, |c) {
    self.new(:$rule, :$pos, :parent(self))."$rule"(|c)
  }

  method run-next($event?, *%pars, |c) {
    self.clone(|(:$event with $event), :pos($.pos + 1), |%pars)."$.rule()"(|c) # TODO: validate if pos exist
  }
}

