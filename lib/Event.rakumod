use QueryStorage;
unit class Event is Capture is Any;

my QueryStorage $storage .= new;

has Event        $.parent;
has Str          $.rule     = 'TOP';
has              @.pos;
has UInt         $.index    = 0;
has              $.data;
has QueryStorage $.storage  = $storage;
has              $.actions;
has              $.made;
has Capture      $.args;

my sub to-map(\match --> Map()) {
  to-list match
}
my sub to-list(\match) {
  match.^attributes.grep(*.has_accessor).map(-> $a {
    $a.name.substr(2) => .<> with $a.get_value(match)
  })
}

multi method raku(::?CLASS:U:) {self.^name}

multi method raku(::?CLASS:D:) {
  "{ self.^name }.new({ to-list(self).grep(*.key ne 'storage')>>.raku.join: ', ' })"
}

sub run(\match) {
  my Str     $rule = match.rule // "TOP";
  my Capture $args = match.args // \();
  do with $args {
    match."$rule"(|.Capture)
  } else {
    match."$rule"()
  }
}

method parse(Supply $supply, Str :$rule = "TOP", |args) {
  my $match = run self.new: :$rule, :args(args), :pos[0], :0index;
  supply {
    whenever $supply -> $event {
      for $storage.search: $event -> \match {
        run match.clone: :data($event);
      }
    }
  }
}

method clone(*%p) {
  my @list = @.list;
  my %hash = %.hash;
  $.new: |to-map(self), :@list, :%hash, |%p
}

use Pattern;
my $pattern = Pattern.bless: :name<event>, :source("event(...)");
$pattern.add-step: sub add-query-to-storage($match, *%pars) {
    my %query is Map = %pars.kv.map: -> $key, $value {
      do if $value !~~ Associative {
        $key => %("==" => $value)
      } else {
        $key => $value
      }
    }
    my $storage = $match.storage;
    HandledReturn::AddToStorage.new: :$storage, :%query
}

$pattern.add-step: sub query-matched ($match, *%pars) {
    HandledReturn::Next
}
::?CLASS.^add_method: 'event', $pattern;

multi method gist(::?CLASS:D:) {
    [
        "{$!rule}: ｢" ~ (.gist with $!data) ~ '｣' ~ "   # { .subst(/\n/, "␤").subst(/\t/, "␉") with $.^find_method($!rule).?source }",
        do for |@.list.pairs, |%.hash.pairs.sort -> (:key($i), :value($submatch)) {
             "$i => $submatch.gist()"
        }.join.indent: 4
    ].join: "\n"
}

