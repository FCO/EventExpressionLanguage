use Event;
unit class MetamodelX::Event is Metamodel::ClassHOW;

method compose(Mu $type, |options) {
  $type.^add_parent(Event) unless $type.^parents(:local).grep({ .^isa(Event) }).elems;
  callsame
}
