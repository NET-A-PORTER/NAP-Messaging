package NAP::Messaging::Types;
use NAP::policy 'tt';

# ABSTRACT: type constraints used in L<NAP::Messaging>

=head1 SYNOPSIS

    use NAP::Messaging::Types qw(LogLevel LogLevelName);

    has log_level => (
        is => 'ro',
        isa => LogLevel,
        coerce => 1,
        default => 'INFO',
    );

    my $name = to_LogLevelName($obj->log_level);

=head1 DESCRIPTION

This module provides L<MooseX::Types> constraints used in
L<NAP::Messaging>.

=head1 TYPES

=cut

use MooseX::Types -declare => [qw(LogLevel LogLevelName)];
use MooseX::Types::Moose qw(Int Str);

use Log::Log4perl::Level ();

=head2 C<LogLevel>

A numeric L<Log::Log4perl> log level.
Coerces from L</LogLevelName>.

=cut

subtype LogLevel,
    as Int,
    where { Log::Log4perl::Level::is_valid($_) };

=head2 C<LogLevelName>

A string L<Log::Log4perl> log level name.
Coerces from L</LogLevel>.

=cut

subtype LogLevelName,
    as Str,
    where { !is_Int($_) && Log::Log4perl::Level::is_valid($_) };

# coercions must come after the types are defined
coerce LogLevel,
    from LogLevelName,
    via { Log::Log4perl::Level::to_priority($_) };

coerce LogLevelName,
    from LogLevel,
    via { Log::Log4perl::Level::to_level($_) };

=head1 SEE ALSO

L<Log::Log4perl::Level>
