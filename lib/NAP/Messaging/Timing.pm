package NAP::Messaging::Timing;
use NAP::policy 'class','tt';
use Time::HiRes qw(gettimeofday tv_interval);

# ABSTRACT: simple object to log timing

=head1 SYNOPSIS

  my $t = NAP::Messaging::Timing->new({
     logger => $ctx->timing_log,
     details => [qw(some useful info)],
  });

  # later

  $t->stop(qw(some more info));

This will log, at C<INFO> level:

  start|0|some|useful|info
  stop|1.4553|some|useful|info|some|more|info

The number in the second field is the elapsed time, in seconds,
between the two calls.

=head1 DESCRIPTION

This object uses L<Time::HiRes> to keep track of elapsed time, and
logs start / stop events to the provided logger.

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

Array ref, defaults to C<[]>. If provided, these values will be
logger, joined by C<|>, for both the start and stop events.

=cut

has details => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub { [] },
);

=attr C<logger>

Should usually be set to L<NAP::Messaging::Catalyst/timing_log>.

=cut

has logger => (
    is => 'ro',
    required => 1,
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

    $self->logger->info(join '|', 'start',0, @{$self->details});
}

=method C<stop>

  $t->stop(qw(some info));

Logs a "stop" line containing the time elapsed since the object was
constructed. Both L</details> and the passed arguments will be part of
the log message.

Sets L</stopped> to true; if called when L</stopped> is already true,
does nothing. You can only stop a timer once.

=cut

sub stop {
    my ($self,@extra) = @_;

    return if $self->stopped;

    my $elapsed = tv_interval($self->start_ts,[gettimeofday]);
    $self->logger->info(join '|', 'stop',$elapsed,@{$self->details},@extra);
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
