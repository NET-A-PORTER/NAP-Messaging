package NAP::Messaging::Catalyst::ActionRole::DeserialiseFailure;
use NAP::policy 'role';

# ABSTRACT: Action Role to stash de-serialisation errors

=head1 DESCRIPTION

You don't really use this module directly,
L<NAP::Messaging::Catalyst::Controller::JMS> applies this role to its
C<begin> actiions.

=head1 METHODS

=head2 C<serialize_bad_request>

Method called by L<Catalyst::Action::Deserialize> when
de-serialisation fails. We just stash the error.

=cut

sub serialize_bad_request {
    my ( $self, $c, $content_type, $error ) = @_;

    $c->stash->{deserialise_error} = $error;

    return;
}
