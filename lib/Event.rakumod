use nqp;
use EEL::Metadata;
unit class Event is Capture is Any;


has Instant $.timestamp is rw = now;
has Str $.event-id = event-id();
has Event        $.parent;
has Str          $.rule     = 'TOP';
has              @.pos;
has UInt         $.index    = 0;
has              $.data;
has              $.actions;
has              $.made;
method make($value) { $!made = $value; self }
method ast { $!made }
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

method parse(|) {
  die 'The legacy Event.parse runner was removed; use Supply.match';
}

# Internal runtime hook: compiled closures retain this Capture instance.
method EEL-capture {
  my $view = Event.new(:parent($!parent), :rule($!rule), :pos(@!pos), :index($!index),
    :data($!data), :actions($!actions), :made($!made),
    :args($!args), :timestamp($!timestamp), :event-id($!event-id),
    :hash(self.hash), :list(self.list));
  $view.EEL-captures(self.EEL-hash);
  $view
}
method EEL-merge-fields(Event:D $child, Event $baseline = Event) {
  for $child.^attributes -> $attribute {
    next if $attribute.package === Event || $attribute.package === Capture;
    my $value = $attribute.get_value($child);
    next if $baseline.defined && $value eqv $attribute.get_value($baseline);
    my $slot := $attribute.get_value(self);
    if nqp::iscont($slot) { nqp::assign($slot,nqp::decont($value)) }
    else { $attribute.set_value(self,$value) }
  }
  self
}
method EEL-adopt(Event:D $child) {
  $!made = $child.made;
  for $child.^attributes -> $attribute {
    next if $attribute.package === Event || $attribute.package === Capture;
    my $slot := $attribute.get_value(self);
    my $value = $attribute.get_value($child);
    if nqp::iscont($slot) { nqp::assign($slot, nqp::decont($value)) }
    else { $attribute.set_value(self, $value) }
  }
  self.EEL-positions($child.list);
  self.EEL-captures($child.hash.Hash);
  self
}
method EEL-positions(@values) {
  my $list = @values.List;
  $list.elems;
  nqp::bindattr(self, Capture, '@!list', nqp::getattr(nqp::decont($list), List, '$!reified'));
  self
}
method EEL-position(Int $index, $value) {
  my @values = self.list;
  @values[$index] = @values[$index].defined
    ?? (@values[$index] ~~ Array ?? [|@values[$index], $value] !! [@values[$index], $value])
    !! $value;
  self.EEL-positions(@values)
}
# A mutable view of Capture storage, also shared by public capture views.
method EEL-hash {
  my $hash := nqp::create(Hash);
  my $storage := nqp::getattr(self,Capture,'%!hash');
  unless nqp::ishash($storage) { $storage := nqp::hash; nqp::bindattr(self,Capture,'%!hash',$storage) }
  nqp::bindattr(nqp::decont($hash),Map,'$!storage',$storage);
  $hash
}
method EEL-add-capture(Str $name,$value) {
  return self unless $name.chars;
  my %hash := self.EEL-hash;
  %hash{$name} = (%hash{$name}:exists)
    ?? (%hash{$name} ~~ Array ?? [|%hash{$name},$value] !! [%hash{$name},$value])
    !! $value;
  self
}
method EEL-index { $!index }
method EEL-identify { $!event-id = event-id(); self }
method EEL-accept($data, UInt :$index) { $!data = $data; $!index=$index if $index.defined; self }
method EEL-captures(Hash:D $captures) {
  my $storage := nqp::getattr(nqp::decont($captures), Map, '$!storage');
  unless nqp::ishash($storage) {
    $storage := nqp::hash;
    nqp::bindattr(nqp::decont($captures), Map, '$!storage', $storage);
  }
  nqp::bindattr(self, Capture, '%!hash', $storage);
  self
}
method EEL-args(Capture:D $args) { $!args = $args; self }

# Existing capture methods win normal dispatch; only missing methods reach here.
method FALLBACK(Str:D $name, |args) {
  if $!data ~~ Associative {
    return $!data{$name} if ($!data{$name}:exists) && !args.list && !args.hash;
  } elsif $!data.defined && $!data !=== self {
    return $!data."$name"(|args);
  }
  X::Method::NotFound.new(:method($name), :typename(self.^name)).throw
}
# Like the default Regex cursor, failure of a delimiter goal is ordinary failure.
# Applications may override this hook to report or throw a useful diagnostic.
method FAILGOAL($goal) { False }

method clone(*%p) {
  my @list = @.list;
  my %hash = %.hash;
  $.new: |to-map(self), :@list, :%hash, |%p
}

multi method gist(::?CLASS:D:) {
    [
        "{$!rule}: ｢" ~ (.gist with $!data) ~ '｣' ~ "   # { .subst(/\n/, "␤").subst(/\t/, "␉") with $.^find_method($!rule).?source }",
        do for |@.list.pairs, |%.hash.pairs.sort -> (:key($i), :value($submatch)) {
             "$i => $submatch.gist()"
        }.join.indent: 4
    ].join: "\n"
}

