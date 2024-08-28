use QueryStorage;
unit class Event is Any;

has Event        $.parent;
has UInt         $.pos      = 0;
has Str          $.rule;
has              $.event;
has QueryStorage $.storage .= new;
has              $.actions;
has              $.made;

method parse(Supply $supply, Str :$rule = "TOP") {
  my $parent = self.^run: $rule;
  supply {
    whenever $supply -> $event {
      say $parent;
      $parent.^step: $event
    }
  }
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
    note "\$!storage.add: %query<>, {self.gist}";
    $!storage.add: %query, self
  }
  my multi run($) {
    note "run: {self.gist}";
    $.^return
  }

  run $.pos;
  self
}
