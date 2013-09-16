package NAP::Messaging::MultiRunner::Partitioned;
use NAP::policy 'class','tt';
extends 'NAP::Messaging::Runner';
use NAP::Messaging::Runner::ChildSupervisor;

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
  use NAP::Messaging::MultiRunner::Partitioned;

  NAP::Messaging::MultiRunner::Partitioned->new('MyApp')->run_multiple;

=head1 DESCRIPTION

Very similar to L<NAP::Messaging::MultiRunner>, this also gives you
the ability to have different groups of child processes consuming from
a subset of destinations. After a child is forked off, it will only
subscribe to the destinations configured for its group, instead of all
the destinations the application can consume from.

B<NOTE>: this class can work the same way as
L<NAP::Messaging::MultiRunner>; it's provided as its own class in case
you know you won't ever need the additional flexibility, and would
prefer simpler code.

=cut

=attr C<consumers>

An array-ref of L<NAP::Messaging::Runner::ChildSupervisor>. Each
element will supervise a group of children. The groups and number of
instances is obtained calling L</consumer_children_wanted>. The
children will execute
L<NAP::Messaging::Runner::Role::Multi/run_consumer_child>, after
having set (in the sub-process) L</limit_destinations_to>.

=cut

has consumers => (
    is => 'ro',
    isa => 'ArrayRef[NAP::Messaging::Runner::ChildSupervisor]',
    lazy_build => 1,
);
sub _build_consumers {
    my ($self) = @_;

    my $instances = $self->consumer_children_wanted;
    if (not ref $instances) { # just a number
        return [
            NAP::Messaging::Runner::ChildSupervisor->new({
                name => 'consumer',
                trapped_signals => \@NAP::Messaging::Runner::Role::Multi::trapped_signals,
                on_stopping => sub { $self->stopping(1) },
                logger => $self->appclass->log,
                instances => $instances,
                code => sub { $self->run_consumer_child },
            })
          ];
    }

    my @ret;my $partition_number=1;
    for my $instance_config (@$instances) {
        push @ret, NAP::Messaging::Runner::ChildSupervisor->new({
            name => "consumer (partition $partition_number)",
            trapped_signals => \@NAP::Messaging::Runner::Role::Multi::trapped_signals,
            on_stopping => sub { $self->stopping(1) },
            logger => $self->appclass->log,
            instances => $instance_config->{instances},
            code => sub {
                $self->limit_destinations_to($instance_config->{destination});
                $self->run_consumer_child;
            },
        });
        ++$partition_number;
    }
    return \@ret;
}

with 'NAP::Messaging::Runner::Role::Multi';

=attr C<stopping>

Declared in L<NAP::Messaging::Runner::Role::Multi>; here we add a
trigger to propagate the "stopping" information across all
supervisors. Each supervisor sets (via a callback) this attribute; in
the trigger we set the C<stopping> attribute on all other supervisor,
to prevent them from spawning new children while we're trying to shut
down.

=cut

has '+stopping' => (
    trigger => sub {
        my ($self,$new,$old) = @_;
        if ($new && !$old) {
            $_->stopping(1) for @{$self->consumers};
        }
    },
);

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

=method C<remove_child>

Delegate to C<remove_child> of each member of L</consumers>.

=method C<fork_all>

Delegate to C<fork_all> of each member of L</consumers>.

=method C<stop_children>

Delegate to C<stop_children> of each member of L</consumers>.

=cut

sub remove_child {
    my ($self,$child) = @_;
    $_->remove_child($child) for @{$self->consumers};
}
sub fork_all {
    my ($self) = @_;
    $_->fork_all() for @{$self->consumers};
}
sub stop_children {
    my ($self,$signal) = @_;
    # During global destruction, the supervisors may already have been reaped
    $_->stop_children($signal) for grep { defined } @{$self->consumers};
}

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

sub consumer_children_wanted {
    my ($self) = @_;

    my $instances = $self->appclass->config->{runner}{instances};

    # nothing specified? 1 child
    return 1 unless defined $instances;
    # not an array? pass it through
    return $instances unless ref($instances);

    # an array? make sure we get at least 1 child per partition, if
    # not specified
    $_->{instances}//=1 for @$instances;
    return $instances;
}
