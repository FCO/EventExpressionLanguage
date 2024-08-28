use lib 'lib';
use EEL;
event knocked-the-secret {

  has $.id;

  pattern TOP {
    [
      <first=.event(:type<request>)>  <{ $<first><port>  == 1 }> { $!id //= $<first><ip> }
      <second=.event(:type<request>)> <{ $<second><port> == 2 && $<second><ip> eq $!id }>
      <third=.event(:type<request>)>  <{ $<third><port>  == 3 && $<third><ip>  eq $!id }>
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
      whenever $supply -> $ev {
        my $*EV = $ev;
        $parent.step($ev)
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

  method step($ev) {
    my @nexts = $storge.query: $ev;
  }

  method return {
    $.clone(:event($*EV)).parent.run-next: :parent(self)
  }

  method event(*%pars) {
    given $.pos {
      when 0 {
        my %query is Map = %pars.kv.map: -> $key, $value {
          $key => "==" => $value
        }
        $storge.add-query: :%query, :match(self.clone: :$!parent, :pos($.pos + 1))
      }
      when 1 {
        $.return
      }
    }
  }

  method run(Str $rule, UInt $pos = 0, |c) {
    self.new(:$rule, :$pos, :parent(self))."$rule"(|c)
  }

  method run-next(*%pars, |c) {
    self.clone(:pos($.pos + 1), |%pars)."$.rule()"(|c)
  }
}

class knocked-the-secret does Event {
  has     $.id;
  has Num $.min = 2;
  has Num $.max = 2;

  method TOP {
    given $.pos {
      when 0 {
        self.run: 'event', :type<request>;
      }
      when 1 {
        $.clone(:hash{|$.hash, :first($.parent)});
      }
      when 2 {
        my $/ = self;
        my &code = { $<first><port> == 1 };
        return unless code;
        $.run-next
      }
      when 3 {
        my $/ = self;
        my &code = { $!id //= $<first><ip> };
        code;
        $.run-next
      }
      when 4 {
        self.run: 'event', :type<request>;
      }
      when 5 {
        $.clone(:hash{|$.hash, :second($.parent)});
      }
      when 6 {
        my $/ = self;
        my &code = { $<second><port> == 2 };
        return unless code;
        $.run-next
      }
      when 7 {
        self.run: 'event', :type<request>;
      }
      when 8 {
        $.clone(:hash{|$.hash, :third($.parent)});
      }
      when 9 {
        my $/ = self;
        my &code = { $<third><port> == 2 };
        return unless code;
        $.run-next
      }
    }
  }
}
