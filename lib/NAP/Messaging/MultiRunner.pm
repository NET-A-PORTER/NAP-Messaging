package NAP::Messaging::MultiRunner;
use NAP::policy 'class','tt';
extends 'NAP::Messaging::Runner';
use NAP::Messaging::Runner::ChildSupervisor;
use POSIX ':sys_wait_h';

# ABSTRACT: subclass of NAP::Messaging::Runner to supervise multiple consumers

=head1 SYNOPSIS

In the application's configuration:

   <runner>
    instances 5
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

It is technically possible to have more than one instance of this
class, but it hasn't been tested. Mostly, because I can't see a use
for it.

Most of the handling of children is done via
L<NAP::Messaging::Runner::ChildSupervisor> with the help of
L<NAP::Messaging::Runner::Role::Multi>.

=cut

=attr C<consumers>

A L<NAP::Messaging::Runner::ChildSupervisor>. The number of instances
is obtained calling L</consumer_children_wanted>. The children will
execute L<NAP::Messaging::Runner::Role::Multi/run_consumer_child>.

=cut

has consumers => (
    is => 'ro',
    isa => 'NAP::Messaging::Runner::ChildSupervisor',
    lazy_build => 1,
    handles => [qw(remove_child fork_all stop_children)],
);
sub _build_consumers {
    my ($self) = @_;

    return NAP::Messaging::Runner::ChildSupervisor->new({
        name => 'consumer',
        trapped_signals => \@NAP::Messaging::Runner::Role::Multi::trapped_signals,
        on_stopping => sub { $self->stopping(1) },
        logger => $self->appclass->log,
        instances => $self->consumer_children_wanted,
        code => sub { $self->run_consumer_child },
    })
}

with 'NAP::Messaging::Runner::Role::Multi';

=method C<remove_child>

Delegate to L</consumers> C<remove_child>.

=method C<fork_all>

Delegate to L</consumers> C<fork_all>.

=method C<stop_children>

Delegate to L</consumers> C<stop_children>.

=method C<consumer_children_wanted>

Number of consumers to spawn, uses the C<instances> config key,
defaults to 1.

=cut

sub consumer_children_wanted {
    my ($self) = @_;

    $self->appclass->config->{runner}{instances} //
    1;
}
