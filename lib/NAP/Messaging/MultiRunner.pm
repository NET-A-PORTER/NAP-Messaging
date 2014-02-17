package NAP::Messaging::MultiRunner;
use NAP::policy 'class','tt';
extends 'NAP::Messaging::Runner';
use NAP::Messaging::Runner::ChildSupervisor;
use POSIX ':sys_wait_h';
use Hash::Util::FieldHash qw(fieldhash);

# ABSTRACT: multi-runner that partitions subscriptions between groups of children

=head1 SYNOPSIS


In the application's configuration:

  <runner>
   <instances>
    destination /queue/sizing
    destination /queue/stock
    instances 5
   </instances>
   <instances>
    destination /queue/product_info
    destination /queue/command
    instances 8
   </instances>
  </runner>

In the launching script:

  #!/usr/bin/env perl
  use NAP::policy 'tt';
  use NAP::Messaging::MultiRunner;

  NAP::Messaging::MultiRunner->new('MyApp')->run_multiple;

=head1 DESCRIPTION

Fork a number of children, run the L<NAP::Messaging>-based application
in each of them, and re-start them if they die.

Children are killed (C<SIGTERM>) when:

=for :list
* this object is destroyed
* the supervisor process ends
* the supervisor process receives C<SIGINT>, C<SIGTERM> or C<SIGQUIT>

It is possible to have different groups of child processes consuming from
a subset of destinations. After a child is forked off, it will only
subscribe to the destinations configured for its group, instead of all
the destinations the application can consume from.

Most of the handling of children is done via
L<NAP::Messaging::Runner::Role::MultiChildSupervisor>.

=attr C<stopping>

Boolean. True if we just received a signal, and are now killing
children.  Has a trigger to propagate the "stopping" information
across all supervisors. Each supervisor sets (via a callback) this
attribute; in the trigger we set the C<stopping> attribute on all
other supervisor, to prevent them from spawning new children while
we're trying to shut down.

=cut

has stopping => (
    is => 'ro',
    writer => '_set_stopping',
    isa => 'Bool',
    default => 0,
);

=attr C<consumers>

An array-ref of L<NAP::Messaging::Runner::ChildSupervisor>, provided
by L<NAP::Messaging::Runner::Role::MultiChildSupervisor>.

Before running the consumer code, the the sub-process will call
L</limit_destinations_to> with the value of the C<destination>
instance config key.

=cut

with 'NAP::Messaging::Runner::Role::MultiChildSupervisor' => {
    name => 'consumer',
    instances_config_key => 'instances',
};

=method C<consumer_children_wanted>

Groups and number of consumers to spawn, uses the C<instances> config
key.

If the config key is absent, it behaves like it were specified with
value C<1>.

If the configured value is a number, a single group of children will
be created, subscribing to all destinations, with the specified number
of children.

Otherwise, the value has to be an array ref, and each member is a
hash-ref like:

  {
    destination => [ '/queue/some', '/queue/other', ],
    instances => 5,
  }

If the C<instances> value is not there (or C<undef>), it defaults to
1.

=cut

around consumer_children_wanted => sub {
    my ($orig, $self) = (shift, shift);

    my $instances = $self->$orig(@_);

    return [ map { +{
        ($_->{destination} ? (
            # convert legacy destination config to method/args pair
            setup => {
                method => 'limit_destinations_to',
                args => $_->{destination},
            },
        ) : ()),
        %{$_},
    } } @{$instances} ];
};

=attr C<limit_destinations_to>

This gets set (by each supervisor in L</consumers>) to the set of
destinations a child process should subscribe to. It can be a string
or an array-ref of strings.

See L</subscriptions> for more details.

=cut

has limit_destinations_to => (
    is => 'rw',
    isa => 'ArrayRef|Str',
);

=method C<subscriptions>

If L</limit_destinations_to> is set, we intersect the destinations
obtained from the C<appclass> with the strings in
L</limit_destinations_to>, then return the intersection.

This means that:

=for :list
* you cannot add subscriptions, only remove them
* you have to specify all destinations you want a child to be subscribed to
* there is no easy way to say "all but this"

The last point is a feature: if you're partitioning your consumers,
it's a good idea to be very explicit about what you want to happen.

=cut

around subscriptions => sub {
    my ($orig,$self) = @_;

    my @subs = $self->$orig;
    my $limit_to = $self->limit_destinations_to;
    return @subs unless $limit_to;
    my %to_subscribe;
    @to_subscribe{
        map { s{^/*}{/}r } (ref($limit_to) ? @{$limit_to} : $limit_to)
    } = ();

    return grep {
        exists $to_subscribe{ $_->{destination} =~ s{^/*}{/}r }
    } @subs;
};

=method C<BUILD>

"After" modifier. Keep track of this instance, to stop all its
children at C<END> time.

=method C<DEMOLISH>

"Before" modifier: stop all my children.

"After" modifier: stop tracking this instance.

=cut

# yes, this is a per-process global, we want to stop all running
# instances at process end, to make sure all children are stopped
fieldhash my %instances;

sub BUILD {}
after BUILD => sub { $instances{$_[0]} = $_[0] };
sub DEMOLISH {}
before DEMOLISH => sub { $_[0]->stop_children };

END {
    $_->stop_children for values %instances;
}
our @trapped_signals = qw(INT TERM QUIT);
for my $signal (@trapped_signals) {
    ## no critic RequireLocalizedPunctuationVars
    $SIG{$signal} = sub { $_->stop_children for values %instances };
}

=method C<run_multiple>

Enters an infinite loop:

=for :list
* fork up to the needed number of children, via L</fork_all>
* wait for a child to die, or a signal to be received
* if a child died, log the event and update the internal status via L</remove_child>

=cut

sub run_multiple {
    my ($self) = @_;

    $0 .= " (supervisor)";
    while (not $self->stopping) {
        $self->fork_all;

        my $dead_child = waitpid(-1,0);
        next if $dead_child < 1; # interrupted by a signal

        my $exit_code = ${^CHILD_ERROR_NATIVE};
        my $exit_message = 'unclear death';
        if (WIFEXITED($exit_code)) {
            my $status = WEXITSTATUS($exit_code);
            $exit_message = "normal exit, status $status";
        }
        elsif (WIFSIGNALED($exit_code)) {
            my $signal = WTERMSIG($exit_code);
            $exit_message = "killed by signal $signal";
        }
        $self->appclass->log->warn("Process $dead_child died ($exit_message), starting a new one");

        $self->remove_child($dead_child);
    }
}

=method C<run_consumer_child>

Delegate to L<NAP::Messaging::Runner/run>.

=cut

sub run_consumer_child { shift->run }


=method C<remove_child>

Delegate to C<remove_child> of each member of L</consumers>.

=method C<fork_all>

Delegate to C<fork_all> of each member of L</consumers>.

=method C<stop_children>

Delegate to C<stop_children> of each member of L</consumers>.

=method C<extract_child_config>

Delegate to C<extract_child_config> of each member of L</consumers>.

=cut

# Empty methods for NAP::Messaging::Runner::Role::MultiChildSupervisor
# to hook
sub fork_all { }
sub stop_children { $_[0]->_set_stopping(1) }
sub remove_child { }
sub extract_child_config { [] }
