use Event;
use EEL::Metadata;
unit module EEL::Input;

class Snapshot {
    has Associative $.fields is required;
    has Bool $.typed = False;
    has Mu $.object-type;
}

class PreparedInput is export { has $.event is required; has Snapshot $.view is required }

# Matching sees a stable view of object accessors; captures retain the object.
sub snapshot($input, Str :$timestamp-field = 'timestamp' --> Snapshot) is export {
    return $input if $input ~~ Snapshot;
    if $input ~~ Associative {
        my %fields = $input.Map;
        if $timestamp-field ne 'timestamp' {
            %fields<timestamp>:delete;
            %fields<timestamp> = $input{$timestamp-field} if $input{$timestamp-field}:exists;
        }
        for metadata(%fields).kv -> $key, $value { %fields{$key} = $value }
        return Snapshot.new(:fields(%fields.Map), :object-type($input.WHAT));
    }
    die 'EEL input events must be defined values' unless $input.defined;
    my %fields;
    for $input.^attributes -> $attribute {
        next unless $attribute.has_accessor;
        next if $attribute.package === Event || $attribute.package === Capture;
        my $name = $attribute.name.substr(2);
        next if %fields{$name}:exists;
        %fields{$name} = $input."$name"();
    }
    if $input ~~ Event { %fields<timestamp> = $input.timestamp; %fields<event-id> = $input.event-id }
    if $timestamp-field ne 'timestamp' {
        my $value = %fields{$timestamp-field};
        my $exists = %fields{$timestamp-field}:exists;
        %fields<timestamp>:delete;
        %fields<timestamp> = $value if $exists;
    }
    for metadata(%fields).kv -> $key, $value { %fields{$key} = $value }
    %fields<type> = $input.WHAT unless %fields<type>:exists;
    Snapshot.new(:fields(%fields.Map), :typed, :object-type($input.WHAT))
}

# Event names remain case-sensitive. A type object can also match a tagged raw
# event without resolving arbitrary class names from the input.
sub type-equal($actual, $expected --> Bool) is export {
    if !$expected.DEFINITE {
        return so $actual.^isa($expected) unless $actual.DEFINITE;
        return $actual eq $expected.^name if $actual ~~ Str;
        return False;
    }
    return $actual.^name eq $expected if !$actual.DEFINITE && $expected ~~ Str;
    so $actual eqv $expected
}

sub selected-kind($input, $selector, $view = snapshot($input) --> Bool) is export {
    if !$selector.DEFINITE {
        return True if $view.object-type.^isa($selector);
        return False if $view.typed || !($view.fields<type>:exists);
        return type-equal($view.fields<type>, $selector);
    }
    return True if $view.typed && $view.object-type.^name eq $selector;
    ($view.fields<type>:exists) && type-equal($view.fields<type>, $selector)
}
