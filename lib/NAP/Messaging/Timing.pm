package NAP::Messaging::Timing;
use NAP::policy 'class','tt';
use NAP::Logging::JSON;
use NAP::Messaging::Types qw(LogLevel LogLevelName);
use List::AllUtils qw(reduce);
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

Arrayref of pairs, defaults to C<[]>. If provided, these values will
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

Allows you to add key-value pairs to the L</details>. They will be
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

=attr C<graphite>

A L<Net::Graphite> object (or one with a compatible
L<send|Net::Graphite/send> method) used to send metrics.

=cut

has graphite => (
    is => 'ro',
    isa => duck_type(['send']),
    predicate => 'has_graphite',
);

=attr C<graphite_path>

An arrayref of fields to build the Graphite path from, which will be
appended to any L<path|Net::Graphite/path> in L</graphite>.

Each item can be one of:

=over

=item a string

Used verbatim.

=item a reference to a string

The corresponding key is looked up in L</details>.

=back

Use the L</append_path> method to add elements to the path.

=method C<append_path>

Appends path elements to L</graphite_path>.

=cut

has graphite_path => (
    is => 'ro',
    isa => 'ArrayRef',
    traits => ['Array'],
    handles => { append_path => 'push' },
    default => sub { [] },
);

=attr C<graphite_metrics>

Arrayref of L</details> fields to send as metrics.
The values must be either numbers or hashref where the leaf elements are numbers.

=cut

has graphite_metrics => (
    is => 'rw',
    isa => 'ArrayRef[Str]',
    traits => ['Array'],
    handles => {
        _add_metrics => 'push',
    },
    default => sub { [] },
);

=method C<add_metrics>

Like L</add_details>, but also adds the keys to L</graphite_metrics>
to send them to Graphite.

=cut

sub add_metrics {
    my ($self, @details) = @_;
    $self->add_details(@details);
    # add_details asserts that @details is a key/value list,
    # so we can safely feed it to keys via a hashref to get the names
    $self->_add_metrics(keys %{{@details}});
}

sub _log_start {
    my ($self) = @_;

    $self->logger->log(to_LogLevel($self->start_log_level), logmsg event=>'start', @{$self->details});
}

=method C<stop>

  $t->stop(some => 'info');

Logs a "stop" line containing the time elapsed since the object was
constructed. All of L</details>, and the passed hash will be part of
the log message.

If L</graphite> is set, also sends the registered L</graphite_metrics>.

Sets L</stopped> to true; if called when L</stopped> is already true,
does nothing. You can only stop a timer once.

=cut

sub stop {
    my ($self,@extra) = @_;

    return if $self->stopped;

    my $now = [gettimeofday];
    my $elapsed = tv_interval($self->start_ts,$now);

    $self->add_details(@extra);
    my @details = (
        event => 'stop',
        time_taken => $elapsed,
        @{$self->details},
    );
    $self->logger->log(to_LogLevel($self->stop_log_level),
        logmsg @details
    );
    if ($self->has_graphite) {
        my %details = @details;
        my $metrics = {
            map { $_ => $details{$_} }
            grep { defined $details{$_} }
            'time_taken', @{$self->graphite_metrics}
        };
        # turn $metrics, $path_field2, $path_field1 into
        # { $path_field1 => { $path_field2 => $metrics } }
        # looking up scalarrefs the path in %details
        $self->graphite->send(data => {
            $now->[0] => reduce {
                !ref($b)              ? { $b => $a }
              : defined $details{$$b} ? { $details{$$b} => $a }
              : $a
            } $metrics, reverse @{$self->graphite_path},
        });
    }
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
