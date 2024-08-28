use Event;
unit class MetamodelX::Event is Metamodel::ClassHOW;

method new_type(|c) {
  my $type = callsame;
  $type.^add_parent: Event;
  $type
}

method to-map(\match --> Map()) {
  match.^attributes.map(-> $a {
    $a.name.substr(2) => .<> with $a.get_value(match)
  })
}

method clone(\match, *%p) {
  match.new: |match.^to-map, |%p
}

method step(\match, $event) {
  my @nexts = match.storage.search: $event;
  for @nexts -> $match {
    $match.^run-next: $event
  }
}

method return(\match) {
  my $rule = match.rule;
  ."$rule"(match) with match.actions;
  note "emit: {match.gist}";
  return emit match unless match.parent;
  # Should it emit match.made if it exist?
  match.parent.run-next: :parent(match)
}

multi method store-submatch(\match, Str $rule) {
  match.run-next(:hash(%(|match.hash, $rule => match.parent)))
}

multi method store-submatch(\match) {
  match.run-next(:list((|match.list, match.parent)))
}

method run(\match, Str $rule, UInt $pos = 0, |c) {
  match.new(:$rule, :$pos, :parent(match))."$rule"(|c)
}

method run-next(\match, $event?, *%pars, |c) {
  note "run-next: {match.gist}, $event";
  my $rule = match.rule;
  match.clone(|(:$event with $event), :pos(match.pos + 1), |%pars)."$rule"(|c) # TODO: validate if pos exist
}
