use QueryStorage;
unit class Event is Any;

my QueryStorage $storage .= new;

has Event        $.parent;
has Str          $.rule     = 'TOP';
has              @.pos;
has UInt         $.index    = 0;
has              $.hash-event;
has QueryStorage $.storage = $storage;
has              $.actions;
has              $.made;
has Capture      $.args;

sub run(\match ( :$rule, :$args, | )) {
  match."$rule"(|$args.Capture)
}

method parse(Supply $supply, Str :$rule = "TOP", |args) {
  my $match := run self.new: :$rule, :args(args);
  say $match;
  supply {
    whenever $supply -> $event {
      for $storage.search: $event -> \match {
        say match;
        run match;
      }
    }
  }
}

method clone(*%p) {
  my sub to-map(\match --> Map()) {
    match.^attributes.map(-> $a {
      $a.name.substr(2) => .<> with $a.get_value(match)
    })
  }

  $.new: |to-map(self), |%p
}

use Pattern;
my $pattern = Pattern.bless: :name<event>;
$pattern.add-step: my method (*%pars) {
    say 'step: 1';
    my %query is Map = %pars.kv.map: -> $key, $value {
      do if $value !~~ Associative {
        $key => %("==" => $value)
      } else {
        $key => $value
      }
    }
    HandledReturn::AddToStorage.new: :match(self), :$!storage, :%query
}

$pattern.add-step: my method (*%pars) {
    say 'step: 2';
    note "RUNNING: {self.gist}"
}
::?CLASS.^add_method: 'event', $pattern;
say $pattern;


