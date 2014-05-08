package NAP::Messaging::Timing;
use NAP::policy 'class','tt';
use NAP::Logging::JSON;
use NAP::Messaging::Types qw(LogLevel LogLevelName);
use Time::HiRes qw(gettimeofday tv_interval);
use Tie::IxHash;
use Moose::Util::TypeConstraints;

# ABSTRACT: simple object to log timing

=head1 SYNOPSIS

  my $t = NAP::Messaging::Timing->new({
     logger => $ctx->timing_log,
     details => {some => ['useful,'info']}
  });

  # later

  $t->stop(more=>'info');

This will log, at the levels specified by L</start_log_level> and
L</stop_log_level>:

  { "event":"start","some":["useful","info"] }
  { "event":"stop","time_taken":1.4553,"some":["useful","info"],"more":"info" }

The number in the C<time_taken> field is the elapsed time, in seconds,
between the two calls.

=head1 DESCRIPTION

This object uses L<Time::HiRes> to keep track of elapsed time, and
logs start / stop events to the provided logger, and
L<NAP::Logging::JSON> to log JSON strings.

If you don't call L</stop>, it will be called automatically on object
destruction, so you can make your time measurements exception-safe.

=attr C<start_ts>

The result of L<Time::HiRes/gettimeofday> at the time the object was
constructed.

=cut

has start_ts => (
    is => 'ro',
    builder => '_build_start_ts',
);
sub _build_start_ts {
    my ($self) = @_;

    return [gettimeofday];
}

=attr C<details>

Araryref of pairs, defaults to C<[]>. If provided, these values will
be logged, as key=value pairs, for both the start and stop events.

=cut

my $pair_array_name = __PACKAGE__ . '::PairArray';
subtype $pair_array_name,
    as 'ArrayRef',
    where { @$_ %2 == 0 },
    message { 'An array of pairs must have an even number of elements' };
my $pair_array_type = Moose::Util::TypeConstraints::find_type_constraint($pair_array_name);

has details => (
    is => 'ro',
    isa => $pair_array_type,
    default => sub { [] },
);

=method C<add_details>

  $t->add_details(%hash);

Allows you to add kay-value pairs to the L</details>. They will be
appended to whatever is already there.

=cut

sub add_details {
    my ($self,@pairs) = @_;

    $pair_array_type->assert_valid(\@pairs);

    push @{$self->details}, @pairs;
    return;
}

=attr C<logger>

Should usually be set to L<NAP::Messaging::Catalyst/timing_log>.

=cut

has logger => (
    is => 'ro',
    required => 1,
);

=attr C<start_log_level>

The L<log level name|NAP::Messaging::Types/LogLevelName> at which the
start event is logged. Default: C<INFO>.

=cut

has start_log_level => (
    is => 'ro',
    isa => LogLevelName,
    default => 'INFO',
);

=attr C<stop_log_level>

The L<log level name|NAP::Messaging::Types/LogLevelName> at which the
stop event is logged. Default: C<INFO>.

=cut

has stop_log_level => (
    is => 'ro',
    isa => LogLevelName,
    default => 'INFO',
);

=attr C<stopped>

Boolean, defaults to false. It's set to true by the L</stop> method.

=cut

has stopped => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

sub _log_start {
    my ($self) = @_;

    $self->logger->log(to_LogLevel($self->start_log_level), logmsg event=>'start', @{$self->details});
}

=method C<stop>

  $t->stop(some => 'info');

Logs a "stop" line containing the time elapsed since the object was
constructed. All of L</details>, and the passed hash will be part of
the log message.

Sets L</stopped> to true; if called when L</stopped> is already true,
does nothing. You can only stop a timer once.

=cut

sub stop {
    my ($self,@extra) = @_;

    return if $self->stopped;

    my $elapsed = tv_interval($self->start_ts,[gettimeofday]);

    $self->add_details(@extra);
    $self->logger->log(to_LogLevel($self->stop_log_level),
        logmsg event=>'stop',
        time_taken => $elapsed,
        @{$self->details},
    );
    $self->stopped(1);
}

=method C<BUILD>

Logs a "start" line, containing L</details>.

=cut

sub BUILD {
    shift->_log_start;
}

=method C<DEMOLISH>

Calls L</stop>, so that, even if you don't call it explicitly, a
"stop" line is always logged.

=cut

sub DEMOLISH {
    shift->stop;
}
