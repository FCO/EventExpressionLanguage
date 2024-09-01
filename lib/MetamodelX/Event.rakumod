use Event;
unit class MetamodelX::Event is Metamodel::ClassHOW;

method new_type(|c) {
  my $type = callsame;
  $type.^add_parent: Event;
  $type
}
