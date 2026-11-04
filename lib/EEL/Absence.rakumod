# A successful zero-consumption negative assertion. All times are event times.
unit class EEL::Absence;
has Str $.pattern is required;
has Instant $.started-at is required;
has Instant $.confirmed-at is required;
has Str $.reason is required;
has Mu $.witness;
method witness { $!witness.defined ?? $!witness !! Nil }
method Bool { True }
method gist { "absence({$!pattern}, {$!reason}, {$!confirmed-at})" }
