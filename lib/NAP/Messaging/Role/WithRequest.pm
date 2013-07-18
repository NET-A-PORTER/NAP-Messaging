package NAP::Messaging::Role::WithRequest;
use NAP::policy 'role','tt';

# ABSTRACT: have a request

=head1 Attributes provided

=head2 C<request>

Shortcut for C<< $the_application->request >>.

=cut

requires '_c';

sub request {
    return shift->_c->request
}
