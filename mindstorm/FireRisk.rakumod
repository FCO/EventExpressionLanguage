########################
# Emits a FireRisk event if its too hot and too dry on a given area
########################

event Temperature is generic-hash-event { has Int $.area; has Rat $.value }
event Humidity    is generic-hash-event { has Int $.area; has Rat $.value }

event FireRisk {
  has Int $.area;
  has Rat $.temparature;
  has Rat $.humidity;

  pattern TOP {
    [
      <hot> & <dry>
      <{ $<hot>.area == $<dry>.area }>
      { $!area = $<hot>.area }
    ] in 5min
    { $!temperature = $<hot>.value }
    { $!humidity    = $<dry>.value }
  }

  pattern hot {
    <Temperature> { $<Temperature>.value > 40 }
  }

  pattern dry {
    <Humidity>    { $<Humidity>.value < 20 }
  }
}
