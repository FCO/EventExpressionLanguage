use MONKEY-TYPING;
use EEL::Runner;

# Keep this declaration at the compilation-unit root so the RakuAST frontend
# preserves Supply's original package name.
# augment changes the shared Supply class. Loading EEL installs this method;
# the event/pattern slang itself remains lexical.
augment class Supply {
    method made(Supply:D:) { self.map(*.made) }
    method ast(Supply:D:) { self.made }
    method match(Supply:D: *@patterns, :$reemit = False, :$actions, Str:D :$rule = 'TOP', Real :$lateness = 0, *%options --> Supply) {
        die "Unknown Supply.match option(s): {%options.keys.sort.join(', ')}" if %options;
        EEL::Runner.new(:@patterns, :$rule, :$lateness, :$actions).supply(self, :$reemit)
    }
}
