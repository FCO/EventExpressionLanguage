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
  method match(Supply $supply, Str :$rule = "TOP") {
    supply {
      whenever $supply -> $ev {
        self!step($ev)
      }
    }
  }
  
  method !step($ev) {
    my @nexts = $storge.query: $ev;
  }

  method event(*%pars) {
    my $ev      = $*EV;
    my $current = self;

    my %query is Map = %pars.kv.map: -> $key, $value {
      $key => "==" => $value
    }
    $storge.add-query: :%query, :$current
  }
}

class knocked-the-secret does Event {
  has $.id;

  method TOP {
    my $ev      = $*EV;
    my $current = self;

    my @code = [
      -> $/ { $<first><port> == 1 },
      -> $/ { $!id //= $<first><ip> },
      -> $/ { $<second><port> == 2 && $<second><ip> eq $!id },
      -> $/ { $<third><port>  == 3 && $<third><ip>  eq $!id },
    ];

    sub again(UInt $count = 1, $while = 1) {
      return unless $count > 0 || $while;
      my %event is Map = :type<request>;
      my &*NEXT = -> $ev {
        $current<first> = $ev;
        return unless @code[0].($current)
        @code[1].($current);

        my %event is Map = :type<request>;
        my &*NEXT = -> $ev {
          $current<second> = $ev;
          return unless @code[2].($current);

          my %event is Map = :type<request>;
          my &*NEXT = -> $ev {
            $current<second> = $ev;
            return unless @code[3].($current);

            again $count - 1, $while - 1;
            if !$count && $while {
              emit $current
            }
          }
          $.event: |%event;
        }
        $.event: |%event;
      }
      $.event: |%event;
    }

    again 2
  }
}
