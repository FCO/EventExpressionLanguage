########################
# Emits a FireRisk event if its too hot and too dry on a given area
########################
use lib 'lib';
use EEL;

event FireRisk {
  pattern TOP {
    [
      | <hot> <dry($<hot><event><area>)>
      | <dry> <hot($<dry><event><area>)>
    ] 5min
  }

  pattern hot($area) {
    <event(|(:$area with $area), :type<temperature>, :value{'>' => 40 })>
  }

  pattern dry($area) {
    <event(|(:$area with $area), :type<humidity>, :value{'<' => 20 })>
  }
}
