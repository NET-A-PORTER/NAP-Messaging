package NAP::Messaging::Catalyst::Controller::JMS;
use NAP::policy 'class';

# ABSTRACT: Controller base class for our messaging consumers

=head1 DESCRIPTION

You don't really use this module directly,
L<NAP::Messaging::Role::ConsumesJMS> creates your controllers
automatically using this class as their base. This is a subclass of
L<Catalyst::Controller::JMS>

=cut

BEGIN { extends 'Catalyst::Controller::JMS' }

=head1 Actions

=head2 C<begin>

The default C<begin> we get from L<Catalyst::Controller::JMS> has a
C<ActionClass> of L<Catalyst::Action::Deserialize>. We add the
L<NAP::Messaging::Catalyst::ActionRole::DeserialiseFailure> role to
it, to stash the de-serialisation errors. This way, the
message-handling actions created by
L<NAP::Messaging::Role::ConsumesJMS> can send a sensible error message
to the DLQ.

=cut

sub begin :ActionClass('Deserialize') Does('+NAP::Messaging::Catalyst::ActionRole::DeserialiseFailure') {}
