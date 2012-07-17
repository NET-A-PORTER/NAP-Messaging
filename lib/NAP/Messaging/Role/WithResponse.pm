package NAP::Messaging::Role::WithResponse;
use NAP::policy 'role';

# ABSTRACT: have a response

=head1 Attributes provided

=head2 C<response>

This is used by L<NAP::Messaging::Base::Consumer> to extract the
response to send back (if any).

=cut

has response => (
    is => 'rw',
    required => 0,
);
