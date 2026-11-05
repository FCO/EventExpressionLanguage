use Event;
use EEL::Query;
use EEL::Definition;
unit class EEL::Continuation;

class Frame {
    has Event $.context is required;
    has $.candidate;
    has Hash $.captures is required;
    has EEL::Definition $.definition is required;
    has Hash $.arrays = {};
    has Hash $.initialized = {};
    has @.todo;
    has @.layout;
    has Bool $.share-definition = False;
    has Str $.capture = '';
    has Hash $.saved-partition is rw = {};
    has Int $.saved-window-count = 0;
    has Bool $.saved-ignore = True;
}

# Forks rematerialize callbacks and restore local bindings without replaying code.
has Event $.result is required;
has Frame @.frames;
has EEL::Query $.query is rw;
has @.selections is rw;
has Int $.completed-at is rw = 0;
has Int $.result-order is rw = 0;
has @.shuffle is rw;
has @.shuffle-order is rw;
has @.shuffle-locals is rw;
has Bool $.branch-mode = False;
has $.shuffle-base is rw;
has Hash $.choices is rw = {};
has Hash $.partition is rw = {};
has Bool $.ignore-unexpected is rw = True;

has Int $.consumed is rw = 0;
has Bool $.identity-bound is rw = False;
has Int $.seen-through is rw = 0;
has %.used-events is rw;
has %.blocked-events is rw;
has $.first-time is rw;
has Int $.consume-base is rw = 0;
has Bool $.done is rw = False;
has @.goals;

has @.windows;
has $.positive is rw;
has @.negatives is rw;
has Bool $.terminal is rw = False;
has @.deferred is rw;
